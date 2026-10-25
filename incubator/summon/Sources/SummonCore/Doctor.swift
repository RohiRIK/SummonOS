import Foundation

/// One line of `summon doctor`: what was checked, how it went, and what to run when it did not.
public struct DoctorCheck: Sendable, Equatable, Codable {
    public enum Status: String, Sendable, Codable, Comparable {
        case pass
        case warn
        case fail

        var rank: Int {
            switch self {
            case .pass: return 0
            case .warn: return 1
            case .fail: return 2
            }
        }

        public static func < (lhs: Status, rhs: Status) -> Bool { lhs.rank < rhs.rank }
    }

    /// Dotted id, stable for agents: `install.app`, `config.agent`, `skills.links`, ...
    public var id: String
    public var status: Status
    public var detail: String
    /// A command or step that fixes it; nil when the check passed.
    public var fix: String?

    public init(_ id: String, _ status: Status, _ detail: String, fix: String? = nil) {
        self.id = id
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}

public struct DoctorReport: Sendable, Equatable, Codable {
    public var checks: [DoctorCheck]

    public init(checks: [DoctorCheck]) {
        self.checks = checks
    }

    /// The worst status of any check; `pass` when there are none.
    public var status: DoctorCheck.Status {
        checks.map(\.status).max() ?? .pass
    }

    public func check(_ id: String) -> DoctorCheck? {
        checks.first { $0.id == id }
    }

    /// Whether any check failed or warned.
    public var hasIssues: Bool {
        checks.contains { $0.status != .pass }
    }

    /// All checks that need attention (warn or fail).
    public var issues: [DoctorCheck] {
        checks.filter { $0.status != .pass }
    }
}

/// What the menu app writes on launch so the CLI can see what only the app knows: whether it is running,
/// whether its hotkeys registered, and whether it may post notifications.
public struct AppHealth: Sendable, Equatable, Codable {
    public var pid: Int32
    public var launchedAt: Date
    /// Hotkey label (`⌃⌥Space`) → registered. False means another app owns the combination.
    public var hotkeys: [String: Bool]
    /// `authorized`, `denied`, `notDetermined`, `provisional`, or nil when the app cannot notify (run outside a bundle).
    public var notifications: String?

    public init(pid: Int32, launchedAt: Date = Date(), hotkeys: [String: Bool], notifications: String? = nil) {
        self.pid = pid
        self.launchedAt = launchedAt
        self.hotkeys = hotkeys
        self.notifications = notifications
    }
}

/// `~/.local/state/summon/app.json`.
public struct AppHealthStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    public func load() -> AppHealth? {
        guard let data = try? Data(contentsOf: paths.appHealthFile) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppHealth.self, from: data)
    }

    /// Whether Summon.app is running now, so it (not the CLI) posts notifications for logged events.
    public func appIsRunning(isProcessRunning: (Int32) -> Bool = { pid in pid > 0 && kill(pid, 0) == 0 }) -> Bool {
        guard let health = load() else { return false }
        return isProcessRunning(health.pid)
    }

    public func save(_ health: AppHealth) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try TextFile.write(String(decoding: try encoder.encode(health), as: UTF8.self) + "\n", to: paths.appHealthFile)
    }
}

/// `summon doctor`: checks Summon's own install and setup, never changes anything.
/// Every fact about the machine comes in through these properties, so tests run against a temp home.
public struct Doctor: Sendable {
    public var paths: SummonPaths
    public var runner: Runner
    /// The extended search path (Homebrew, ~/.local/bin) Summon itself uses to find tools.
    public var tools: ToolLocator
    /// Only the shell's `$PATH`, to tell whether typing `summon` in a terminal works.
    public var shellTools: ToolLocator
    /// Summon's shared files (`summon path`): `skills/`, `themes/`.
    public var share: URL
    /// Where Summon.app may be installed, first match wins.
    public var appLocations: [URL]
    public var installedTerminals: Set<TerminalApp>
    public var isProcessRunning: @Sendable (Int32) -> Bool

    public init(
        paths: SummonPaths,
        runner: @escaping Runner,
        tools: ToolLocator,
        shellTools: ToolLocator,
        share: URL,
        appLocations: [URL],
        installedTerminals: Set<TerminalApp>,
        isProcessRunning: @escaping @Sendable (Int32) -> Bool
    ) {
        self.paths = paths
        self.runner = runner
        self.tools = tools
        self.shellTools = shellTools
        self.share = share
        self.appLocations = appLocations
        self.installedTerminals = installedTerminals
        self.isProcessRunning = isProcessRunning
    }

