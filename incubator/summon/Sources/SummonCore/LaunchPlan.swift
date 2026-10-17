import Foundation

/// A process to start: absolute executable plus argv. Values only ever travel as argv, never spliced into script text.
public struct LaunchPlan: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum TerminalApp: String, Sendable, Equatable, CaseIterable {
    case ghostty
    case terminal
}

public enum AgentLauncher {
    /// Agents refuse to remember trust for the home folder, so a launch from `~` starts in `~/Work` when it exists.
    public static func workingDirectory(current: String, home: String, workExists: Bool) -> String {
        let normalizedCurrent = (current as NSString).standardizingPath
        let normalizedHome = (home as NSString).standardizingPath
        if normalizedCurrent == normalizedHome && workExists {
            return (normalizedHome as NSString).appendingPathComponent("Work")
        }
        return normalizedCurrent
    }

    /// Opens a new terminal window running `agentArgv` in `directory`.
    public static func terminalPlan(agentArgv: [String], directory: String, terminal: TerminalApp) -> LaunchPlan {
        switch terminal {
        case .ghostty:
            return LaunchPlan(
                executable: "/usr/bin/open",
                arguments: ["-na", "Ghostty", "--args", "--working-directory=\(directory)", "-e"] + agentArgv
            )
        case .terminal:
            // A fixed script; the directory and every argv item arrive as osascript argv and are quoted there.
            let script = [
                "on run argv",
                "set cmd to \"cd \" & quoted form of (item 1 of argv) & \" &&\"",
                "repeat with i from 2 to (count of argv)",
                "set cmd to cmd & \" \" & quoted form of (item i of argv)",
                "end repeat",
                "tell application \"Terminal\"",
                "activate",
                "do script cmd",
                "end tell",
                "end run",
            ]
            var arguments: [String] = []
            for line in script {
                arguments.append("-e")
                arguments.append(line)
            }
            arguments.append(directory)
            arguments.append(contentsOf: agentArgv)
            return LaunchPlan(executable: "/usr/bin/osascript", arguments: arguments)
        }
    }

    public static func preferredTerminal(ghosttyInstalled: Bool) -> TerminalApp {
        ghosttyInstalled ? .ghostty : .terminal
    }

    public static var ghosttyInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            || FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/Ghostty.app")
    }
}
