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
        // A GUI app (the Summon Menu) starts with `/` as its folder: treat that like home.
        let fromHomeOrRoot = normalizedCurrent == normalizedHome || normalizedCurrent == "/"
        guard fromHomeOrRoot else { return normalizedCurrent }
        return workExists ? (normalizedHome as NSString).appendingPathComponent("Work") : normalizedHome
    }

    /// Opens a new terminal window running `agentArgv` in `directory`.
    /// Both scripts are fixed text; the directory and every argv item arrive as osascript argv and are quoted there.
    public static func terminalPlan(agentArgv: [String], directory: String, terminal: TerminalApp) -> LaunchPlan {
        let script: [String]
        switch terminal {
        case .ghostty:
            // `open -na Ghostty` started a second Ghostty app per launch (extra Dock icon, stray window).
            // A running Ghostty (1.3+) gets one new window over AppleScript; a cold start opens exactly the -e window.
            script = [
                "on run argv",
                "set cmd to \"\"",
                "repeat with i from 2 to (count of argv)",
                "set cmd to cmd & quoted form of (item i of argv) & \" \"",
                "end repeat",
                "if application \"Ghostty\" is running then",
                "tell application \"Ghostty\"",
                "activate",
                "set cfg to new surface configuration",
                "set initial working directory of cfg to item 1 of argv",
                "set command of cfg to cmd",
                "new window with configuration cfg",
                "end tell",
                "else",
                "do shell script \"/usr/bin/open -na Ghostty --args --working-directory=\" & quoted form of (item 1 of argv) & \" -e \" & cmd",
                "end if",
                "end run",
            ]
        case .terminal:
            script = [
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
        }
        var arguments: [String] = []
        for line in script {
            arguments.append("-e")
            arguments.append(line)
        }
        arguments.append(directory)
        arguments.append(contentsOf: agentArgv)
        return LaunchPlan(executable: "/usr/bin/osascript", arguments: arguments)
    }

    public static func preferredTerminal(ghosttyInstalled: Bool) -> TerminalApp {
        ghosttyInstalled ? .ghostty : .terminal
    }

    public static var ghosttyInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Ghostty.app")
            || FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/Ghostty.app")
    }
}