    var skills: URL { share.appendingPathComponent("skills", isDirectory: true) }

    public func run() async -> DoctorReport {
        var checks = [
            appInstalled(),
            cliOnPath(),
            sharedFiles(),
            configFolder(),
            defaultAgent(),
            agentSettings(),
            terminal(),
            menu(),
            themes(),
            undoRepo(),
        ]
        checks.append(await macctl())
        checks.append(contentsOf: [
            stateFolder(),
            eventLog(),
            projectsFolder(),
            projectRegistry(),
            skillLinks(),
            tasks(),
            claudePlugin(),
        ])
        checks.append(contentsOf: app())
        checks.append(crashReports())
        return DoctorReport(checks: checks)
    }

    // MARK: Install

    func appInstalled() -> DoctorCheck {
        let fm = FileManager.default
        if let app = appLocations.first(where: { fm.fileExists(atPath: $0.path) }) {
            return DoctorCheck("install.app", .pass, "Summon.app at \(tilde(app.path))")
        }
        return DoctorCheck("install.app", .warn, "Summon.app is not in ~/Applications or /Applications, so there are no hotkeys or crash alerts",
                           fix: "scripts/bundle.sh && scripts/install.sh (in incubator/summon)")
    }

    func cliOnPath() -> DoctorCheck {
        guard let path = shellTools.find("summon") else {
            return DoctorCheck("install.cli", .warn, "`summon` is not on your shell PATH",
                               fix: "Add ~/.local/bin to PATH: echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.zshrc")
        }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolved == path || FileManager.default.fileExists(atPath: resolved) else {
            return DoctorCheck("install.cli", .fail, "\(tilde(path)) points to \(tilde(resolved)), which is gone",
                               fix: "scripts/install.sh (in incubator/summon)")
        }
        return DoctorCheck("install.cli", .pass, tilde(path) + (resolved == path ? "" : " → \(tilde(resolved))"))
    }

    func sharedFiles() -> DoctorCheck {
        let skillCount = SkillLinker.skillNames(in: skills).count
        let themeCount = Self.themeFolders(in: share.appendingPathComponent("themes", isDirectory: true)).count
        guard skillCount > 0 else {
            return DoctorCheck("install.files", .fail, "No skills in \(tilde(skills.path)), so agents get no Summon skills",
                               fix: "Reinstall with scripts/install.sh, or set SUMMON_PATH to the folder holding skills/ and themes/")
        }
        let templates = share.appendingPathComponent("templates", isDirectory: true)
        let missing = ProjectKind.allCases.filter { kind in
            !FileManager.default.fileExists(atPath: templates.appendingPathComponent(kind.rawValue).path)
        }
        guard missing.isEmpty else {
            return DoctorCheck("install.files", .warn,
                               "\(skillCount) skills, \(themeCount) themes, but no project template for \(missing.map(\.rawValue).joined(separator: ", ")) in \(tilde(templates.path))",
                               fix: "Reinstall with scripts/bundle.sh && scripts/install.sh (in incubator/summon)")
        }
        return DoctorCheck("install.files", .pass,
                           "\(tilde(share.path)): \(skillCount) skills, \(themeCount) themes, \(ProjectKind.allCases.count) project templates")
    }

    // MARK: Config

