import AppKit
import ApplicationServices
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
    private let live: Bool

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
    /// Recurring tasks and their last terminal outcome, projected from the one shared activity read.
    public private(set) var tasks: [RecurringTask] = []
    public private(set) var taskResults: [String: String] = [:]
    /// Per-agent model and skill choices (`~/.config/summon/agents.json`), read here, changed through the CLI.
    public private(set) var agentSettings = AgentSettings()
    /// Accessibility lets the agent hotkey read the selected text and window title.
    public private(set) var accessibilityGranted = AXIsProcessTrusted()
    /// Allow… was clicked; if the permission is still off, the switch in the list belongs to an older build.
    public private(set) var accessibilityRequested = false
    /// Set by `summon://settings/<section>`; the Settings window switches to it and clears it.
    public var requestedSettingsSection: SettingsSection?
    /// The panel's "Undo <agent> Session" row; nil hides it.
    public private(set) var undoOffer: UndoOffer?
    /// Skills Summon ships, from `summon skills`; empty until `loadShippedSkills()` runs.
    public private(set) var shippedSkills: [String] = []
    /// Each shipped skill's description, for Settings.
    public private(set) var skillDescriptions: [String: String] = [:]
    /// What each agent's CLI reports (login, models), filled on demand; ids being checked right now.
    public private(set) var agentStatus: [String: AgentStatus] = [:]
    public private(set) var checkingAgents: Set<String> = []
    /// Every new app gets a private GitHub repo right away (`always`) or after the dialog (`ask`).
    public private(set) var repoPolicy: RepoPolicy = .ask
    public private(set) var executionMode: AgentExecutionMode = .normal
    /// A newer Summon on the update channel (checked at launch, then daily); nil hides the panel's Update row.
    public private(set) var availableUpdate: UpdateCheck?
    public private(set) var updateChannel: UpdateChannel = .stable
    public private(set) var checksForUpdates = true
    public private(set) var isUpdating = false
    /// The last Check Now or install result for Settings ("up to date", an error).
    public private(set) var updateStatus: String?
    /// Outdated agents, Homebrew, bun and npm packages and macOS updates (`SoftwareUpdateCheck`), checked with Summon's.
    public private(set) var packageUpdates: [SoftwareUpdate] = []
    public private(set) var updatePreferences = UpdatePreferences()
    /// Each row's install in the Updates window; a new check starts clean.
    public private(set) var updateStates: [String: UpdateRowState] = [:]
    public private(set) var lastUpdateCheck: Date?
    public private(set) var isCheckingUpdates = false
    /// A check found these (AppDelegate posts at most one notification per new set).
    @ObservationIgnored public var onUpdatesFound: (([SoftwareUpdate]) -> Void)?
    @ObservationIgnored private var installQueue: [SoftwareUpdate] = []
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var updateInstallTask: Task<Void, Never>?
    @ObservationIgnored private var updateCheckTask: Task<Void, Never>?
    @ObservationIgnored private var updateCheckGeneration = 0
    /// The Updates window's list: Summon first, then the checked groups, minus skipped versions.
    public var updates: [SoftwareUpdate] {
        let summon = availableUpdate.map { SoftwareUpdate.summon(current: $0.current, latest: $0.release.version, tag: $0.release.tag) }
        return updatePreferences.shown((summon.map { [$0] } ?? []) + packageUpdates)
    }
    /// Not installed yet: what the panel and the notification count (an updated row stays until the next check).
    public var pendingUpdates: [SoftwareUpdate] { updates.filter { updateStates[$0.id] != .done } }
    /// Agents whose CLI is on this Mac, in registry order.
    public private(set) var installedAgentIDs: [String] = []
    /// Installed plugins per agent, and which agents have each catalog plugin (filled on demand).
    public private(set) var agentPlugins: [String: [InstalledPlugin]] = [:]
    public private(set) var catalogInstalled: [String: [String: Bool]] = [:]
    public private(set) var pluginWork: String? = nil
    public private(set) var menu: MenuTree
    public private(set) var menuError: String? = nil
    public private(set) var menuRevision = 0
    @ObservationIgnored private var baseMenu: MenuTree = .standard
    @ObservationIgnored private weak var activity: ActivityModel?
    @ObservationIgnored private var reloadGeneration = 0
    @ObservationIgnored private var reloadTask: Task<Void, Never>?
    @ObservationIgnored private var reloadWorker: Task<SummonDiskSnapshot, Never>?
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var loadError: String?
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
    @ObservationIgnored private var guardGeneration = 0

    /// Bumped each time the panel opens, so the view resets its search and level.
    public private(set) var launcherSession = 0
    public private(set) var launcherStartLevel: String? = nil
    @ObservationIgnored private var requestedLauncherLevel: String?

    public var crashCaptureEnabled: Bool {
        didSet { UserDefaults.standard.set(crashCaptureEnabled, forKey: Self.crashCaptureKey) }
    }

    /// Summon's floating alert or a macOS banner for new crashes; never both.
    public var crashAlertStyle: CrashAlertStyle {
        didSet { UserDefaults.standard.set(crashAlertStyle.rawValue, forKey: Self.crashAlertStyleKey) }
    }

    /// Banners for scheduled task results (posted by the app from the event log). On by default.
    public var taskNotificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(taskNotificationsEnabled, forKey: Self.taskNotificationsKey) }
    }

    /// Play the system sound with Summon's banners. On by default.
    public var notificationSound: Bool {
        didSet { UserDefaults.standard.set(notificationSound, forKey: Self.notificationSoundKey) }
    }

    /// Show a running agent's elapsed time next to the menu bar icon (`MenuBarStatus`). On by default.
    public var menuBarShowsAgentTime: Bool {
        didSet {
            UserDefaults.standard.set(menuBarShowsAgentTime, forKey: Self.menuBarShowsAgentTimeKey)
            onMenuBarLabelChanged?()
        }
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
    /// Set by `AppDelegate`: redraw the status item after a menu bar setting changed.
    @ObservationIgnored public var onMenuBarLabelChanged: (() -> Void)? = nil

    /// Set by the app delegate to announce the new reports of one scan, all at once (oldest first).
    @ObservationIgnored public var onNewCrashes: (([CrashReport]) -> Void)? = nil
    @ObservationIgnored private var recentKey: [String] = []
    @ObservationIgnored private var scanningCrashes = false
    @ObservationIgnored private var watchTask: Task<Void, Never>? = nil
    @ObservationIgnored private var crashFolders: [FileWatch] = []
    @ObservationIgnored private var pendingCrashScan: Task<Void, Never>?
    @ObservationIgnored private var crashScanGeneration = 0
    @ObservationIgnored private var crashRescanRequested = false

    static let crashCaptureKey = "crashCaptureEnabled"
    static let crashAlertStyleKey = "summon.notifications.crashStyle"
    static let taskNotificationsKey = "summon.notifications.tasks"
    static let notificationSoundKey = "summon.notifications.sound"
    static let menuBarShowsAgentTimeKey = "summon.menuBar.showsAgentTime"
    static let panelAgentShortcutKey = "summon.shortcut.panelAgent"
    static let globalMenuShortcutKey = "summon.shortcut.globalMenu"
    static let globalAgentShortcutKey = "summon.shortcut.globalAgent"
    static let previousThemeKey = "summon.appearance.previousTheme"

    public init(paths: SummonPaths = .live, runner: @escaping Runner = Shell.live, live: Bool = true) {
        self.paths = paths
        self.runner = runner
        self.live = live
        self.menu = MenuTree.standard
        self.crashCaptureEnabled = UserDefaults.standard.object(forKey: Self.crashCaptureKey) as? Bool ?? true
        self.crashAlertStyle = UserDefaults.standard.string(forKey: Self.crashAlertStyleKey)
            .flatMap(CrashAlertStyle.init(rawValue:)) ?? .default
        self.taskNotificationsEnabled = UserDefaults.standard.object(forKey: Self.taskNotificationsKey) as? Bool ?? true
        self.notificationSound = UserDefaults.standard.object(forKey: Self.notificationSoundKey) as? Bool ?? true
        // Off unless chosen (owner, 2026-10-25): the menu bar shows Summon's icon only; the panel's Now has the clock.
        self.menuBarShowsAgentTime = UserDefaults.standard.object(forKey: Self.menuBarShowsAgentTimeKey) as? Bool ?? false
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
        if live { reload() }
    }

    // MARK: Loading

    /// The panel keeps the last valid menu while file-derived state is collected off the main actor.
    /// Only the latest generation may publish; an invalid store never erases its last good value.
    public func reload() {
        guard !stopped else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        reloadTask?.cancel()
        reloadWorker?.cancel()
        let paths = paths
        let crashes = recentCrashes
        let worker = Task.detached(priority: .utility) {
            let interval = PanelTrace.signposter.beginInterval("SourceCollection", id: PanelTrace.signposter.makeSignpostID())
            defer { PanelTrace.signposter.endInterval("SourceCollection", interval, "menu") }
            return SummonDiskSnapshot.collect(paths: paths, crashes: crashes)
        }
        reloadWorker = worker
        reloadTask = Task { [weak self] in
            let snapshot = await worker.value
            guard !Task.isCancelled, let self, self.reloadGeneration == generation else { return }
            let interval = PanelTrace.signposter.beginInterval("MainPublication", id: PanelTrace.signposter.makeSignpostID())
            self.publish(snapshot)
            PanelTrace.signposter.endInterval("MainPublication", interval, "menu")
            self.reloadWorker = nil
            self.reloadTask = nil
        }
    }

    /// AppDelegate supplies the one activity owner after both models exist.
    public func bindActivity(_ activity: ActivityModel) {
        self.activity = activity
        activity.markDirty()
    }

    /// Settings' Tasks page joins the shared reader without starting a second activity owner.
    public func refreshActivity() async {
        guard live, !stopped else { return }
        _ = await activity?.refresh()
    }

    private func publish(_ snapshot: SummonDiskSnapshot) {
        let previousAgent = defaultAgent
        let previousInstallation = agentInstalled
        if defaultAgent != snapshot.defaultAgent { defaultAgent = snapshot.defaultAgent }
        if repoPolicy != snapshot.repoPolicy { repoPolicy = snapshot.repoPolicy }
        if updateChannel != snapshot.updateChannel { updateChannel = snapshot.updateChannel }
        if checksForUpdates != snapshot.checksForUpdates { checksForUpdates = snapshot.checksForUpdates }
        if updatePreferences != snapshot.updatePreferences { updatePreferences = snapshot.updatePreferences }
        if let mode = snapshot.executionMode, executionMode != mode { executionMode = mode }
        if installedAgentIDs != snapshot.installedAgentIDs { installedAgentIDs = snapshot.installedAgentIDs }
        let installed = snapshot.defaultAgent.map { snapshot.installedAgentIDs.contains($0.id) } ?? false
        if agentInstalled != installed { agentInstalled = installed }
        if themes != snapshot.themes { themes = snapshot.themes }
        if currentThemeSlug != snapshot.currentThemeSlug { currentThemeSlug = snapshot.currentThemeSlug }
        if let loaded = snapshot.tasks, tasks != loaded { tasks = loaded }
        if installedTerminals != snapshot.installedTerminals { installedTerminals = snapshot.installedTerminals }
        if terminal != snapshot.terminal { terminal = snapshot.terminal }
        if mutedPrograms != snapshot.mutedPrograms { mutedPrograms = snapshot.mutedPrograms }
        if let loaded = snapshot.agentSettings, agentSettings != loaded { agentSettings = loaded }
        if let loaded = snapshot.projects, projects != loaded { projects = loaded }
        if snapshot.projects != nil, appHealth != snapshot.appHealth { appHealth = snapshot.appHealth }
        if artJobs != snapshot.artJobs { artJobs = snapshot.artJobs }
        if artJobHealth != snapshot.artJobHealth { artJobHealth = snapshot.artJobHealth }
        if themeHealth != snapshot.themeHealth { themeHealth = snapshot.themeHealth }
        if snapshot.menuError == nil { baseMenu = snapshot.menu }
        if menuError != snapshot.menuError { menuError = snapshot.menuError }
        if lastError == loadError { lastError = nil }
        loadError = snapshot.errors.first
        if let loadError { lastError = loadError }
        accessibilityGranted = AXIsProcessTrusted()
        loadMenu()
        if let requestedLauncherLevel {
            self.requestedLauncherLevel = nil
            if launcherStartLevel == nil, menu.item(requestedLauncherLevel) != nil {
                launcherStartLevel = requestedLauncherLevel
                launcherSession += 1
            }
        }
        if previousAgent != defaultAgent || previousInstallation != agentInstalled { activity?.refreshStatus() }
        if snapshot.defaultAgent == nil, defaultAgent == nil, installedAgentIDs.count == 1,
           let only = installedAgentIDs.first { setDefaultAgent(only) }
    }

    /// Called only after the activity owner's current generation was published.
    func acceptActivity(taskResults latest: [String: String], undoOffer latestOffer: UndoOffer?) {
        if taskResults != latest { taskResults = latest }
        if undoOffer != latestOffer { undoOffer = latestOffer }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        invalidateGuards()
        reloadGeneration += 1
        reloadTask?.cancel()
        reloadWorker?.cancel()
        reloadTask = nil
        reloadWorker = nil
        stopWatching()
        installTask?.cancel()
        installTask = nil
        installQueue.removeAll()
        updateInstallTask?.cancel()
        updateInstallTask = nil
        updateCheckTask?.cancel()
        updateCheckGeneration += 1
        updateCheckTask = nil
        onNewCrashes = nil
        onUpdatesFound = nil
        onUpdateGlobalHotKeys = nil
        onMenuBarLabelChanged = nil
        activity = nil
    }

    /// macOS's own request: it adds Summon to Privacy & Security › Accessibility (switched off) and offers to open
    /// it, so the person only flips the switch. The page is opened too, in case the request was dismissed before.
    public func requestAccessibility() {
        // The key's value is "AXTrustedCheckOptionPrompt"; the global constant is not concurrency-safe in Swift 6.
        accessibilityRequested = true
        // Ad-hoc builds are trusted by cdhash: after an update the old switch stays on but no longer counts. Not
        // trusted means any entry for this bundle id is stale, so clear it and the prompt lists this build, off.
        if !AXIsProcessTrusted(), let id = Bundle.main.bundleIdentifier {
            _ = try? Shell.runSync("/usr/bin/tccutil", ["reset", "Accessibility", id])
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        guard !accessibilityGranted,
              let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Updates

    public func setChecksForUpdates(_ on: Bool) {
        do { try AutoUpdateStore(paths: paths).save(on) } catch { lastError = String(describing: error) }
        checksForUpdates = on
        if !on {
            availableUpdate = nil
            packageUpdates = []
            loadMenu()
        }
    }

    public func setUpdateChannel(_ channel: UpdateChannel) {
        guard !stopped else { return }
        do { try UpdateChannelStore(paths: paths).save(channel) } catch { lastError = String(describing: error) }
        updateChannel = channel
        updateCheckGeneration += 1
        let generation = updateCheckGeneration
        let previous = updateCheckTask
        previous?.cancel()
        updateCheckTask = Task { [weak self] in
            if let previous { await previous.value }
            guard !Task.isCancelled else { return }
            await self?.checkForUpdates()
            if self?.updateCheckGeneration == generation { self?.updateCheckTask = nil }
        }
    }

    /// Summon's channel and every package manager at once. `quiet` (the daily check) says nothing when Summon's
    /// check fails: offline or GitHub's rate limit is not worth a row.
    public func checkForUpdates(quiet: Bool = false) async {
        guard !stopped, !Task.isCancelled, !isUpdating, !isCheckingUpdates, installTask == nil else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        if !quiet { updateStatus = nil }
        async let packages = SoftwareUpdateCheck(runner: userPathRunner(runner), tools: ToolLocator.live()).run()
        var checkedUpdate = availableUpdate
        do {
            let check = try await Updater(runner: runner, gh: ToolLocator.live().find("gh")).check(updateChannel)
            checkedUpdate = check.available ? check : nil
        } catch {
            if !quiet, !stopped, !Task.isCancelled { updateStatus = String(describing: error) }
        }
        let checkedPackages = await packages
        guard !stopped, !Task.isCancelled else { return }
        if availableUpdate != checkedUpdate { availableUpdate = checkedUpdate }
        if packageUpdates != checkedPackages { packageUpdates = checkedPackages }
        updateStates = [:]
        lastUpdateCheck = Date()
        loadMenu()
        PanelTrace.log.notice("update check: summon \(self.availableUpdate?.release.version ?? "current", privacy: .public), \(self.packageUpdates.count, privacy: .public) packages")
        if updatePreferences.autoUpdateAgents { install(updates.filter { $0.group == .agents }) }
        if !pendingUpdates.isEmpty { onUpdatesFound?(pendingUpdates) }
    }

    /// A row's Update button: Summon installs and relaunches, macOS opens Software Update, the rest run their command.
    public func update(_ update: SoftwareUpdate) {
        switch update.source {
        case .summon: installUpdate()
        case .macOS: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")!)
        default: install([update])
        }
    }

    /// Queues each command-line update; they run one at a time (brew and npm take a lock), each row showing its state.
    public func install(_ list: [SoftwareUpdate]) {
        guard !stopped else { return }
        for update in list where update.command != nil {
            switch updateStates[update.id] {
            case .queued, .running, .done: continue
            default: break
            }
            updateStates[update.id] = .queued
            installQueue.append(update)
        }
        guard installTask == nil, !installQueue.isEmpty else { return }
        // Upgrades (a cask, a big formula) can take minutes.
        let run = userPathRunner(Shell.live(timeout: 1800))
        installTask = Task {
            while !installQueue.isEmpty, !Task.isCancelled, !stopped {
                let update = installQueue.removeFirst()
                guard let command = update.command, let tool = command.first else { continue }
                updateStates[update.id] = .running
                do {
                    _ = try await run(tool, Array(command.dropFirst()))
                    guard !Task.isCancelled, !stopped else { return }
                    updateStates[update.id] = .done
                } catch RunnerError.failed(_, _, let output) {
                    guard !Task.isCancelled, !stopped else { return }
                    updateStates[update.id] = .failed(output)
                } catch {
                    guard !Task.isCancelled, !stopped else { return }
                    updateStates[update.id] = .failed(String(describing: error))
                }
                loadMenu()
            }
            installTask = nil
        }
    }

    /// For a failure that needs a password: the same command in the default terminal, where sudo can ask.
    public func openInTerminal(_ update: SoftwareUpdate) {
        guard let command = update.command else { return }
        let argv = terminal == .terminal ? command : AgentLauncher.inLoginShell(command, shell: ProcessInfo.processInfo.environment["SHELL"])
        let plan = AgentLauncher.terminalPlan(agentArgv: argv, directory: NSHomeDirectory(), terminal: terminal)
        Task {
            do { _ = try await runner(plan.executable, plan.arguments) } catch { lastError = "Open in Terminal: \(error)" }
        }
    }

    /// A failed row's Fix with AI: the agent gets the command and its output.
    public func fixWithAI(_ update: SoftwareUpdate) {
        guard case .failed(let output) = updateStates[update.id] else { return }
        askAgent(prompt: update.fixPrompt(output: output))
    }

    public func skip(_ update: SoftwareUpdate) {
        changeUpdatePreferences { $0.skipped[update.id] = update.latest }
    }

    public func setUpdateGroup(_ group: SoftwareUpdate.Group, on: Bool) {
        changeUpdatePreferences { if on { $0.off.remove(group.rawValue) } else { $0.off.insert(group.rawValue) } }
    }

    public func setAutoUpdateAgents(_ on: Bool) {
        changeUpdatePreferences { $0.autoUpdateAgents = on }
    }

    private func changeUpdatePreferences(_ change: (inout UpdatePreferences) -> Void) {
        change(&updatePreferences)
        do { try UpdatePreferencesStore(paths: paths).save(updatePreferences) } catch { lastError = String(describing: error) }
        loadMenu()
    }

    /// Package managers need the user's PATH from a GUI app (npm starts with `env node`). The argv is passed as
    /// "$@", never spliced into the shell string.
    private func userPathRunner(_ base: @escaping Runner) -> Runner {
        let prefix = shellPrefix
        return { tool, arguments in try await base("/bin/zsh", ["-c", prefix + "\"$@\"", "zsh", tool] + arguments) }
    }

    /// The same install as `summon update` (checksum, staged installer with rollback), then Summon relaunches.
    public func installUpdate() {
        guard !stopped, let release = availableUpdate?.release, !isUpdating else { return }
        isUpdating = true
        updateStatus = "Installing Summon \(release.version)…"
        let updater = Updater(runner: Shell.live(timeout: 900))
        updateInstallTask = Task { [weak self] in
            do {
                _ = try await updater.install(release)
                guard !Task.isCancelled, let self, !self.stopped else { return }
                self.updateInstallTask = nil
                self.relaunchInstalledApp()
            } catch {
                guard !Task.isCancelled, let self, !self.stopped else { return }
                self.updateInstallTask = nil
                self.isUpdating = false
                self.updateStatus = "Update failed: \(error)"
            }
        }
    }

    /// Opens the new ~/Applications/Summon.app once this process has quit. `--updated` asks for Accessibility again:
    /// macOS trusts an ad-hoc build by its hash, so the new build starts without it.
    private func relaunchInstalledApp() {
        let app = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/Summon.app").path
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\" --args --updated",
                            "sh", String(ProcessInfo.processInfo.processIdentifier), app]
        do { try waiter.run() } catch {
            isUpdating = false
            updateStatus = "Installed. Quit and open Summon to finish."
            return
        }
        NSApp.terminate(nil)
    }

    public func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Asks first (the undo restores settings and ~/.config files), then runs `summon checkpoint undo <id>`.
    public func confirmUndo(_ offer: UndoOffer) {
        NSApp.activate()
        let alert = NSAlert()
        let changes = "\(offer.changes) Change\(offer.changes == 1 ? "" : "s")"
        alert.messageText = "Undo \(offer.label)?"
        alert.informativeText = "Restores the settings and ~/.config files from before it and removes the files it created. Other new files stay."
        // The button names what it does; Cancel is the default (Return), so a stray keypress restores nothing.
        let restore = alert.addButton(withTitle: "Restore \(changes)")
        restore.hasDestructiveAction = true
        restore.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await summon(["checkpoint", "undo", offer.checkpoint]) }
    }

    func loadMenu() {
        let updated = baseMenu.withProjects(projects, themes: themes, appHealth: appHealth, themeHealth: themeHealth)
            .withUpdates(count: pendingUpdates.count)
        if menu != updated {
            menu = updated
            menuRevision += 1
        }
    }

    // MARK: Crash watching

    @ObservationIgnored private var lastMac: MacContext?
    @ObservationIgnored private var macCheck: Task<Void, Never>?
    @ObservationIgnored private var macProbe: Task<MacContext, Never>?
    @ObservationIgnored private var macAppend: Task<[String], Never>?

    /// Probe and append on utility workers; the event lease must never block the UI actor.
    func checkMac() {
        guard macCheck == nil else { return }
        let paths = paths
        let probe = Task.detached(priority: .utility) { MacContextProbe.vitals(paths: paths) }
        macProbe = probe
        macCheck = Task { [weak self] in
            let snapshot = await probe.value
            guard !Task.isCancelled, let self else { return }
            let changes = MacEvents.changes(from: self.lastMac, to: snapshot)
            let append = Task.detached(priority: .utility) { () -> [String] in
                var errors: [String] = []
                for event in changes {
                    guard !Task.isCancelled else { return errors }
                    do {
                        let receipt = try EventLog(paths: paths).append(event)
                        if let failure = receipt.maintenanceFailure { errors.append(failure) }
                    } catch {
                        errors.append(String(describing: error))
                    }
                }
                return errors
            }
            self.macAppend = append
            let errors = await append.value
            guard !Task.isCancelled else { return }
            if let error = errors.first { self.lastError = "Mac status event could not be saved: \(error)" }
            self.lastMac = snapshot
            self.macProbe = nil
            self.macAppend = nil
            self.macCheck = nil
        }
    }

    /// At launch, then a day after the last check.
    func updateCheckDue(now: Date = Date()) -> Bool {
        lastUpdateCheck.map { now.timeIntervalSince($0) >= 24 * 60 * 60 } ?? true
    }

    /// One slow loop for what has no notification: Mac vitals, a fallback crash scan, the doctor and updates.
    /// New crash reports arrive sooner through `crashFolders` (a folder watch).
    public func startWatching(interval: Duration = .seconds(60)) {
        guard !stopped, watchTask == nil else { return }
        // A new report is written in pieces: scan once the folder has been quiet for 3 s.
        crashFolders = paths.diagnosticReportDirs.compactMap { dir in
            FileWatch(dir) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.pendingCrashScan?.cancel()
                    self.pendingCrashScan = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(3), tolerance: .seconds(1))
                        if !Task.isCancelled { await self?.scanCrashes() }
                    }
                }
            }
        }
        watchTask = Task { [weak self] in
            var round = 0
            while !Task.isCancelled {
                await self?.watchRound(round)
                guard !Task.isCancelled else { return }
                round += 1
                // The slack lets macOS group this wakeup with others, without retaining the model.
                try? await Task.sleep(for: interval, tolerance: .seconds(10))
            }
        }
    }

    private func watchRound(_ round: Int) async {
        guard !Task.isCancelled else { return }
        // The folder watch finds new reports; this is also the fallback for a missing folder.
        if round % 5 == 0 || crashFolders.count < paths.diagnosticReportDirs.count {
            await scanCrashes()
        }
        guard !Task.isCancelled else { return }
        checkMac()
        if round % 30 == 0 { await checkHealth(full: round == 0) }
        guard !Task.isCancelled else { return }
        if checksForUpdates, updateCheckDue(), !ProcessInfo.processInfo.isLowPowerModeEnabled {
            await checkForUpdates(quiet: true)
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        crashFolders = []
        pendingCrashScan?.cancel()
        pendingCrashScan = nil
        crashRescanRequested = false
        crashScanGeneration += 1
        scanningCrashes = false
        macCheck?.cancel()
        macProbe?.cancel()
        macAppend?.cancel()
        macCheck = nil
        macProbe = nil
        macAppend = nil
    }

    func scanCrashes() async {
        if scanningCrashes { crashRescanRequested = true; return }
        scanningCrashes = true
        let expected = crashScanGeneration
        defer {
            if expected == crashScanGeneration {
                scanningCrashes = false
                if crashRescanRequested {
                    crashRescanRequested = false
                    Task { await scanCrashes() }
                }
            }
        }
        let watcher = CrashWatcher(paths: paths)
        var found: [CrashReport] = []
        defer { if expected == crashScanGeneration, !found.isEmpty { onNewCrashes?(found) } }
        do {
            var hasMore: Bool
            repeat {
                let previousKey = recentKey
                let result = try await Task.detached { () -> ([CrashReport]?, CrashWatcher.Batch, [String]) in
                    let key = watcher.reportCacheKey()
                    let recent = key == previousKey ? nil : watcher.reports(since: nil, limit: 10)
                    return (recent, try watcher.scanNewReports(limit: 5), key)
                }.value
                guard expected == crashScanGeneration else { return }
                if let recent = result.0, recentCrashes != recent {
                    recentCrashes = recent
                    activity?.markDirty()
                    reloadProjects()
                }
                recentKey = result.2
                if crashCaptureEnabled { found += result.1.reports }
                guard !Task.isCancelled else { return }
                hasMore = result.1.hasMore
                if hasMore { await Task.yield() }
            } while hasMore && !Task.isCancelled
        } catch {
            if !Task.isCancelled, expected == crashScanGeneration {
                lastError = "Could not scan diagnostic reports: \(error)"
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
        guard !stopped, let summonPath else {
            if !stopped { lastError = "The summon command is missing. Reinstall Summon." }
            return
        }
        do {
            _ = try await runner(summonPath, arguments)
            if !Task.isCancelled, !stopped { lastError = nil }
        } catch {
            if !Task.isCancelled, !stopped { lastError = String(describing: error) }
        }
        if !Task.isCancelled, !stopped { reload() }
    }

    /// The hotkey and the panel's Ask Agent: the agent starts with what is on screen as its first message.
    /// Captured before anything else runs, while the person's app is still in front (the panel never activates).
    public func askAgentAboutScreen() {
        let hidden = agentSettings.hiddenContext
        Task {
            let screen = await ScreenContext.capture(hidden: hidden, runner: runner)
            askAgent(prompt: screen.prompt())
        }
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

    /// `full: false` keeps the last `macctl` result (the periodic re-check); Settings and launch run everything.
    public func checkHealth(full: Bool = true) async {
        guard !stopped, !Task.isCancelled, !isCheckingHealth else { return }
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
        let report = await doctor.run(reuseMacctl: full ? nil : doctorReport?.check("macctl"))
        guard !stopped, !Task.isCancelled else { return }
        if report != doctorReport { doctorReport = report }
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

    /// Reconcile the project registry and health without blocking Settings or panel presentation.
    public func reloadProjects() { reload() }

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

    /// Diagnosing hands the report to the agent, so that program's reports are archived.
    public func diagnose(file: String) {
        if let program = recentCrashes.first(where: { $0.file == file })?.program {
            archiveProblems(recentCrashes.filter { $0.program == program })
        }
        Task { await summon(["crash", "diagnose", file]) }
    }

    public func archiveProblems(_ reports: [CrashReport]) {
        try? ProblemArchive(paths: paths).archive(reports.map(\.file))
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

    /// Shows or hides a `summon context` field from every agent.
    public func setContextField(_ field: ContextField, visible: Bool) {
        Task { await summon(AgentSettingsCommand.context(field, visible: visible)) }
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
        // Use the last valid menu for the first frame; disk refresh follows presentation.
        launcherStartLevel = level.flatMap { menu.item($0) == nil ? nil : $0 }
        requestedLauncherLevel = launcherStartLevel == nil ? level : nil
        launcherSession += 1
        reload()
    }

    /// Children of `parent` whose `when` guard did not fail.
    public func visibleChildren(of parent: String?) -> [MenuItem] {
        menu.children(of: parent).filter { visibility[$0.id] != false }
    }

    public func hasChildren(_ item: MenuItem) -> Bool {
        !menu.children(of: item.id).isEmpty
    }

    /// One generation owns both level and search checks; a cancelled command never becomes false.
    public func beginGuardEvaluation() -> Int {
        guardGeneration += 1
        return guardGeneration
    }

    public func invalidateGuards() { guardGeneration += 1 }

    public func evaluateGuards(_ items: [MenuItem], generation: Int) async {
        let prefix = shellPrefix
        for item in items {
            guard !Task.isCancelled, generation == guardGeneration else { return }
            if let command = item.when {
                guard let value = try? await succeeds(command, prefix: prefix),
                      !Task.isCancelled, generation == guardGeneration else { return }
                if visibility[item.id] != value { visibility[item.id] = value }
            }
            guard !Task.isCancelled, generation == guardGeneration else { return }
            if let command = item.checked {
                guard let value = try? await succeeds(command, prefix: prefix),
                      !Task.isCancelled, generation == guardGeneration else { return }
                if checks[item.id] != value { checks[item.id] = value }
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

    private func succeeds(_ command: String, prefix: String) async throws -> Bool {
        try Task.checkCancellation()
        do {
            _ = try await runner("/bin/zsh", ["-c", prefix + command])
            try Task.checkCancellation()
            return true
        } catch {
            try Task.checkCancellation()
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

/// No AppKit or permission reads here. Collection is intentionally independent of the UI actor;
/// even a discarded generation must never mutate observable state.
private struct SummonDiskSnapshot: Sendable {
    let defaultAgent: Agent?
    let repoPolicy: RepoPolicy
    let updateChannel: UpdateChannel
    let checksForUpdates: Bool
    let updatePreferences: UpdatePreferences
    let executionMode: AgentExecutionMode?
    let installedAgentIDs: [String]
    let themes: [Theme]
    let currentThemeSlug: String?
    let tasks: [RecurringTask]?
    let installedTerminals: [TerminalApp]
    let terminal: TerminalApp
    let mutedPrograms: [String]
    let agentSettings: AgentSettings?
    let projects: [Project]?
    let appHealth: [String: ItemHealth]
    let themeHealth: [String: ItemHealth]
    let artJobs: [ArtJob]
    let artJobHealth: [String: ItemHealth]
    let menu: MenuTree
    let menuError: String?
    let errors: [String]

    static func collect(paths: SummonPaths, crashes: [CrashReport]) -> Self {
        var errors: [String] = []
        let mode: AgentExecutionMode?
        do { mode = try ExecutionPolicyStore(paths: paths).load() }
        catch { mode = nil; errors.append("Execution mode: \(error)") }
        let tasks: [RecurringTask]?
        do { tasks = try TaskStore(paths: paths).loadValidated() }
        catch { tasks = nil; errors.append("Tasks: \(error)") }
        let settings: AgentSettings?
        do { settings = try AgentSettingsStore(paths: paths).loadValidated() }
        catch { settings = nil; errors.append("Agent settings: \(error)") }
        let projects: [Project]?
        do { projects = try ProjectStore(paths: paths).load().projects }
        catch { projects = nil; errors.append("Projects: \(error)") }

        let themeStore = ThemeStore(paths: paths)
        let themes = themeStore.all()
        var appHealth: [String: ItemHealth] = [:]
        for project in projects ?? [] where !Task.isCancelled {
            appHealth[project.name] = AppHealthChecker.check(project: project, recentCrashes: crashes)
        }
        var themeHealth: [String: ItemHealth] = [:]
        for theme in themes where !Task.isCancelled {
            themeHealth[theme.slug] = AppHealthChecker.check(theme: theme, themesFolder: paths.themes)
        }
        let artJobs = Task.isCancelled ? [] : AppHealthChecker.scanArtJobs(artFolder: paths.art)
        var artJobHealth: [String: ItemHealth] = [:]
        for job in artJobs where !Task.isCancelled {
            artJobHealth[job.name] = AppHealthChecker.check(artJob: job)
        }
        let locator = ToolLocator.live()
        let installedAgentIDs = AgentRegistry.all.filter { locator.find($0.command) != nil }.map(\.id)
        let installedTerminals = TerminalApp.installed
        let menu = MenuTree.load(from: paths.menuFile)
        return Self(defaultAgent: DefaultAgentStore(paths: paths).load(), repoPolicy: RepoPolicyStore(paths: paths).load(),
                    updateChannel: UpdateChannelStore(paths: paths).load(),
                    checksForUpdates: AutoUpdateStore(paths: paths).load(),
                    updatePreferences: UpdatePreferencesStore(paths: paths).load(), executionMode: mode,
                    installedAgentIDs: installedAgentIDs, themes: themes, currentThemeSlug: themeStore.currentSlug(),
                    tasks: tasks, installedTerminals: TerminalApp.allCases.filter { installedTerminals.contains($0) },
                    terminal: AgentLauncher.preferredTerminal(saved: DefaultTerminalStore(paths: paths).load(),
                                                               installed: installedTerminals),
                    mutedPrograms: CrashWatcher(paths: paths).muted().sorted(), agentSettings: settings,
                    projects: projects, appHealth: appHealth, themeHealth: themeHealth,
                    artJobs: artJobs, artJobHealth: artJobHealth, menu: menu.tree, menuError: menu.problem, errors: errors)
    }
}

extension SummonModel {
    /// A model with sample data for previews; it never runs commands.
    /// The Updates window's preview: one of each group and every row state.
    public static func previewUpdates() -> SummonModel {
        let model = preview()
        model.packageUpdates = [
            SoftwareUpdate(source: .agent, name: "Codex", current: "0.158.0", latest: "0.164.0", command: ["bun"]),
            SoftwareUpdate(source: .agent, name: "OpenCode", current: "1.17.11", latest: "1.19.4", command: ["bun"]),
            SoftwareUpdate(source: .homebrew, name: "btop", current: "1.4.7", latest: "1.4.8", command: ["brew"]),
            SoftwareUpdate(source: .homebrew, name: "omniwm", current: "0.7.1", latest: "0.7.6", command: ["brew"]),
            SoftwareUpdate(source: .npm, name: "npm", current: "11.19.1", latest: "12.2.1", command: ["npm"]),
            SoftwareUpdate(source: .macOS, name: "macOS Tahoe 26.1", current: "", latest: "26.1", command: nil),
        ]
        model.updateStates = ["agent:Codex": .running, "agent:OpenCode": .done,
                              "homebrew:omniwm": .failed("Error: sudo: a terminal is required to read the password")]
        model.lastUpdateCheck = Date().addingTimeInterval(-120)
        return model
    }

    public static func preview() -> SummonModel {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("summon-preview", isDirectory: true)
        let model = SummonModel(paths: SummonPaths(home: home), runner: { _, _ in "" }, live: false)
        model.recentCrashes = [
            CrashReport(
                file: "/tmp/Example-2026-10-17-101500.ips", kind: .crash, bugType: "309", appName: "Example",
                appVersion: "1.2", timestamp: "2026-10-17 10:15:00.00 +0000", incidentID: nil, osVersion: "macOS 26.0",
                process: "Example", pid: 4242, exceptionType: "EXC_BAD_ACCESS", signal: "SIGSEGV", topFrames: []
            ),
        ]
        model.defaultAgent = AgentRegistry.find("claude")
        model.agentInstalled = true
        model.installedAgentIDs = ["claude", "codex", "opencode"]
        model.agentStatus = ["claude": AgentStatus(login: AgentLogin(loggedIn: true, detail: "Claude Max"), models: []),
                             "codex": AgentStatus(login: AgentLogin(loggedIn: false), models: [])]
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
