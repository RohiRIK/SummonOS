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
    case kitty
    case terminal

    public var name: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .kitty: return "kitty"
        case .terminal: return "Terminal"
        }
    }

    public var isInstalled: Bool {
        switch self {
        case .terminal: return true
        case .ghostty, .kitty:
            let app = name + ".app"
            return FileManager.default.fileExists(atPath: "/Applications/" + app)
                || FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/" + app)
        }
    }

    public static var installed: Set<TerminalApp> { Set(allCases.filter(\.isInstalled)) }
}

/// `~/.config/summon/defaults/terminal`. Unset means the first installed of Ghostty, kitty, Terminal.
public struct DefaultTerminalStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    public func load() -> TerminalApp? {
        TextFile.firstLine(paths.defaultTerminalFile).flatMap { TerminalApp(rawValue: $0.lowercased()) }
    }

    public func save(_ terminal: TerminalApp) throws {
        try TextFile.write(terminal.rawValue + "\n", to: paths.defaultTerminalFile)
    }
}

public enum AgentLauncher {
    /// Agents refuse to remember trust for the home folder, so a launch from `~` starts in the projects folder
    /// (`~/Summon`, created on install and on every launch).
    public static func workingDirectory(current: String, home: String, projects: String) -> String {
        let normalizedCurrent = (current as NSString).standardizingPath
        let normalizedHome = (home as NSString).standardizingPath
        // A GUI app (the Summon Menu) starts with `/` as its folder: treat that like home.
        let fromHomeOrRoot = normalizedCurrent == normalizedHome || normalizedCurrent == "/"
        return fromHomeOrRoot ? (projects as NSString).standardizingPath : normalizedCurrent
    }

    /// Opens a new terminal window running `agentArgv` in `directory`.
    /// Both scripts are fixed text; the directory and every argv item arrive as osascript argv and are quoted there.
    public static func terminalPlan(agentArgv: [String], directory: String, terminal: TerminalApp) -> LaunchPlan {
        let script: [String]
        switch terminal {
        case .kitty:
            // --single-instance hands the window to a running kitty and exits, so no second kitty stays open.
            return LaunchPlan(
                executable: "/usr/bin/open",
                arguments: ["-na", "kitty", "--args", "--single-instance", "--directory", directory] + agentArgv
            )
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

    /// The saved choice when it is still installed, else the first installed of Ghostty, kitty, Terminal.
    public static func preferredTerminal(saved: TerminalApp?, installed: Set<TerminalApp>) -> TerminalApp {
        if let saved, installed.contains(saved) { return saved }
        return TerminalApp.allCases.first { installed.contains($0) } ?? .terminal
    }
}
