import Foundation

// Tools that need a command-line tool go through `CommandRunner`. There is no "run any shell
// command" tool: executables come from a fixed allowlist, arguments are an array (never a shell
// string), and every run has a deadline and an output cap.

/// An absolute executable path. The live runner refuses any path not on its allowlist.
public struct Executable: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    // Read-only macOS tools used by diagnostics. Add here, then to the live allowlist, deliberately.
    public static let sysctl = Executable(rawValue: "/usr/sbin/sysctl")
    public static let vmStat = Executable(rawValue: "/usr/bin/vm_stat")
    public static let ps = Executable(rawValue: "/bin/ps")
    public static let df = Executable(rawValue: "/bin/df")
    public static let pmset = Executable(rawValue: "/usr/bin/pmset")
    public static let swVers = Executable(rawValue: "/usr/bin/sw_vers")
}

public struct Command: Sendable, Hashable {
    public var executable: Executable
    public var arguments: [String]
    public var timeoutSeconds: Double
    /// Stdout and stderr are each cut at this many bytes; `CommandOutput.truncated` says so.
    public var maxOutputBytes: Int

    public init(_ executable: Executable, _ arguments: [String] = [], timeoutSeconds: Double = 5,
                maxOutputBytes: Int = 256 * 1024)
    {
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }
}

public struct CommandOutput: Sendable, Hashable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var truncated: Bool

    public init(exitCode: Int32, stdout: String, stderr: String = "", truncated: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.truncated = truncated
    }
}

public enum CommandError: Error, Sendable, Hashable {
    case notAllowed(Executable)
    case launchFailed(String)
    case timedOut(Executable)
    case cancelled
}

/// Runs a `Command`. Inject `.live(...)` in the app and CLI, a fake in tests.
public struct CommandRunner: Sendable {
    public var run: @Sendable (Command) async throws -> CommandOutput

    public init(run: @escaping @Sendable (Command) async throws -> CommandOutput) {
        self.run = run
    }
}
