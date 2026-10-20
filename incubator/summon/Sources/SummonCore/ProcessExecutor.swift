import Darwin
import Foundation

/// Limits apply while the process runs, before any output reaches a parser or a log file.
public struct ProcessOptions: Sendable {
    public var timeout: TimeInterval = 60
    public var terminationGrace: TimeInterval = 0.5
    public var maxOutputBytes = 1_048_576
    public var directory: URL?
    public var environment: [String: String]?
    public var includeStandardError = true
    public var logFile: URL?
    public var maxLogBytes = 5_242_880
    public var terminateDescendantsOnExit = false

    public init() {}
}

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let output: String
    public let truncated: Bool
}

/// A dedicated process group makes cancellation affect only this invocation and its descendants.
/// A synchronous POSIX loop runs on a worker thread; it never blocks the main actor or waits for a
/// descendant to close stdout. Processes that deliberately create a new session escape this boundary.
public enum ProcessExecutor {
    public static func run(_ path: String, _ arguments: [String], options: ProcessOptions = .init()) async throws -> ProcessOutput {
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try execute(path, arguments, options, cancellation) })
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    public static func runSync(_ path: String, _ arguments: [String], options: ProcessOptions = .init()) throws -> ProcessOutput {
        try execute(path, arguments, options, ProcessCancellation())
    }

    private static func execute(_ path: String, _ arguments: [String], _ options: ProcessOptions,
                                _ cancellation: ProcessCancellation) throws -> ProcessOutput {
        guard path.hasPrefix("/"), !([path] + arguments).contains(where: { $0.contains("\0") }),
              options.timeout.isFinite, options.timeout > 0,
              options.terminationGrace.isFinite, options.terminationGrace >= 0,
              options.maxOutputBytes >= 0, options.maxLogBytes >= 0 else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        if cancellation.cancelled { throw CancellationError() }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw posixError(errno) }
        let reader = descriptors[0], writer = descriptors[1]
        defer { close(reader) }
        var writerOpen = true
        defer { if writerOpen { close(writer) } }
        guard fcntl(reader, F_SETFL, O_NONBLOCK) != -1,
              fcntl(reader, F_SETFD, FD_CLOEXEC) != -1,
              fcntl(writer, F_SETFD, FD_CLOEXEC) != -1 else { throw posixError(errno) }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in [SIGTERM, SIGINT, SIGPIPE] { sigaddset(&defaults, signal) }
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        var mask = sigset_t()
        sigemptyset(&mask)
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, writer, STDOUT_FILENO))
        if options.includeStandardError {
            try check(posix_spawn_file_actions_adddup2(&actions, writer, STDERR_FILENO))
        } else {
            try check(posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0))
        }
        try check(posix_spawn_file_actions_addclose(&actions, reader))
        try check(posix_spawn_file_actions_addclose(&actions, writer))
        if let directory = options.directory {
            if #available(macOS 26, *) {
                try check(posix_spawn_file_actions_addchdir(&actions, directory.path))
            } else {
                try check(posix_spawn_file_actions_addchdir_np(&actions, directory.path))
            }
        }

        var logDescriptor: Int32 = -1
        if let file = options.logFile {
            logDescriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard logDescriptor >= 0 else { throw posixError(errno) }
        }
        defer { if logDescriptor >= 0 { close(logDescriptor) } }
        let env = (options.environment ?? ProcessInfo.processInfo.environment).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        guard !env.contains(where: { $0.contains("\0") }) else { throw CocoaError(.fileReadInvalidFileName) }
        let cArguments = ([path] + arguments).map { strdup($0) }
        let cEnvironment = env.map { strdup($0) }
        defer {
            cArguments.forEach { free($0) }
            cEnvironment.forEach { free($0) }
        }
        var argv = cArguments + [nil]
        var envp = cEnvironment + [nil]
        var pid: pid_t = 0
        try check(posix_spawn(&pid, path, &actions, &attributes, &argv, &envp))
        close(writer)
        writerOpen = false
        var reaped = false
        defer {
            if !reaped {
                kill(-pid, SIGKILL)
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            }
        }

        let began = ProcessInfo.processInfo.systemUptime
        var stoppedAt: TimeInterval?
        var timedOut = false
        var wasCancelled = false
        var output = Data()
        var logCount = 0
        var logTruncated = false
        var truncated = false
        var bytes = [UInt8](repeating: 0, count: 16_384)

        func drain() throws {
            // Bound each pass so a continuously noisy child cannot starve deadline checks.
            for _ in 0..<64 {
                let count = read(reader, &bytes, bytes.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN { return }
                    throw posixError(errno)
                }
                if count == 0 { return }
                let retained = min(count, max(0, options.maxOutputBytes - output.count))
                output.append(contentsOf: bytes.prefix(retained))
                truncated = truncated || retained < count
                if logDescriptor >= 0 {
                    let logged = min(count, max(0, options.maxLogBytes - logCount))
                    if logged > 0 { try writeAll(logDescriptor, Data(bytes.prefix(logged))) }
                    logCount += logged
                    logTruncated = logTruncated || logged < count
                }
            }
        }

        var waitStatus: Int32 = 0
        while true {
            try drain()
            let now = ProcessInfo.processInfo.systemUptime
            if stoppedAt == nil, cancellation.cancelled || now - began >= options.timeout {
                wasCancelled = cancellation.cancelled
                timedOut = !wasCancelled
                stoppedAt = now
                kill(-pid, SIGTERM)
            }
            if let stoppedAt, now - stoppedAt >= options.terminationGrace { kill(-pid, SIGKILL) }
            let waited = waitpid(pid, &waitStatus, WNOHANG)
            if waited == pid {
                reaped = true
                // A TERM-ignoring descendant may remain after its parent exits.
                if stoppedAt != nil || options.terminateDescendantsOnExit { kill(-pid, SIGKILL) }
                try drain()
                break
            }
            if waited == -1, errno != EINTR { throw posixError(errno) }
            var pollDescriptor = pollfd(fd: reader, events: Int16(POLLIN), revents: 0)
            _ = poll(&pollDescriptor, 1, 20)
            // POLLHUP remains readable when descendants have closed the pipe; avoid a busy loop.
            if pollDescriptor.revents & Int16(POLLHUP) != 0 { Thread.sleep(forTimeInterval: 0.01) }
        }
        if logDescriptor >= 0 {
            if logTruncated { try writeAll(logDescriptor, Data("\nsummon: log output truncated at \(options.maxLogBytes) bytes\n".utf8)) }
            if timedOut { try writeAll(logDescriptor, Data("\nsummon: deadline exceeded (\(options.timeout) seconds)\n".utf8)) }
            if wasCancelled { try writeAll(logDescriptor, Data("\nsummon: cancelled\n".utf8)) }
        }
        let text = String(decoding: output, as: UTF8.self)
        if wasCancelled { throw CancellationError() }
        if timedOut { throw RunnerError.timedOut(path: path, seconds: options.timeout, output: text) }
        let signal = waitStatus & 0x7f
        let status = signal == 0 ? (waitStatus >> 8) & 0xff : 128 + signal
        return ProcessOutput(status: status, output: text, truncated: truncated)
    }

    private static func check(_ code: Int32) throws {
        if code != 0 { throw posixError(code) }
    }

    private static func posixError(_ code: Int32) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private static func writeAll(_ descriptor: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = write(descriptor, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posixError(errno)
                }
                guard count > 0 else { throw posixError(EIO) }
                written += count
            }
        }
    }
}

/// Mutable cancellation state is shared only under this lock, including before spawn.
private final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var cancelled: Bool { lock.withLock { value } }
    func cancel() { lock.withLock { value = true } }
}
