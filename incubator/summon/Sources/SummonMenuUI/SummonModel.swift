import AppKit
import Foundation
import Observation
import SummonCore

/// App state for the menu bar panel (with its Summon Menu) and Settings. Actions go through the `summon` CLI,
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

    public var currentThemeName: String? {
        guard let currentThemeSlug else { return nil }
        return themes.first { $0.slug == currentThemeSlug }?.name ?? currentThemeSlug
    }
    /// The terminal agents open in, and the ones Settings can offer.
    public private(set) var terminal: TerminalApp = .terminal
    public private(set) var installedTerminals: [TerminalApp] = [.terminal]
    /// Programs whose crash notifications the user muted, sorted.
    public private(set) var mutedPrograms: [String] = []
    /// Recurring agent tasks (`tasks.json`) and each one's last result ("done"/"failed"), from the event log.
    public private(set) var tasks: [RecurringTask] = []
    public private(set) var taskResults: [String: String] = [:]
    /// Per-agent model and skill choices (`~/.config/summon/agents.json`), read here, changed through the CLI.
    public private(set) var agentSettings = AgentSettings()
    /// Skills Summon ships, from `summon skills`; empty until `loadShippedSkills()` runs.
    public private(set) var shippedSkills: [String] = []
    /// Each shipped skill's description, for Settings.
    public private(set) var skillDescriptions: [String: String] = [:]
    /// What each agent's CLI reports (login, models), filled on demand; ids being checked right now.
    public private(set) var agentStatus: [String: AgentStatus] = [:]
    public private(set) var checkingAgents: Set<String> = []
    /// Every new app gets a private GitHub repo right away (`always`) or after the dialog (`ask`).
    public private(set) var repoPolicy: RepoPolicy = .always
    public private(set) var executionMode: AgentExecutionMode = .normal
    /// Agents whose CLI is on this Mac, in registry order.
    public private(set) var installedAgentIDs: [String] = []
    /// Installed plugins per agent, and which agents have each catalog plugin (filled on demand).
    public private(set) var agentPlugins: [String: [InstalledPlugin]] = [:]
    public private(set) var catalogInstalled: [String: [String: Bool]] = [:]
    public private(set) var pluginWork: String? = nil
    public private(set) var menu: MenuTree
    public private(set) var menuError: String? = nil
    /// Apps made with Summon (`~/.config/summon/projects.json`), shown in the panel.
    public private(set) var projects: [Project] = []
    /// Last action error, shown under the row that caused it.
    public var lastError: String? = nil
    /// Hotkey labels whose registration failed at launch (another app owns them); Settings marks them (C4).
    public var unavailableHotKeys: Set<String> = []

    /// System health report from summon doctor; loaded on demand.
    public private(set) var doctorReport: DoctorReport? = nil
    public private(set) var isCheckingHealth = false

    /// Per-app and per-theme health status for instant indicators and AI fixes.
    public private(set) var appHealth: [String: ItemHealth] = [:]
    public private(set) var themeHealth: [String: ItemHealth] = [:]
    /// Art jobs in ~/Summon/Art and their inspection health.
    public private(set) var artJobs: [ArtJob] = []
    public private(set) var artJobHealth: [String: ItemHealth] = [:]

    /// Shell guard results by item id. Missing means not evaluated yet (shown, unchecked).
    public private(set) var visibility: [String: Bool] = [:]
    public private(set) var checks: [String: Bool] = [:]

    /// Bumped each time the panel opens, so the view resets its search and level.
    public private(set) var launcherSession = 0
    public private(set) var launcherStartLevel: String? = nil

    public var crashCaptureEnabled: Bool {
        didSet { UserDefaults.standard.set(crashCaptureEnabled, forKey: Self.crashCaptureKey) }
    }

    public var globalMenuShortcut: PanelShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(globalMenuShortcut) {
                UserDefaults.standard.set(data, forKey: Self.globalMenuShortcutKey)
            }
            onUpdateGlobalHotKeys?()
        }
    }

    public var globalAgentShortcut: PanelShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(globalAgentShortcut) {
                UserDefaults.standard.set(data, forKey: Self.globalAgentShortcutKey)
            }
            onUpdateGlobalHotKeys?()
        }
    }

    public var panelAgentShortcut: PanelShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(panelAgentShortcut) {
                UserDefaults.standard.set(data, forKey: Self.panelAgentShortcutKey)
            }
        }
    }

    public var previousThemeSlug: String? {
        didSet {
            UserDefaults.standard.set(previousThemeSlug, forKey: Self.previousThemeKey)
        }
    }

    /// Callback to re-register global hotkeys when customized in Settings.
    @ObservationIgnored public var onUpdateGlobalHotKeys: (() -> Void)? = nil

    /// Set by the app delegate to post a notification for each new report.
    @ObservationIgnored public var onNewCrash: ((CrashReport) -> Void)? = nil
    @ObservationIgnored private var recentKey: [String] = []
    @ObservationIgnored private var scanningCrashes = false
    @ObservationIgnored private var watchTask: Task<Void, Never>? = nil

    static let crashCaptureKey = "crashCaptureEnabled"
    static let panelAgentShortcutKey = "summon.shortcut.panelAgent"
    static let globalMenuShortcutKey = "summon.shortcut.globalMenu"
    static let globalAgentShortcutKey = "summon.shortcut.globalAgent"
    static let previousThemeKey = "summon.appearance.previousTheme"

    public init(paths: SummonPaths = .live, runner: @escaping Runner = Shell.live) {
        self.paths = paths
        self.runner = runner
        self.menu = MenuTree.standard
        self.crashCaptureEnabled = UserDefaults.standard.object(forKey: Self.crashCaptureKey) as? Bool ?? true
        self.previousThemeSlug = UserDefaults.standard.string(forKey: Self.previousThemeKey)
        if let data = UserDefaults.standard.data(forKey: Self.globalMenuShortcutKey),
           let loaded = try? JSONDecoder().decode(PanelShortcut.self, from: data) {
            self.globalMenuShortcut = loaded
        } else {
            self.globalMenuShortcut = .defaultGlobalMenu
        }
        if let data = UserDefaults.standard.data(forKey: Self.globalAgentShortcutKey),
           let loaded = try? JSONDecoder().decode(PanelShortcut.self, from: data) {
            self.globalAgentShortcut = loaded
        } else {
            self.globalAgentShortcut = .defaultGlobalAgent
        }
        if let data = UserDefaults.standard.data(forKey: Self.panelAgentShortcutKey),
           let loaded = try? JSONDecoder().decode(PanelShortcut.self, from: data) {
            self.panelAgentShortcut = loaded
        } else {
            self.panelAgentShortcut = .defaultPanelAgent
        }
        reload()
    }

    // MARK: Loading

    public func reload() {
        defaultAgent = DefaultAgentStore(paths: paths).load()
        repoPolicy = RepoPolicyStore(paths: paths).load()
        do { executionMode = try ExecutionPolicyStore(paths: paths).load() }
        catch { lastError = String(describing: error) }
        let locator = ToolLocator.live()
        installedAgentIDs = AgentRegistry.all.filter { locator.find($0.command) != nil }.map(\.id)
        if let agent = defaultAgent {
            agentInstalled = ToolLocator.live().find(agent.command) != nil
        } else {
            agentInstalled = false
        }
        let themeStore = ThemeStore(paths: paths)
        themes = themeStore.all()
        currentThemeSlug = themeStore.currentSlug()
        do { tasks = try TaskStore(paths: paths).loadValidated() }
        catch { lastError = String(describing: error) }
        let events = EventLog(paths: paths).read()
        taskResults = Dictionary(events.compactMap { event in
            event.refs["task"].map { ($0, event.kind == EventKind.taskFailed ? "failed" : "done") }
        }, uniquingKeysWith: { _, newer in newer })
        let installed = TerminalApp.installed
        installedTerminals = TerminalApp.allCases.filter { installed.contains($0) }
        terminal = AgentLauncher.preferredTerminal(saved: DefaultTerminalStore(paths: paths).load(), installed: installed)
        mutedPrograms = CrashWatcher(paths: paths).muted().sorted()
        do { agentSettings = try AgentSettingsStore(paths: paths).loadValidated() }
        catch { lastError = String(describing: error) }
        reloadProjects()
        loadMenu()
    }

    func loadMenu() {
        let loaded = MenuTree.load(from: paths.menuFile)
        menu = loaded.tree.withProjects(projects, themes: themes, appHealth: appHealth, themeHealth: themeHealth)
        menuError = loaded.problem
    }

    // MARK: Crash watching

    public func startWatching(interval: Duration = .seconds(30)) {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let model = self else { return }
                await model.scanCrashes()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    func scanCrashes() async {
        guard !scanningCrashes else { return }
        scanningCrashes = true
        defer { scanningCrashes = false }
        let watcher = CrashWatcher(paths: paths)
        do {
            var hasMore: Bool
            repeat {
                let previousKey = recentKey
                let result = try await Task.detached { () -> ([CrashReport]?, CrashWatcher.Batch, [String]) in
                    // Reports can be megabytes each: re-parse only when metadata or mutes change.
                    let key = watcher.reportCacheKey()
                    let recent = key == previousKey ? nil : watcher.reports(since: nil, limit: 10)
                    return (recent, try watcher.scanNewReports(limit: 5), key)
                }.value
                if let recent = result.0 { recentCrashes = recent }
                recentKey = result.2
                if crashCaptureEnabled {
                    for report in result.1.reports { onNewCrash?(report) }
                }
                hasMore = result.1.hasMore
                if hasMore { await Task.yield() }
            } while hasMore && !Task.isCancelled
        } catch {
            lastError = "Could not scan diagnostic reports: \(error)"
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

    public func checkHealth() async {
        guard !isCheckingHealth else { return }
        isCheckingHealth = true
        defer { isCheckingHealth = false }
        let environment = ProcessInfo.processInfo.environment
        let shellPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = paths.home
        let doctor = Doctor(
            paths: paths,
            runner: runner,
            tools: ToolLocator.live(),
            shellTools: ToolLocator(searchPath: shellPath, isExecutable: ToolLocator.live().isExecutable),
            share: URL(fileURLWithPath: SummonPaths.installPath(environment: environment), isDirectory: true),
            appLocations: [
                home.appendingPathComponent("Applications/Summon.app", isDirectory: true),
                URL(fileURLWithPath: "/Applications/Summon.app", isDirectory: true),
            ],
            installedTerminals: TerminalApp.installed,
            isProcessRunning: { pid in pid > 0 && kill(pid, 0) == 0 }
        )
        doctorReport = await doctor.run()
    }

    public func fixWithAI() {
        Task {
            await summon(["fix"])
        }
    }

    public func setGlobalMenuShortcut(_ shortcut: PanelShortcut) {
        self.globalMenuShortcut = shortcut
    }

    public func resetGlobalMenuShortcut() {
        self.globalMenuShortcut = .defaultGlobalMenu
    }

    public func setGlobalAgentShortcut(_ shortcut: PanelShortcut) {
        self.globalAgentShortcut = shortcut
    }

    public func resetGlobalAgentShortcut() {
        self.globalAgentShortcut = .defaultGlobalAgent
    }

    public func setPanelAgentShortcut(_ shortcut: PanelShortcut) {
        self.panelAgentShortcut = shortcut
    }

    public func resetPanelAgentShortcut() {
        self.panelAgentShortcut = .defaultPanelAgent
    }

    public func reloadProjects() {
        let loaded = (try? ProjectStore(paths: paths).load().projects) ?? []
        projects = loaded
        checkAppsAndThemesHealth()
        loadMenu()
    }

    public func checkAppsAndThemesHealth() {
        var newAppHealth: [String: ItemHealth] = [:]
        for project in projects {
            newAppHealth[project.name] = AppHealthChecker.check(project: project, recentCrashes: recentCrashes)
        }
        appHealth = newAppHealth

        var newThemeHealth: [String: ItemHealth] = [:]
        for theme in themes {
            newThemeHealth[theme.slug] = AppHealthChecker.check(theme: theme, themesFolder: paths.themes)
        }
        themeHealth = newThemeHealth

        let scannedJobs = AppHealthChecker.scanArtJobs(artFolder: paths.art)
        artJobs = scannedJobs
        var newArtHealth: [String: ItemHealth] = [:]
        for job in scannedJobs {
            newArtHealth[job.name] = AppHealthChecker.check(artJob: job)
        }
        artJobHealth = newArtHealth
    }

    public func fixArtJobWithAI(_ job: ArtJob) {
        let health = artJobHealth[job.name] ?? AppHealthChecker.check(artJob: job)
        let prompt = health.fixPrompt ?? "Investigate and complete the art job in ~/Summon/Art/\(job.name) using summon-art skill."
        askAgent(prompt: prompt)
    }

    public func fixAppWithAI(_ project: Project) {
        let health = appHealth[project.name] ?? AppHealthChecker.check(project: project, recentCrashes: recentCrashes)
        let prompt = health.fixPrompt ?? "Investigate and fix any issues in project '\(project.name)' at \(project.path)."
        askAgent(prompt: prompt)
    }

    public func fixThemeWithAI(_ theme: Theme) {
        let health = themeHealth[theme.slug] ?? AppHealthChecker.check(theme: theme, themesFolder: paths.themes)
        let prompt = health.fixPrompt ?? "Investigate and fix any issues in theme '\(theme.name)' at ~/.config/summon/themes/\(theme.slug)."
        askAgent(prompt: prompt)
    }

    public func health(for item: MenuItem) -> ItemHealth? {
        if item.id == "apps" {
            let all = Array(appHealth.values) + Array(themeHealth.values)
            if all.contains(where: { $0.level == .error }) {
                return ItemHealth(level: .error, badge: "Issues", detail: "Some apps or themes have errors")
            }
            if all.contains(where: { $0.level == .warning }) {
                return ItemHealth(level: .warning, badge: "Warnings", detail: "Some apps or themes have warnings")
            }
            return all.isEmpty ? nil : .healthy
        }
        if item.id.hasPrefix("apps.panel.") || item.id.hasPrefix("apps.app.") || item.id.hasPrefix("apps.cli.") || item.id.hasPrefix("apps.screensaver.") {
            let name = String(item.id.split(separator: ".").last ?? "")
            return appHealth[name]
        }
        if item.id.hasPrefix("apps.theme.") || item.id.hasPrefix("style.theme.") {
            let slug = String(item.id.split(separator: ".").last ?? "")
            return themeHealth[slug]
        }
        return nil
    }

    /// Opens the project's built .app if present, else reveals its folder.
    public func openProject(_ project: Project) {
        let folder = URL(fileURLWithPath: project.path)
        let pascal = ProjectName.pascal(project.name)
        let primaryApp = folder.appendingPathComponent("build/\(pascal).app")
        if FileManager.default.fileExists(atPath: primaryApp.path) {
            NSWorkspace.shared.open(primaryApp)
            return
        }
        let buildDir = folder.appendingPathComponent("build")
        if let items = try? FileManager.default.contentsOfDirectory(at: buildDir, includingPropertiesForKeys: nil),
           let appURL = items.first(where: { $0.pathExtension == "app" }) {
            NSWorkspace.shared.open(appURL)
            return
        }
        NSWorkspace.shared.open(folder)
    }

    /// Problems the panel still shows: not archived, not older than a day (Activity keeps them all).
    /// `problemsVersion` makes the panel recompute after an archive.
    public var panelProblems: [CrashReport] {
        _ = problemsVersion
        return ProblemArchive(paths: paths).visible(recentCrashes)
    }
    private var problemsVersion = 0

    /// Diagnosing hands the report to the agent, so that program's reports leave the panel.
    public func diagnose(file: String) {
        if let program = recentCrashes.first(where: { $0.file == file })?.program {
            archiveProblems(recentCrashes.filter { $0.program == program })
        }
        Task { await summon(["crash", "diagnose", file]) }
    }

    public func archiveProblems(_ reports: [CrashReport]) {
        try? ProblemArchive(paths: paths).archive(reports.map(\.file))
        problemsVersion += 1
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

    public static func findBrew() -> String? {
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return ToolLocator.live().find("brew")
    }

    public func installTerminal(_ terminal: TerminalApp) async throws {
        guard let cask = terminal.caskName else { return }
        guard let brew = Self.findBrew() else {
            throw TerminalInstallError.brewMissing
        }
        let output = try await runner(brew, ["install", "--cask", cask])
        _ = output
        reload()
    }

    public func setTheme(_ slug: String) {
        if let current = currentThemeSlug, current != slug {
            previousThemeSlug = current
        }
        Task { await summon(["theme", "set", slug]) }
    }

    public func revertTheme() {
        guard let prev = previousThemeSlug else { return }
        setTheme(prev)
    }

    public func setDefaultAgent(_ id: String) {
        Task { await summon(["default", "agent", id]) }
    }

    /// nil or blank goes back to the CLI's own default model.
    public func setAgentModel(_ model: String?, for id: String) {
        Task { await summon(AgentSettingsCommand.model(model, for: id)) }
    }

    /// All Agents: the skills every agent follows unless it has its own list.
    public func setDefaultSkill(_ name: String, on: Bool) {
        let skills = agentSettings.defaultSkills(shipped: shippedSkills, turning: name, on: on)
        Task { await summon(AgentSettingsCommand.defaultSkills(skills)) }
    }

    /// The agent follows All Agents' skills again.
    public func useDefaultSkills(for id: String) {
        Task { await summon(AgentSettingsCommand.skills(nil, for: id)) }
    }

    public func setAgentSkill(_ name: String, on: Bool, for id: String) {
        let skills = agentSettings.skills(for: id, shipped: shippedSkills, turning: name, on: on)
        Task { await summon(AgentSettingsCommand.skills(skills, for: id)) }
    }

    /// Asks the bundled CLI which skills ship, so the app and `summon agents set` agree on the names.
    public func loadShippedSkills() async {
        guard let summonPath else { return }
        guard let output = try? await runner(summonPath, ["skills", "list"]) else { return }
        shippedSkills = AgentSettingsCommand.skillNames(fromList: output)
        if let json = try? await runner(summonPath, ["skills", "list", "--json"]),
           let infos = try? JSONDecoder().decode([SkillInfo].self, from: Data(json.utf8)) {
            skillDescriptions = Dictionary(infos.compactMap { info in info.description.map { (info.name, $0) } },
                                           uniquingKeysWith: { first, _ in first })
        }
    }

    /// Asks the agent's CLI whether it is logged in and which models it has (`summon agents status --json`).
    public func checkAgent(_ id: String) async {
        guard let summonPath, !checkingAgents.contains(id) else { return }
        checkingAgents.insert(id)
        defer { checkingAgents.remove(id) }
        guard let output = try? await runner(summonPath, ["agents", "status", id, "--json"]),
              let status = try? JSONDecoder().decode(AgentStatus.self, from: Data(output.utf8)) else { return }
        agentStatus[id] = status
    }

    public func loadPlugins(_ id: String) async {
        guard let summonPath,
              let output = try? await runner(summonPath, ["agents", "plugins", id, "--json"]),
              let plugins = try? JSONDecoder().decode([InstalledPlugin].self, from: Data(output.utf8)) else { return }
        agentPlugins[id] = plugins
    }

    private struct CatalogRow: Decodable {
        let plugin: CatalogPlugin
        let agents: [String: Bool]
    }

    public func loadCatalog() async {
        guard let summonPath,
              let output = try? await runner(summonPath, ["plugins", "--json"]),
              let rows = try? JSONDecoder().decode([CatalogRow].self, from: Data(output.utf8)) else { return }
        catalogInstalled = Dictionary(rows.map { ($0.plugin.id, $0.agents) }, uniquingKeysWith: { a, _ in a })
    }

    /// The agent's own installer; the list refreshes afterwards. `pluginWork` shows progress in Settings.
    public func addPlugin(_ spec: String, to id: String) {
        Task {
            pluginWork = "Adding \(spec)…"
            await summon(["agents", "plugin-add", id, spec])
            pluginWork = nil
            await loadPlugins(id)
            await loadCatalog()
        }
    }

    public func installEverywhere(_ pluginID: String) {
        Task {
            pluginWork = "Installing in every agent…"
            await summon(["plugins", "install", pluginID])
            pluginWork = nil
            await loadCatalog()
        }
    }

    public func fixPlugin(_ pluginID: String, agent id: String) {
        Task { await summon(["plugins", "fix", pluginID, id]) }
    }

    /// What `summon clean` would move to the Trash right now, for Settings › General.
    public func cleanPreview() async -> SummonCleaner.Plan? {
        guard let summonPath, let output = try? await runner(summonPath, ["clean", "--json"]) else { return nil }
        return try? JSONDecoder().decode(SummonCleaner.Plan.self, from: Data(output.utf8))
    }

    public func setExecutionMode(_ mode: AgentExecutionMode) {
        Task { await summon(["default", "execution", mode.rawValue]) }
    }

    public func setRepoPolicy(_ policy: RepoPolicy) {
        Task { await summon(["default", "repos", policy.rawValue]) }
    }

    public func cleanNow() {
        Task { await summon(["clean", "--apply"]) }
    }

    /// Opens the agent's own login in a terminal; Settings offers Check Again afterwards.
    public func logIn(_ id: String) {
        Task { await summon(["agents", "login", id]) }
    }

    // MARK: Summon Menu (in the panel)

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
        if item.id.hasPrefix("apps.") {
            let parts = item.id.split(separator: ".")
            if parts.count >= 3 {
                let projectName = String(parts[2])
                if let project = projects.first(where: { $0.name == projectName }) {
                    openProject(project)
                    return
                }
            }
        }
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

    /// GUI apps get a minimal PATH; menu commands expect user tools, Homebrew and the bundled `summon`.
    private var shellPrefix: String {
        let home = paths.home.path
        var dirs = [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
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
        model.tasks = [RecurringTask(id: "brew", name: "Brew check", prompt: "Check brew updates and summarize", agent: "claude",
                                    schedule: TaskSchedule(kind: .weekdays, hour: 9, minute: 0))]
        model.taskResults = ["brew": "done"]
        return model
    }
}

public enum TerminalInstallError: LocalizedError, Sendable {
    case brewMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .brewMissing:
            return "Homebrew is not installed. Please install Homebrew from https://brew.sh first."
        case .failed(let message):
            return "Installation failed: \(message)"
        }
    }
}