    func configFolder() -> DoctorCheck {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: paths.config.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return DoctorCheck("config.folder", .fail, "\(tilde(paths.config.path)) is missing", fix: "scripts/install.sh (in incubator/summon)")
        }
        guard FileManager.default.isWritableFile(atPath: paths.config.path) else {
            return DoctorCheck("config.folder", .fail, "\(tilde(paths.config.path)) is not writable",
                               fix: "sudo chown -R \"$USER\" ~/.config/summon")
        }
        return DoctorCheck("config.folder", .pass, tilde(paths.config.path))
    }

    func defaultAgent() -> DoctorCheck {
        if let raw = TextFile.firstLine(paths.defaultAgentFile), AgentRegistry.find(raw) == nil {
            return DoctorCheck("config.agent", .fail, "Default agent \"\(raw)\" is not one Summon knows",
                               fix: "summon default agent claude (see summon agents)")
        }
        guard let agent = DefaultAgentStore(paths: paths).load() else {
            return DoctorCheck("config.agent", .warn, "No default agent chosen, so the hotkey and crash Diagnose do nothing",
                               fix: "summon default agent claude")
        }
        guard let path = tools.find(agent.command) else {
            return DoctorCheck("config.agent", .fail, "\(agent.name) is the default agent but `\(agent.command)` is not installed",
                               fix: agent.installHint)
        }
        return DoctorCheck("config.agent", .pass, "\(agent.name) at \(tilde(path))")
    }

    func agentSettings() -> DoctorCheck {
        let file = paths.agentSettingsFile
        guard let data = try? Data(contentsOf: file) else {
            return DoctorCheck("config.agents", .pass, "No \(tilde(file.path)): every agent uses its own model and every skill")
        }
        guard let settings = try? JSONDecoder().decode(AgentSettings.self, from: data) else {
            return DoctorCheck("config.agents", .fail, "\(tilde(file.path)) is not valid, so Summon ignores it",
                               fix: "Fix the JSON, or delete it and use summon agents set")
        }
        let shipped = Set(SkillLinker.skillNames(in: skills))
        var problems: [String] = []
        for id in settings.agents.keys.sorted() {
            guard AgentRegistry.find(id) != nil else {
                problems.append("unknown agent \"\(id)\"")
                continue
            }
            let unknown = (settings.agents[id]?.skills ?? []).filter { !shipped.isEmpty && !shipped.contains($0) }
            if !unknown.isEmpty {
                problems.append("\(id): unknown skills \(unknown.joined(separator: ", "))")
            }
        }
        guard problems.isEmpty else {
            return DoctorCheck("config.agents", .warn, problems.joined(separator: "; "),
                               fix: "summon agents set <agent> --all-skills, or edit \(tilde(file.path))")
        }
        return DoctorCheck("config.agents", .pass, "\(settings.agents.count) agent(s) customized")
    }

    func terminal() -> DoctorCheck {
        let saved = DefaultTerminalStore(paths: paths).load()
        let used = AgentLauncher.preferredTerminal(saved: saved, installed: installedTerminals)
        if let saved, saved != used {
            return DoctorCheck("config.terminal", .warn, "\(saved.name) is the default terminal but is not installed; agents open in \(used.name)",
                               fix: "Install \(saved.name), or: summon default terminal \(used.rawValue)")
        }
        return DoctorCheck("config.terminal", .pass, "Agents open in \(used.name)")
    }

    func menu() -> DoctorCheck {
        let file = paths.menuFile
        guard FileManager.default.fileExists(atPath: file.path) else {
            return DoctorCheck("config.menu", .warn, "No \(tilde(file.path)), so the Summon Menu uses the built-in default",
                               fix: "summon menu init")
        }
        let loaded = MenuTree.load(from: file)
        if let problem = loaded.problem {
            return DoctorCheck("config.menu", .fail, problem, fix: "Fix \(tilde(file.path)), or replace it: summon menu init --force")
        }
        return DoctorCheck("config.menu", .pass, "\(loaded.tree.items.count) entries")
    }

    func themes() -> DoctorCheck {
        let store = ThemeStore(paths: paths)
        let installed = store.all()
        let broken = Self.themeFolders(in: paths.themes).count - installed.count
        guard !installed.isEmpty else {
            return DoctorCheck("config.themes", .warn, "No themes in \(tilde(paths.themes.path))", fix: "scripts/install.sh (in incubator/summon)")
        }
        if let current = store.currentSlug(), !installed.contains(where: { $0.slug == current }) {
            return DoctorCheck("config.themes", .warn, "Current theme \"\(current)\" is not installed",
                               fix: "summon theme set \(installed[0].slug)")
        }
        let current = store.currentSlug().map { ", current \($0)" } ?? ""
        if broken > 0 {
            return DoctorCheck("config.themes", .warn, "\(installed.count) themes\(current); \(broken) folder(s) with a missing or invalid theme.json",
                               fix: "Check theme.json in each folder of \(tilde(paths.themes.path))")
        }
        return DoctorCheck("config.themes", .pass, "\(installed.count) themes\(current)")
    }

    func undoRepo() -> DoctorCheck {
        let git = paths.userConfig.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: git) else {
            return DoctorCheck("config.undo", .warn, "~/.config is not a git repo, so undo cannot put changed files back",
                               fix: "git -C ~/.config init")
        }
        guard tools.find("git") != nil else {
            return DoctorCheck("config.undo", .fail, "git is not installed, so checkpoints cannot commit ~/.config", fix: "xcode-select --install")
        }
        return DoctorCheck("config.undo", .pass, "~/.config is a git repo")
    }

    // MARK: Dependencies

    func macctl() async -> DoctorCheck {
        guard let path = tools.find("macctl") else {
            return DoctorCheck("macctl", .fail, "macctl is not installed, so settings changes are not recorded or undoable",
                               fix: "Build macctl (macctl/README.md) and put it on PATH")
        }
        let problems: [String]
        do {
            problems = StatusProbe.doctorProblems(fromJSON: try await runner(path, ["doctor", "--json"]))
        } catch {
            problems = ["doctor failed: \(error)"]
        }
        guard problems.isEmpty else {
            return DoctorCheck("macctl", .warn, problems.joined(separator: "; "), fix: "macctl doctor")
        }
        return DoctorCheck("macctl", .pass, "\(tilde(path)), all its checks pass")
    }

    // MARK: State

    func stateFolder() -> DoctorCheck {
        let fm = FileManager.default
        var dir = paths.state
        // Not created until first use: check the nearest folder that exists instead.
        while !fm.fileExists(atPath: dir.path), dir.pathComponents.count > 1 {
            dir = dir.deletingLastPathComponent()
        }
        guard fm.isWritableFile(atPath: dir.path) else {
            return DoctorCheck("state.folder", .fail, "\(tilde(dir.path)) is not writable, so events and checkpoints cannot be saved",
                               fix: "sudo chown -R \"$USER\" \(tilde(dir.path))")
        }
        return DoctorCheck("state.folder", .pass, tilde(paths.state.path))
    }

    func eventLog() -> DoctorCheck {
        let file = paths.eventLogFile
        guard let text = TextFile.read(file) else {
            return DoctorCheck("state.events", .pass, "No events yet")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let events = EventLog(file: file).read()
        let bad = lines.count - events.count
        let last = events.last.map { ", last \($0.kind) at \(Self.timestamp($0.time))" } ?? ""
        if bad > 0 {
            return DoctorCheck("state.events", .warn, "\(bad) of \(lines.count) lines in \(tilde(file.path)) cannot be read and are skipped\(last)",
                               fix: "Remove the broken lines, or move the file away to start a new log")
        }
        return DoctorCheck("state.events", .pass, "\(events.count) events\(last)")
    }

    // MARK: Projects

    func projectsFolder() -> DoctorCheck {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: paths.projects.path, isDirectory: &isDirectory) else {
            return DoctorCheck("projects.folder", .warn, "\(tilde(paths.projects.path)) is missing, so new projects have nowhere to go",
                               fix: "mkdir ~/Summon (Summon.app also makes it on launch)")
        }
        guard isDirectory.boolValue else {
            return DoctorCheck("projects.folder", .fail, "\(tilde(paths.projects.path)) is a file, not a folder",
                               fix: "Move that file away, then: mkdir ~/Summon")
        }
        guard FileManager.default.isWritableFile(atPath: paths.projects.path) else {
            return DoctorCheck("projects.folder", .fail, "\(tilde(paths.projects.path)) is not writable",
                               fix: "sudo chown -R \"$USER\" ~/Summon")
        }
        return DoctorCheck("projects.folder", .pass, tilde(paths.projects.path))
    }

    func projectRegistry() -> DoctorCheck {
        let file = tilde(paths.projectRegistryFile.path)
        let registry: ProjectRegistry
        do {
            registry = try ProjectStore(paths: paths).load()
        } catch {
            return DoctorCheck("projects.registry", .fail, "\(file) cannot be read, so project commands refuse to save",
                               fix: "Fix the JSON in \(file), or move it away to start an empty list")
        }
        guard !registry.projects.isEmpty else {
            return DoctorCheck("projects.registry", .pass, "No projects yet")
        }
        let gone = registry.projects.filter { project in
            !FileManager.default.fileExists(atPath: (project.path as NSString).expandingTildeInPath)
        }
        guard gone.isEmpty else {
            return DoctorCheck("projects.registry", .warn,
                               "\(registry.projects.count) projects; folder missing for \(Self.list(gone.map(\.name)))",
                               fix: "Move the folders back, or remove those entries from \(file)")
        }
        return DoctorCheck("projects.registry", .pass, "\(registry.projects.count) projects, every folder present")
    }

    // MARK: Agents

    /// Each installed agent should have a link to the current install for every skill chosen for it.
    /// Every recurring task needs its LaunchAgent and an agent that can run unattended (from PR #40's check).
    func tasks() -> DoctorCheck {
        let file = tilde(paths.tasksFile.path)
        guard let data = try? Data(contentsOf: paths.tasksFile) else { return DoctorCheck("tasks", .pass, "No tasks") }
        guard let tasks = try? JSONDecoder().decode([RecurringTask].self, from: data) else {
            return DoctorCheck("tasks", .fail, "\(file) cannot be read, so no task runs",
                               fix: "Fix the JSON in \(file), or move it away to start an empty list")
        }
        guard !tasks.isEmpty else { return DoctorCheck("tasks", .pass, "No tasks") }
        let unscheduled = tasks.filter { !FileManager.default.fileExists(atPath: TaskPlist.file($0.id, home: paths.home).path) }
        if !unscheduled.isEmpty {
            return DoctorCheck("tasks", .warn, "No LaunchAgent for \(Self.list(unscheduled.map(\.id))), so it never runs on its own",
                               fix: "summon task remove \(unscheduled[0].id), then add it again (summon task new)")
        }
        let fallback = DefaultAgentStore(paths: paths).load()
        let stuck = tasks.filter { ($0.agent.flatMap(AgentRegistry.find) ?? fallback)?.headlessPrefix == nil }
        if !stuck.isEmpty {
            return DoctorCheck("tasks", .warn, "\(Self.list(stuck.map(\.id))) would fail: no agent that can run it unattended",
                               fix: "summon default agent claude (or codex, opencode, agy, pi)")
        }
        return DoctorCheck("tasks", .pass, tasks.count == 1 ? "1 task scheduled" : "\(tasks.count) tasks scheduled")
    }

    func skillLinks() -> DoctorCheck {
        let fm = FileManager.default
        let shipped = SkillLinker.skillNames(in: skills)
        guard !shipped.isEmpty else {
            return DoctorCheck("skills.links", .warn, "No shipped skills to link (see install.files)")
        }
        let settings = AgentSettingsStore(paths: paths).load()
        let linker = SkillLinker(home: paths.home)
        var missing: [String] = []
        var stale: [String] = []
        var agents: [String] = []
        for agent in AgentRegistry.all {
            guard let folder = agent.skillFolder, tools.find(agent.command) != nil else { continue }
            agents.append(agent.name)
            for name in settings.skills(for: agent.id, shipped: shipped) {
                let link = paths.home.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
                let label = "~/\(folder)/\(name)"
                if let target = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                    if target != skills.appendingPathComponent(name).path, linker.isOurs(link, name: name) {
                        stale.append(label)
                    } else if !fm.fileExists(atPath: link.path) {
                        stale.append(label)
                    }
                } else if !fm.fileExists(atPath: link.path) {
                    missing.append(label)
                }
                // A real folder of the user's with the skill's name is theirs to keep: not a problem.
            }
        }
        guard !agents.isEmpty else {
            return DoctorCheck("skills.links", .pass, "No coding agents installed yet")
        }
        var problems: [String] = []
        if !missing.isEmpty { problems.append("missing \(Self.list(missing))") }
        if !stale.isEmpty { problems.append("pointing at an old or missing install: \(Self.list(stale))") }
        guard problems.isEmpty else {
            return DoctorCheck("skills.links", .warn, "Skill links " + problems.joined(separator: "; "), fix: "summon skills link")
        }
        return DoctorCheck("skills.links", .pass, "Skills linked for \(agents.joined(separator: ", "))")
    }

    /// The Claude Code plugin's hooks are what record agent sessions in the Activity window.
    func claudePlugin() -> DoctorCheck {
        guard tools.find("claude") != nil else {
            return DoctorCheck("plugin", .pass, "Claude Code is not installed; the Summon plugin is only for Claude Code")
        }
        let registry = paths.home.appendingPathComponent(".claude/plugins/installed_plugins.json")
        if let text = TextFile.read(registry), text.contains("\"summon@") || text.contains("\"summon\"") {
            return DoctorCheck("plugin", .pass, "Summon plugin installed in Claude Code")
        }
        return DoctorCheck("plugin", .warn, "The Summon plugin is not installed in Claude Code, so its sessions are not recorded in Activity",
                           fix: "claude --plugin-dir <repo>/incubator/summon/plugin (a marketplace install comes later)")
    }

    // MARK: Menu app

    func app() -> [DoctorCheck] {
        guard let health = AppHealthStore(paths: paths).load() else {
            return [DoctorCheck("app.running", .warn, "Summon.app has not run yet, so hotkeys and crash alerts are off",
                                fix: "open ~/Applications/Summon.app")]
        }
        guard isProcessRunning(health.pid) else {
            return [DoctorCheck("app.running", .warn, "Summon.app is not running, so hotkeys and crash alerts are off",
                                fix: "open ~/Applications/Summon.app")]
        }
        var checks = [DoctorCheck("app.running", .pass, "Running since \(Self.timestamp(health.launchedAt))")]
        let taken = health.hotkeys.filter { !$0.value }.keys.sorted()
        if taken.isEmpty {
            checks.append(DoctorCheck("app.hotkeys", .pass, health.hotkeys.keys.sorted().joined(separator: ", ")))
        } else {
            checks.append(DoctorCheck("app.hotkeys", .fail, "\(taken.joined(separator: " and ")) taken by another app",
                                      fix: "Free the shortcut in the other app (or System Settings › Keyboard › Keyboard Shortcuts), then quit and reopen Summon"))
        }
        switch health.notifications {
        case "authorized"?, "provisional"?, "ephemeral"?:
            checks.append(DoctorCheck("app.notifications", .pass, "Allowed"))
        case "denied"?:
            checks.append(DoctorCheck("app.notifications", .warn, "Notifications are off, so crashes are not announced",
                                      fix: "open \"x-apple.systempreferences:com.apple.Notifications-Settings.extension\" and allow Summon"))
        case nil:
            checks.append(DoctorCheck("app.notifications", .warn, "The app runs outside Summon.app, so it cannot post notifications",
                                      fix: "Run the bundled app: open ~/Applications/Summon.app"))
        case let other?:
            checks.append(DoctorCheck("app.notifications", .warn, "Notification permission is \(other)",
                                      fix: "Quit and reopen Summon to be asked again"))
        }
        return checks
    }

    // MARK: Permissions

    func crashReports() -> DoctorCheck {
        let dir = paths.diagnosticReportDirs[0]
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return DoctorCheck("permissions.reports", .pass, "No crash reports folder yet")
        }
        guard FileManager.default.isReadableFile(atPath: dir.path),
              (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) != nil else {
            return DoctorCheck("permissions.reports", .warn, "\(tilde(dir.path)) cannot be read, so crashes are not seen",
                               fix: "Give your terminal Full Disk Access: open \"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles\"")
        }
        return DoctorCheck("permissions.reports", .pass, "Crash reports are readable")
    }

    // MARK: Helpers

    func tilde(_ path: String) -> String {
        let home = paths.home.path
        return path.hasPrefix(home + "/") ? "~" + String(path.dropFirst(home.count)) : path
    }

    static func themeFolders(in dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return !name.hasPrefix(".")
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    static func list(_ items: [String]) -> String {
        items.count <= 3 ? items.joined(separator: ", ") : items.prefix(3).joined(separator: ", ") + " and \(items.count - 3) more"
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Plain text for a terminal: one line per check, with its fix underneath.
    public static func render(_ report: DoctorReport) -> String {
        let width = report.checks.map(\.id.count).max() ?? 0
        var lines = ["summon \(SummonVersion.current)", ""]
        for check in report.checks {
            let mark: String
            switch check.status {
            case .pass: mark = "ok  "
            case .warn: mark = "warn"
            case .fail: mark = "FAIL"
            }
            lines.append("\(mark)  \(check.id.padding(toLength: width, withPad: " ", startingAt: 0))  \(check.detail)")
            if let fix = check.fix, check.status != .pass {
                lines.append(String(repeating: " ", count: width + 8) + "fix: \(fix)")
            }
        }
        let fails = report.checks.filter { $0.status == .fail }.count
        let warns = report.checks.filter { $0.status == .warn }.count
        lines.append("")
        if fails == 0 && warns == 0 {
            lines.append("Summon is healthy.")
        } else {
            lines.append("\(fails) failed, \(warns) warning(s).")
        }
        return lines.joined(separator: "\n")
    }
}
