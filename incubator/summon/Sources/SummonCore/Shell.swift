import Foundation

/// Runs a tool by absolute path with an argv array and returns its combined stdout and stderr.
/// Injected everywhere so tests use a fake and never touch the real system.
public typealias Runner = @Sendable (String, [String]) async throws -> String

public enum RunnerError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(path: String, status: Int32, output: String)

    public var description: String {
        switch self {
        case let .failed(path, status, output):
            let name = (path as NSString).lastPathComponent
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\(name) exited with \(status)" : "\(name) exited with \(status): \(trimmed)"
        }
    }
}

public enum Shell {
    /// The real runner. The blocking wait runs on a GCD thread, never on a Swift concurrency thread.
    public static let live: Runner = { path, arguments in
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Shell.runSync(path, arguments))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static func runSync(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // One pipe for both streams: reading two pipes in sequence can deadlock when the second fills up.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        // Read as data arrives instead of to end-of-file: a child the command left running in the
        // background (`caffeinate … &`) keeps the pipe open, and reading to EOF would wait for it.
        let buffer = OutputBuffer()
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(chunk)
            }
        }
        try process.run()
        process.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.05)  // let the handler take what the process wrote just before exiting
        reader.readabilityHandler = nil
        let output = String(decoding: buffer.data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw RunnerError.failed(path: path, status: process.terminationStatus, output: output)
        }
        return output
    }

    /// Starts a process and does not wait for it (daemons such as `borders`, or GUI launches).
    public static func spawn(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// Collects pipe output from the readability handler's thread.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Finds executables the way a login shell would, plus the Homebrew and user bin folders
/// that GUI apps do not get on their PATH.
public struct ToolLocator: Sendable {
    public var searchPath: [String]
    public var isExecutable: @Sendable (String) -> Bool

    public init(searchPath: [String], isExecutable: @escaping @Sendable (String) -> Bool) {
        self.searchPath = searchPath
        self.isExecutable = isExecutable
    }

    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) -> ToolLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for extra in ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.npm-global/bin", "/usr/bin", "/bin"]
        where !dirs.contains(extra) {
            dirs.append(extra)
        }
        return ToolLocator(searchPath: dirs) { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    }

    public func find(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return isExecutable(name) ? name : nil
        }
        for dir in searchPath where !dir.isEmpty {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if isExecutable(candidate) {
                return candidate
            }
        }
        return nil
    }
}
