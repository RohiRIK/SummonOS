import Foundation
import Observation
import SummonCore

/// App state for the menu bar panel, the launcher and Settings. Actions go through the `summon` CLI,
/// so the app and agents use one code path (and one checkpoint rule).
@MainActor
@Observable
public final class SummonModel {
    public let paths: SummonPaths
    let runner: Runner

    public private(set) var defaultAgent: Agent? = nil
    public private(set) var agentInstalled = false
    public private(set) var recentCrashes: [CrashReport] = []
    public private(set) var themes: [Theme] = []
    public private(set) var currentThemeSlug: String? = nil
    /// The terminal agents open in, and the ones Settings can offer.
    public private(set) var terminal: TerminalApp = .terminal
    public private(set) var installedTerminals: [TerminalApp] = [.terminal]
    /// Programs whose crash notifications the user muted, sorted.
    public private(set) var mutedPrograms: [String] = []
    /// Per-agent model and skill choices (`~/.config/summon/agents.json`), read here, changed through the CLI.
    public private(set) var agentSettings = AgentSettings()
    /// Skills Summon ships, from `summon skills`; empty until `loadShippedSkills()` runs.
    public private(set) var shippedSkills: [String] = []
    /// Recurring tasks (`~/.config/summon/tasks.json`), read here, changed through `summon task`.
    public private(set) var tasks: [AgentTask] = []
    /// The newest run of each task, by id, from the event log.
    public private(set) var lastTaskRuns: [String: LoggedEvent] = [:]
    /// Set when tasks.json cannot be read; Settings shows it instead of an empty list.
    public private(set) var tasksError: String? = nil
    /// Tasks started with Run Now that have not finished.
    public private(set) var runningTasks: Set<String> = []
    public private(set) var menu: MenuTree
    public private(set) var menuError: String? = nil
    /// Last action error, shown under the row that caused it.
    public var lastError: String? = nil

    /// Shell guard results by item id. Missing means not evaluated yet (shown, unchecked).
    public private(set) var visibility: [String: Bool] = [:]
    public private(set) var checks: [String: Bool] = [:]

    /// Bumped each time the launcher opens, so the view resets its search and level.
    public private(set) var launcherSession = 0
    public private(set) var launcherStartLevel: String? = nil

    public var crashCaptureEnabled: Bool {
        didSet { UserDefaults.standard.set(crashCaptureEnabled, forKey: Self.crashCaptureKey) }
    }

