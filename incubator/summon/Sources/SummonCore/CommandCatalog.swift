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
        CommandInfo(route: "default execution", summary: "normal: use the agent's own controls; unattended: bypass supported agent approvals/sandbox (existing installs retain their choice)",
                    args: "[normal|unattended]", examples: ["summon default execution", "summon default execution unattended"], risk: "user"),
        CommandInfo(route: "default agent", summary: "Show or set the default coding agent",
                    args: "[claude|codex|opencode|copilot|cursor-agent|agy|pi|hermes|openclaw|grok]", examples: ["summon default agent", "summon default agent claude"], risk: "user"),
        CommandInfo(route: "agents set", summary: "Choose an agent's model and which Summon skills it gets (saved in ~/.config/summon/agents.json, relinked at once)",
                    args: "<agent> [--model <m> | --default-model] [--skills a,b | --all-skills]",
                    examples: ["summon agents set claude --model opus", "summon agents set codex --skills summon,summon-mac"], risk: "user"),
        CommandInfo(route: "task new", summary: "Describe a recurring task to the default agent; it asks what is unclear, writes the run prompt and adds it",
                    args: "[what you want] [--inline]", examples: ["summon task new \"every weekday at 9, check brew updates\""], risk: "user"),
        CommandInfo(route: "task add", summary: "Schedule a prompt for an agent: every day or weekday at a time, or every N hours (launchd; checkpoint first; result in Activity)",
                    args: "<prompt> (--at HH:MM [--weekdays] | --every <n>h) [--agent <id>] [--name <name>] [--execution normal|unattended] [--directory <path>]",
                    examples: ["summon task add \"Check brew updates and summarize\" --at 09:00 --weekdays --agent claude"], risk: "user"),
        CommandInfo(route: "task list", summary: "Recurring tasks with their schedule and last result", args: "[--json]", examples: ["summon task list"], risk: "read"),
        CommandInfo(route: "task remove", summary: "Stop and delete a recurring task", args: "<id>", examples: ["summon task remove brew-check"], risk: "user"),
        CommandInfo(route: "task run", summary: "Run a recurring task now, unattended (what launchd calls)", args: "<id>", examples: ["summon task run brew-check"], risk: "user"),
        CommandInfo(route: "agents defaults", summary: "The All Agents skills every agent follows unless it has its own list (summon agents set <agent> --all-skills follows them again)",
                    args: "[--skills a,b | --all-skills]", examples: ["summon agents defaults --skills summon,summon-mac,summon-art"], risk: "user"),
        CommandInfo(route: "agents status", summary: "Ask an agent's CLI whether it is logged in and which models it offers",
                    args: "<agent> [--json]", examples: ["summon agents status pi --json"], risk: "read"),
        CommandInfo(route: "agents login", summary: "Open the agent's own login in a terminal window", args: "<agent>",
                    examples: ["summon agents login codex"], risk: "user"),
        CommandInfo(route: "agents plugins", summary: "An agent's installed plugins (Codex: its MCP servers)", args: "<agent> [--json]",
                    examples: ["summon agents plugins claude"], risk: "read"),
        CommandInfo(route: "agents plugin-add", summary: "Install a plugin with the agent's own installer (OpenCode: added to opencode.json, backup kept)",
                    args: "<agent> <plugin>", examples: ["summon agents plugin-add pi npm:context-mode"], risk: "user"),
        CommandInfo(route: "plugins", summary: "Summon's shared plugin catalog (OpenLTM, …) and which agents have each", args: "[--json]",
                    examples: ["summon plugins"], risk: "read"),
        CommandInfo(route: "plugins install", summary: "Install a catalog plugin into every installed agent that has a build", args: "<id>",
                    examples: ["summon plugins install openltm"], risk: "user"),
        CommandInfo(route: "plugins fix", summary: "Hand a plugin that is not working to the default agent to diagnose and fix", args: "<id> <agent>",
                    examples: ["summon plugins fix openltm opencode"], risk: "user"),
        CommandInfo(route: "project shots", summary: "Build the app, open it, capture its menu bar panel or window into docs/screenshots, add them to the README and commit (also run by project repo)",
                    args: "<name>", examples: ["summon project shots mac-battery"], risk: "user"),
        CommandInfo(route: "showcase", summary: "Write ~/Summon/Showcase/index.html, a gallery of every app Summon made with its screenshots, and open it",
                    args: "[--no-open]", examples: ["summon showcase"], risk: "user"),
        CommandInfo(route: "clean", summary: "Tidy ~/Summon: old task logs, art jobs untouched 30 days, Antigravity originals after 14 days go to the Trash; apps are never touched (preview without --apply)",
                    args: "[--apply] [--if-due] [--quiet] [--json]", examples: ["summon clean", "summon clean --apply"], risk: "user"),
        CommandInfo(route: "home", summary: "Set up ~/Summon (Apps, Art, Tasks, a Themes link, .gitignore) and move older Summon files into it",
                    args: "[--quiet]", examples: ["summon home"], risk: "user"),
        CommandInfo(route: "skills", summary: "List the skill files Summon ships", args: "", examples: ["summon skills"], risk: "read"),
        CommandInfo(route: "skills link", summary: "Link Summon's skills into ~/.agents, ~/.claude, ~/.codex, ~/.gemini/config and ~/.pi/agent skill folders (your own folders are kept)",
                    args: "[--quiet]", examples: ["summon skills link"], risk: "user"),
        CommandInfo(route: "default repos", summary: "always (default): every new app gets a private GitHub repo right away; ask: only after the approval dialog. Always private.",
                    args: "[always|ask]", examples: ["summon default repos", "summon default repos ask"], risk: "user"),
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
        CommandInfo(route: "context", summary: "This Mac for agents: hardware, power, storage, network, displays, apps, appearance, permissions, agents, recent crashes",
                    args: "[--json] [--only system,power,storage,network,displays,apps,appearance,permissions,agents,crashes]",
                    examples: ["summon context", "summon context --json --only power,storage"], risk: "read"),
        CommandInfo(route: "mcp", summary: "MCP server on stdio for any agent: mac_context, settings list/get/set/undo/history (macctl), checkpoints, crash reports",
                    args: "", examples: ["claude mcp add summon -- summon mcp"], risk: "user"),
        CommandInfo(route: "connect", summary: "Add the summon MCP server and a short \"This Mac\" note to every installed agent: Claude Code, Codex, Cursor, OpenCode, Hermes, OpenClaw, Antigravity CLI, Pi (files backed up first)",
                    args: "[agent...] [--dry-run] [--json]", examples: ["summon connect --dry-run", "summon connect claude codex"], risk: "user"),
        CommandInfo(route: "disconnect", summary: "Remove what summon connect added (only Summon's server entry and marked note; your other changes stay)",
                    args: "[agent...] [--dry-run] [--json]", examples: ["summon disconnect pi"], risk: "user"),
        CommandInfo(route: "context fields", summary: "Which context fields agents see (all on unless turned off)", args: "",
                    examples: ["summon context fields"], risk: "read"),
        CommandInfo(route: "context hide", summary: "Hide a context field from agents (hostname, window-title, running-apps, paths)",
                    args: "<field>", examples: ["summon context hide window-title"], risk: "user"),
        CommandInfo(route: "context show", summary: "Show a hidden context field to agents again", args: "<field>",
                    examples: ["summon context show window-title"], risk: "user"),
        CommandInfo(route: "status", summary: "Agent, macctl, last change, last checkpoint and recent problems at a glance",
                    args: "[--json]", examples: ["summon status", "summon status --json"], risk: "read"),
        CommandInfo(route: "doctor", summary: "Check Summon's own install and setup: app, CLI, config, macctl, event log, hotkeys, permissions, skill links",
                    args: "[--json] [--fix]", examples: ["summon doctor", "summon doctor --json", "summon doctor --fix"], risk: "read"),
        CommandInfo(route: "fix", summary: "Launch default agent to fix issues detected by summon doctor or crash reports",
                    args: "[--inline]", examples: ["summon fix", "summon fix --inline"], risk: "launch"),
        CommandInfo(route: "events", summary: "The activity timeline: settings changes, undos, checkpoints, agent sessions, themes, crashes, and Mac changes (offline, low disk, hot, battery, displays); --follow keeps printing new ones",
                    args: "[--json] [--limit N] [--kind settings|agent|checkpoint|theme|problem|mac] [--follow]",
                    examples: ["summon events --limit 10", "summon events --kind mac --follow"], risk: "read"),
        CommandInfo(route: "event add", summary: "Record an event in the timeline (used by the Claude Code plugin hooks)",
                    args: "<kind> <title...> [--detail text] [--ref key=value]...",
                    examples: ["summon event add session.start \"Claude Code session\" --ref session=abc --ref folder=~/Summon/mac-battery"], risk: "user"),
        CommandInfo(route: "event hook", summary: "Record a Claude Code SessionStart/SessionEnd hook payload read from stdin",
                    args: "start|end", examples: ["summon event hook start < payload.json"], risk: "user"),
        CommandInfo(route: "project new", summary: "Start a project in ~/Summon/Apps/<name> from a template (menu bar app, window app, CLI tool, screensaver) and record it in Summon's private list",
                    args: "<name> --kind menubar|app|cli|screensaver [--json]",
                    examples: ["summon project new mac-battery --kind menubar"], risk: "user"),
        CommandInfo(route: "project register", summary: "Register an existing app folder in ~/Summon/Apps/<name> into Summon's private list",
                    args: "<name> [--kind menubar|app|cli|screensaver] [--json]",
                    examples: ["summon project register mac-network"], risk: "user"),
        CommandInfo(route: "project import", summary: "Copy an external app directory into ~/Summon/Apps/<name> and register it",
                    args: "<path> [--name <name>] [--kind menubar|app|cli|screensaver] [--json]",
                    examples: ["summon project import ~/old-apps/mac-network"], risk: "user"),
        CommandInfo(route: "project list", summary: "Projects Summon made (private list in ~/.config/summon/projects.json)",
                    args: "[--json]", examples: ["summon project list --json"], risk: "read"),
        CommandInfo(route: "project path", summary: "Print a project's folder, or ~/Summon/Apps without a name",
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
        CommandInfo(route: "theme check", summary: "Say why a theme is not usable (theme list skips broken files): JSON, #RRGGBB colors, 16 terminal colors",
                    args: "<slug>", examples: ["summon theme check hearts-valley-theme"], risk: "read"),
        CommandInfo(route: "theme current", summary: "Print the current theme slug",
                    args: "", examples: ["summon theme current"], risk: "read"),
        CommandInfo(route: "debug", summary: "Collect a debug bundle: macOS version, hardware, recent errors, reports, packages",
                    args: "[--print] [--save] [--since 1h]", examples: ["summon debug --print --since 30m"], risk: "read"),
        CommandInfo(route: "hooks run", summary: "Run the hooks of one event",
                    args: "<theme-set|post-login|post-update|wake|crash> [args...]", examples: ["summon hooks run theme-set summon-night"], risk: "user"),
        CommandInfo(route: "hooks list", summary: "List hook scripts per event",
                    args: "", examples: ["summon hooks list"], risk: "read"),
        CommandInfo(route: "menu summon", summary: "Open the Summon Menu (menu bar panel), optionally at one entry",
                    args: "[id]", examples: ["summon menu summon style.theme"], risk: "launch"),
        CommandInfo(route: "panel", summary: "Open (or close) the menu bar panel without activating Summon",
                    args: "[--close]", examples: ["summon panel", "summon panel --close"], risk: "launch"),
        CommandInfo(route: "menu init", summary: "Write the default menu to ~/.config/summon/menu.jsonc if it does not exist",
                    args: "[--force]", examples: ["summon menu init"], risk: "user"),
        CommandInfo(route: "menu list", summary: "Print the menu tree",
                    args: "[--json]", examples: ["summon menu list --json"], risk: "read"),
        CommandInfo(route: "commands", summary: "List every command",
                    args: "[--json]", examples: ["summon commands --json"], risk: "read"),
        CommandInfo(route: "version", summary: "Print the SummonOS version (also --version)",
                    args: "", examples: ["summon version", "summon --version"], risk: "read"),
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
