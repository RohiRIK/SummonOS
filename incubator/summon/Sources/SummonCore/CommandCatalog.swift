import Foundation

/// Every `summon` command, so agents can discover the system with one call (`summon commands --json`),
/// the way `omarchy commands --json` works. `--help` output is generated from the same list.
public struct CommandInfo: Sendable, Equatable, Codable {
    public let route: String
    public let summary: String
    public let args: String
    public let examples: [String]
    /// "read" never changes anything; "user" changes user settings; "launch" starts a program.
    public let risk: String
}

public enum CommandCatalog {
    public static let all: [CommandInfo] = [
        CommandInfo(route: "agent", summary: "Start the default coding agent in a new terminal window (checkpoint first)",
                    args: "[--inline] [--no-checkpoint]", examples: ["summon agent", "summon agent --inline"], risk: "launch"),
        CommandInfo(route: "agent prompt", summary: "Start the default agent straight into a task",
                    args: "[--inline] <prompt...>", examples: ["summon agent prompt \"Why is my Mac slow?\""], risk: "launch"),
        CommandInfo(route: "default agent", summary: "Show or set the default coding agent",
                    args: "[claude|codex|opencode|copilot|cursor-agent|agy|pi|grok]", examples: ["summon default agent", "summon default agent claude"], risk: "user"),
        CommandInfo(route: "agents set", summary: "Choose an agent's model and which Summon skills it gets (saved in ~/.config/summon/agents.json, relinked at once)",
                    args: "<agent> [--model <m> | --default-model] [--skills a,b | --all-skills]",
                    examples: ["summon agents set claude --model opus", "summon agents set codex --skills summon,summon-mac"], risk: "user"),
        CommandInfo(route: "task new", summary: "Describe a recurring task to the default agent; it asks what is unclear, writes the run prompt and adds it",
                    args: "[what you want] [--inline]", examples: ["summon task new \"every weekday at 9, check brew updates\""], risk: "user"),
        CommandInfo(route: "task add", summary: "Schedule a prompt for an agent: every day or weekday at a time, or every N hours (launchd; checkpoint first; result in Activity)",
                    args: "<prompt> (--at HH:MM [--weekdays] | --every <n>h) [--agent <id>] [--name <name>]",
                    examples: ["summon task add \"Check brew updates and summarize\" --at 09:00 --weekdays --agent claude"], risk: "user"),
        CommandInfo(route: "task list", summary: "Recurring tasks with their schedule and last result", args: "[--json]", examples: ["summon task list"], risk: "read"),
        CommandInfo(route: "task remove", summary: "Stop and delete a recurring task", args: "<id>", examples: ["summon task remove brew-check"], risk: "user"),
        CommandInfo(route: "task run", summary: "Run a recurring task now, unattended (what launchd calls)", args: "<id>", examples: ["summon task run brew-check"], risk: "user"),
        CommandInfo(route: "skills", summary: "List the skill files Summon ships", args: "", examples: ["summon skills"], risk: "read"),
        CommandInfo(route: "skills link", summary: "Link Summon's skills into ~/.agents, ~/.claude, ~/.codex, ~/.gemini/config and ~/.pi/agent skill folders (your own folders are kept)",
                    args: "[--quiet]", examples: ["summon skills link"], risk: "user"),
        CommandInfo(route: "default terminal", summary: "Show or set the terminal agents open in (unset: first installed of Ghostty, kitty, Terminal)",
                    args: "[ghostty|kitty|terminal]", examples: ["summon default terminal", "summon default terminal kitty"], risk: "user"),
        CommandInfo(route: "agents", summary: "List the agents Summon knows, whether each is installed, and how to install it",
                    args: "[--json]", examples: ["summon agents --json"], risk: "read"),
        CommandInfo(route: "checkpoint create", summary: "Take a checkpoint now (macctl snapshot + git commit of ~/.config)",
                    args: "[--dry-run] [label]", examples: ["summon checkpoint create before-cleanup"], risk: "user"),
        CommandInfo(route: "checkpoint list", summary: "List checkpoints, newest first",
                    args: "[--json]", examples: ["summon checkpoint list --json"], risk: "read"),
        CommandInfo(route: "checkpoint undo", summary: "Restore ~/.config and macOS settings to a checkpoint (default: the latest)",
                    args: "[id] [--dry-run]", examples: ["summon checkpoint undo --dry-run", "summon checkpoint undo 20261017-203000"], risk: "user"),
        CommandInfo(route: "undo-session", summary: "Undo the last agent session (same as checkpoint undo of the latest)",
                    args: "[--dry-run]", examples: ["summon undo-session"], risk: "user"),
        CommandInfo(route: "status", summary: "Agent, macctl, last change, last checkpoint and recent problems at a glance",
                    args: "[--json]", examples: ["summon status", "summon status --json"], risk: "read"),
        CommandInfo(route: "doctor", summary: "Check Summon's own install and setup: app, CLI, config, macctl, event log, hotkeys, permissions, skill links",
                    args: "[--json]", examples: ["summon doctor", "summon doctor --json"], risk: "read"),
        CommandInfo(route: "events", summary: "The activity timeline: settings changes, undos, checkpoints, agent sessions, themes, crashes",
                    args: "[--json] [--limit N] [--kind settings|agent|checkpoint|theme|problem]",
                    examples: ["summon events --limit 10", "summon events --kind settings --json"], risk: "read"),
        CommandInfo(route: "event add", summary: "Record an event in the timeline (used by the Claude Code plugin hooks)",
                    args: "<kind> <title...> [--detail text] [--ref key=value]...",
                    examples: ["summon event add session.start \"Claude Code session\" --ref session=abc --ref folder=~/Summon/mac-battery"], risk: "user"),
        CommandInfo(route: "event hook", summary: "Record a Claude Code SessionStart/SessionEnd hook payload read from stdin",
                    args: "start|end", examples: ["summon event hook start < payload.json"], risk: "user"),
        CommandInfo(route: "project new", summary: "Start a project in ~/Summon/<name> from a template (menu bar app, window app, CLI tool, screensaver) and record it in Summon's private list",
                    args: "<name> --kind menubar|app|cli|screensaver [--json]",
                    examples: ["summon project new mac-battery --kind menubar"], risk: "user"),
        CommandInfo(route: "project list", summary: "Projects Summon made (private list in ~/.config/summon/projects.json)",
                    args: "[--json]", examples: ["summon project list --json"], risk: "read"),
        CommandInfo(route: "project path", summary: "Print a project's folder, or ~/Summon without a name",
                    args: "[name]", examples: ["summon project path mac-battery"], risk: "read"),
        CommandInfo(route: "project forget", summary: "Remove a project from the list (its folder and repo stay)",
                    args: "<name>", examples: ["summon project forget mac-battery"], risk: "user"),
        CommandInfo(route: "project repo", summary: "Create the project's PRIVATE GitHub repo with CI, only after the user approves a native Summon dialog (never public)",
                    args: "<name> [--owner <login>]", examples: ["summon project repo mac-battery"], risk: "user"),
        CommandInfo(route: "icon set", summary: "Put a custom icon on any file, folder or app",
                    args: "<image> <path>", examples: ["summon icon set ~/Pictures/work.png ~/Summon"], risk: "user"),
        CommandInfo(route: "icon reset", summary: "Remove a custom icon",
                    args: "<path>", examples: ["summon icon reset ~/Summon"], risk: "user"),
        CommandInfo(route: "path", summary: "Print the folder holding Summon's shared files (themes, skills, wallpapers)",
                    args: "", examples: ["summon path"], risk: "read"),
        CommandInfo(route: "crash list", summary: "Recent crash, hang and panic reports, newest first, muted programs skipped",
                    args: "[--json] [--limit N]", examples: ["summon crash list --json"], risk: "read"),
        CommandInfo(route: "crash diagnose", summary: "Hand a report to the default agent with the diagnose-crash-mac skill",
                    args: "<file.ips> | --latest", examples: ["summon crash diagnose --latest"], risk: "launch"),
        CommandInfo(route: "crash show", summary: "Print the parsed facts of one report",
                    args: "<file.ips> [--json]", examples: ["summon crash show ~/Library/Logs/DiagnosticReports/Foo.ips"], risk: "read"),
        CommandInfo(route: "crash mute", summary: "Stop crash notifications for one program, or list muted programs",
                    args: "[program] [off]", examples: ["summon crash mute Foo", "summon crash mute Foo off"], risk: "user"),
        CommandInfo(route: "theme list", summary: "Installed themes, the current one marked",
                    args: "[--json]", examples: ["summon theme list"], risk: "read"),
        CommandInfo(route: "theme set", summary: "Apply a theme to macOS, the wallpaper, Ghostty, borders and Claude Code",
                    args: "<slug> [--no-wallpaper]", examples: ["summon theme set summon-night"], risk: "user"),
        CommandInfo(route: "theme current", summary: "Print the current theme slug",
                    args: "", examples: ["summon theme current"], risk: "read"),
        CommandInfo(route: "debug", summary: "Collect a debug bundle: macOS version, hardware, recent errors, reports, packages",
                    args: "[--print] [--save] [--since 1h]", examples: ["summon debug --print --since 30m"], risk: "read"),
        CommandInfo(route: "hooks run", summary: "Run the hooks of one event",
                    args: "<theme-set|post-login|post-update|wake|crash> [args...]", examples: ["summon hooks run theme-set summon-night"], risk: "user"),
        CommandInfo(route: "hooks list", summary: "List hook scripts per event",
                    args: "", examples: ["summon hooks list"], risk: "read"),
        CommandInfo(route: "menu summon", summary: "Open the Summon Menu, optionally at one entry",
                    args: "[id]", examples: ["summon menu summon style.theme"], risk: "launch"),
        CommandInfo(route: "menu init", summary: "Write the default menu to ~/.config/summon/menu.jsonc if it does not exist",
                    args: "[--force]", examples: ["summon menu init"], risk: "user"),
        CommandInfo(route: "menu list", summary: "Print the menu tree",
                    args: "[--json]", examples: ["summon menu list --json"], risk: "read"),
        CommandInfo(route: "commands", summary: "List every command",
                    args: "[--json]", examples: ["summon commands --json"], risk: "read"),
    ]

    public static func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(all)
        return String(decoding: data, as: UTF8.self)
    }

    public static func helpText() -> String {
        var lines = ["summon: summon your coding agent anywhere on this Mac, and let the Mac call it when something breaks.", "", "Commands:"]
        let width = all.map { $0.route.count }.max() ?? 0
        for command in all {
            let padded = command.route.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("  summon \(padded)  \(command.summary)")
        }
        lines.append("")
        lines.append("Run `summon commands --json` for arguments and examples. Exit codes: 0 ok, 1 error, 2 missing dependency, 4 unsupported.")
        return lines.joined(separator: "\n")
    }

    public static func find(_ route: String) -> CommandInfo? {
        all.first { $0.route == route }
    }
}