    public var taskNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(taskNotificationsEnabled, forKey: Self.taskNotificationsKey) }
    }

    /// Set by the app delegate to post a notification for each new report.
    @ObservationIgnored public var onNewCrash: ((CrashReport) -> Void)? = nil
    @ObservationIgnored private var recentKey: [String] = []
    @ObservationIgnored private var watchTask: Task<Void, Never>? = nil
    /// Set by the app delegate to post a notification for each finished task run.
    @ObservationIgnored public var onTaskRun: ((LoggedEvent) -> Void)? = nil
    /// Time of the newest task run already seen; nil until the first scan, which never notifies.
    @ObservationIgnored private var lastTaskRunSeen: Date? = nil

    static let crashCaptureKey = "crashCaptureEnabled"
    static let taskNotificationsKey = "taskNotificationsEnabled"

    public init(paths: SummonPaths = .live, runner: @escaping Runner = Shell.live) {
        self.paths = paths
        self.runner = runner
        self.menu = MenuTree.standard
        self.crashCaptureEnabled = UserDefaults.standard.object(forKey: Self.crashCaptureKey) as? Bool ?? true
        self.taskNotificationsEnabled = UserDefaults.standard.object(forKey: Self.taskNotificationsKey) as? Bool ?? true
        reload()
    }

    // MARK: Loading

    public func reload() {
        defaultAgent = DefaultAgentStore(paths: paths).load()
        if let agent = defaultAgent {
            agentInstalled = ToolLocator.live().find(agent.command) != nil
        } else {
            agentInstalled = false
        }
        let themeStore = ThemeStore(paths: paths)
        themes = themeStore.all()
        currentThemeSlug = themeStore.currentSlug()
        let installed = TerminalApp.installed
        installedTerminals = TerminalApp.allCases.filter { installed.contains($0) }
        terminal = AgentLauncher.preferredTerminal(saved: DefaultTerminalStore(paths: paths).load(), installed: installed)
        mutedPrograms = CrashWatcher(paths: paths).muted().sorted()
        agentSettings = AgentSettingsStore(paths: paths).load()
        loadTasks()
        loadMenu()
    }

    func loadTasks() {
        do {
            tasks = try TaskStore(paths: paths).load().tasks
            tasksError = nil
        } catch {
            tasksError = "\(paths.tasksFile.path) is not valid: \(error.localizedDescription)"
        }
        lastTaskRuns = EventLog(paths: paths).lastTaskRuns()
    }

    func loadMenu() {
        let loaded = MenuTree.load(from: paths.menuFile)
        menu = loaded.tree
        menuError = loaded.problem
    }

    // MARK: Crash watching

    public func startWatching(interval: Duration = .seconds(30)) {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let model = self else { return }
                await model.scanCrashes()
                await model.scanTaskRuns()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    func scanCrashes() async {
        let watcher = CrashWatcher(paths: paths)
        let since = watcher.marker()
        let scanStart = Date()
        let previousKey = recentKey
        let result = await Task.detached { () -> ([CrashReport]?, [CrashReport], [String]) in
            // Reports can be megabytes each: re-parse the recent list only when the files or mutes changed.
            let key = watcher.reportFiles(since: nil).prefix(30).map(\.path) + watcher.muted().sorted()
            let recent = key == previousKey ? nil : watcher.reports(since: nil, limit: 10)
            // The first scan only sets the marker: old reports never notify.
            let fresh = since == nil ? [] : watcher.reports(since: since, limit: 5)
            return (recent, fresh, key)
        }.value
        if let recent = result.0 {
            recentCrashes = recent
        }
        recentKey = result.2
        try? watcher.saveMarker(scanStart)
        if crashCaptureEnabled {
            for report in result.1 {
                onNewCrash?(report)
            }
        }
    }

    /// Notifies about task runs that finished since the last scan, whoever started them (launchd or Run Now).
    func scanTaskRuns() async {
        let log = EventLog(paths: paths)
        let runs = await Task.detached { log.read().filter { $0.kind == EventKind.taskRun } }.value
        let newest = runs.last?.time
        guard let seen = lastTaskRunSeen else {
            lastTaskRunSeen = newest ?? Date()
            return
        }
        let fresh = runs.filter { $0.time > seen }
        guard !fresh.isEmpty else { return }
        lastTaskRunSeen = newest
        loadTasks()
        if taskNotificationsEnabled {
            for run in fresh {
                onTaskRun?(run)
            }
        }
    }

    // MARK: Actions

    /// The `summon` CLI shipped inside the app bundle, else one on PATH.
    var summonPath: String? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/summon").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        return ToolLocator.live().find("summon")
    }

    func summon(_ arguments: [String]) async {
        guard let summonPath else {
            lastError = "The summon command is missing. Reinstall Summon."
            return
        }
        do {
            _ = try await runner(summonPath, arguments)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        reload()
    }

    public func askAgent(prompt: String? = nil) {
        Task {
            if let prompt {
                await summon(["agent", "prompt", prompt])
            } else {
                await summon(["agent"])
            }
        }
    }

    public func diagnose(file: String) {
        Task { await summon(["crash", "diagnose", file]) }
    }

    public func mute(program: String) {
        Task {
            await summon(["crash", "mute", program])
            await scanCrashes()
        }
    }

    public func unmute(program: String) {
        Task {
            await summon(["crash", "mute", program, "off"])
            await scanCrashes()
        }
    }

    public func setTerminal(_ terminal: TerminalApp) {
        Task { await summon(["default", "terminal", terminal.rawValue]) }
    }

    public func setTheme(_ slug: String) {
        Task { await summon(["theme", "set", slug]) }
    }

    public func setDefaultAgent(_ id: String) {
        Task { await summon(["default", "agent", id]) }
    }

    /// nil or blank goes back to the CLI's own default model.
    public func setAgentModel(_ model: String?, for id: String) {
        Task { await summon(AgentSettingsCommand.model(model, for: id)) }
    }

    public func setAgentSkill(_ name: String, on: Bool, for id: String) {
        let skills = agentSettings.skills(for: id, shipped: shippedSkills, turning: name, on: on)
        Task { await summon(AgentSettingsCommand.skills(skills, for: id)) }
    }

    /// Adds a task through the CLI (which writes its LaunchAgent). Returns false and sets `lastError` on failure.
    public func addTask(name: String, prompt: String, schedule: TaskSchedule) async -> Bool {
        await summon(["task", "add", name] + schedule.arguments + ["--", prompt])
        return lastError == nil
    }

    public func setTask(_ id: String, enabled: Bool) {
        Task { await summon(["task", enabled ? "enable" : "disable", id]) }
    }

    /// Waits for the run; the result arrives as an Activity entry and a notification.
    public func runTask(_ id: String) {
        guard !runningTasks.contains(id) else { return }
        runningTasks.insert(id)
        Task {
            await summon(["task", "run", id])
            runningTasks.remove(id)
            await scanTaskRuns()
        }
    }

    public func removeTask(_ id: String) {
        Task { await summon(["task", "remove", id]) }
    }

    /// Asks the bundled CLI which skills ship, so the app and `summon agents set` agree on the names.
    public func loadShippedSkills() async {
        guard let summonPath else { return }
        guard let output = try? await runner(summonPath, ["skills", "list"]) else { return }
        shippedSkills = AgentSettingsCommand.skillNames(fromList: output)
    }

    // MARK: Launcher

    public func prepareLauncher(startAt level: String?) {
        loadMenu()
        launcherStartLevel = level.flatMap { menu.item($0) == nil ? nil : $0 }
        launcherSession += 1
    }

    /// Children of `parent` whose `when` guard did not fail.
    public func visibleChildren(of parent: String?) -> [MenuItem] {
        menu.children(of: parent).filter { visibility[$0.id] != false }
    }

    public func hasChildren(_ item: MenuItem) -> Bool {
        !menu.children(of: item.id).isEmpty
    }

    /// Runs the `when` and `checked` guards of these items.
    public func evaluateGuards(_ items: [MenuItem]) async {
        for item in items {
            if let guardCommand = item.when {
                visibility[item.id] = await succeeds(guardCommand)
            }
            if let checkCommand = item.checked {
                checks[item.id] = await succeeds(checkCommand)
            }
        }
    }

    public func run(_ item: MenuItem) {
        guard let action = item.action else { return }
        Task {
            do {
                _ = try await runner("/bin/zsh", ["-c", shellPrefix + action])
                lastError = nil
            } catch {
                lastError = "\(item.label): \(error)"
            }
            reload()
        }
    }

    private func succeeds(_ command: String) async -> Bool {
        do {
            _ = try await runner("/bin/zsh", ["-c", shellPrefix + command])
            return true
        } catch {
            return false
        }
    }

    /// GUI apps get a minimal PATH; menu commands expect Homebrew, ~/.local/bin and the bundled `summon`.
    private var shellPrefix: String {
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin", paths.home.appendingPathComponent(".local/bin").path]
        if let summonPath {
            dirs.insert((summonPath as NSString).deletingLastPathComponent, at: 0)
        }
        let quoted = dirs.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: ":")
        return "export PATH=" + quoted + ":\"$PATH\"; "
    }
}

