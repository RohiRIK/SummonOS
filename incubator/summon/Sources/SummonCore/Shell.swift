import Foundation

/// Runs a tool by absolute path with an argv array and returns its combined stdout and stderr.
/// Injected everywhere so tests use a fake and never touch the real system.
public typealias Runner = @Sendable (String, [String]) async throws -> String

public enum RunnerError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(path: String, status: Int32, output: String)
    case timedOut(path: String, seconds: TimeInterval, output: String)
    case outputLimit(path: String, limit: Int)

    public var description: String {
        switch self {
        case let .timedOut(path, seconds, _):
            return "\((path as NSString).lastPathComponent) exceeded its \(seconds)-second deadline"
        case let .outputLimit(path, limit):
            return "\((path as NSString).lastPathComponent) output exceeded \(limit) bytes; output is incomplete"
        case let .failed(path, status, output):
            let name = (path as NSString).lastPathComponent
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "\(name) exited with \(status)" : "\(name) exited with \(status): \(trimmed)"
        }
    }
}

public enum Shell {
    /// Bounded execution off the main actor, with cancellation propagated to its process group.
    public static let live: Runner = { path, arguments in
        try checked(try await ProcessExecutor.run(path, arguments), path: path, options: .init())
    }

    public static func runSync(_ path: String, _ arguments: [String], options: ProcessOptions = .init()) throws -> String {
        try checked(ProcessExecutor.runSync(path, arguments, options: options), path: path, options: options)
    }

    private static func checked(_ result: ProcessOutput, path: String, options: ProcessOptions) throws -> String {
        guard result.status == 0 else { throw RunnerError.failed(path: path, status: result.status, output: result.output) }
        guard !result.truncated else { throw RunnerError.outputLimit(path: path, limit: options.maxOutputBytes) }
        return result.output
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
        let userDirs = ["\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.npm-global/bin"]
        let fallbackDirs = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin"]
        let rawDirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init)

        var seen = Set<String>()
        var dirs: [String] = []

        func add(_ dir: String) {
            guard !dir.isEmpty, !seen.contains(dir) else { return }
            seen.insert(dir)
            dirs.append(dir)
        }

        // The user's own folders first, as in their shell: a tool installed with bun or a script can be newer than
        // a Homebrew copy (two OpenCodes on one Mac: Homebrew 1.15 and bun 2.0).
        for dir in userDirs { add(dir) }
        for dir in rawDirs { add(dir) }
        for dir in fallbackDirs { add(dir) }

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
