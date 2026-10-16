import Foundation

public struct CommandResult: Sendable, Hashable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs an executable by absolute path with an argv array. Never a shell string.
/// Returns the result for any exit code; throws only if the process could not start or timed out.
/// Tests inject a fake; `ProcessRunner.live` is the real one.
public typealias Runner = @Sendable (_ executable: String, _ arguments: [String]) async throws -> CommandResult

/// Absolute paths of the system tools macctl uses.
public enum Tool {
    public static let defaults = "/usr/bin/defaults"
    public static let osascript = "/usr/bin/osascript"
    public static let killall = "/usr/bin/killall"
    public static let swVers = "/usr/bin/sw_vers"
}