extension SummonModel {
    /// A model with sample data for previews; it never runs commands.
    public static func preview() -> SummonModel {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("summon-preview", isDirectory: true)
        let model = SummonModel(paths: SummonPaths(home: home)) { _, _ in "" }
        model.recentCrashes = [
            CrashReport(
                file: "/tmp/Example-2026-10-17-101500.ips", kind: .crash, bugType: "309", appName: "Example",
                appVersion: "1.2", timestamp: "2026-10-17 10:15:00.00 +0000", incidentID: nil, osVersion: "macOS 26.0",
                process: "Example", pid: 4242, exceptionType: "EXC_BAD_ACCESS", signal: "SIGSEGV", topFrames: []
            ),
        ]
        model.defaultAgent = AgentRegistry.find("claude")
        model.agentInstalled = true
        model.installedTerminals = [.ghostty, .kitty, .terminal]
        model.terminal = .ghostty
        model.mutedPrograms = ["adminbyrequest"]
        model.shippedSkills = ["diagnose-crash-mac", "mac-app", "mac-logs", "summon", "summon-art", "summon-mac"]
        model.agentSettings.setModel("opus", for: "claude")
        model.agentSettings.setSkills(["summon", "summon-mac"], for: "codex")
        // Decoded without validation: previews need names, not full palettes.
        model.themes = [("Summon Night", "summon-night", "dark"), ("Summon Dawn", "summon-dawn", "light")].compactMap { name, slug, look in
            let colors = ##"{"background":"#0B0D17","foreground":"#E6E1F5","accent":"#8B5CF6","accent2":"#22D3EE","muted":"#6B6880","selection":"#2A2440","cursor":"#C4B5FD","border_active":"#8B5CF6","border_inactive":"#2A2440"}"##
            let json = ##"{"name":"\##(name)","slug":"\##(slug)","appearance":"\##(look)","colors":\##(colors),"terminal":[],"font":"JetBrainsMono Nerd Font","wallpapers":[]}"##
            return try? JSONDecoder().decode(Theme.self, from: Data(json.utf8))
        }
        model.currentThemeSlug = "summon-night"
        model.tasks = [
            AgentTask(id: "morning-crashes", prompt: "Summarize crash reports from the last day and say which app to look at first.",
                      schedule: .daily(hour: 9, minute: 0, weekdays: [1, 2, 3, 4, 5])),
            AgentTask(id: "disk-space", prompt: "Check free disk space and list the five largest folders in ~/Library/Caches.",
                      schedule: .every(minutes: 360), enabled: false),
        ]
        model.lastTaskRuns = [
            "morning-crashes": LoggedEvent(time: Date().addingTimeInterval(-3_600), kind: EventKind.taskRun,
                                           title: "Task morning-crashes finished", detail: "No new crashes.",
                                           refs: ["task": "morning-crashes", "status": "ok"]),
        ]
        model.runningTasks = []
        return model
    }
}
