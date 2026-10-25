import AppKit
import SummonCore
import UserNotifications

/// Owns everything that outlives a view: hotkeys, the menu bar panel, the crash watcher, notifications, `summon://` URLs.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public let model = SummonModel()
    public private(set) lazy var activity = ActivityModel(summon: model)
    public private(set) lazy var crashAlert = CrashAlertController(model: model)
    /// The menu bar status item and its panel (replaces MenuBarExtra). Created at launch.
    public private(set) var panel: PanelController?
    /// Keeps the status item's label live (a running agent's elapsed time).
    private var menuBarStatus: MenuBarStatusWatcher?

    static let crashCategory = "summon.crash"
    static let diagnoseAction = "summon.crash.diagnose"
    static let muteAction = "summon.crash.mute"
    static let taskCategory = "summon.task"
    static let showLogAction = "summon.task.log"
    static let askAction = "summon.task.ask"

    /// `summon://` URLs that arrived before the panel existed; replayed at the end of applicationDidFinishLaunching.
    private var launchURLs = LaunchURLQueue()

    public override init() {
        super.init()
    }

    /// summon:// URLs come in as a kAEGetURL Apple event. Handling it here, before AppKit finishes launching, keeps
    /// SwiftUI from also routing it to a scene (which showed the Activity window), and still works on cold launch.
    public func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        application(NSApp, open: [url])
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Every project lives in ~/Summon and agents start there, so it exists from the first launch.
        try? ProjectsFolder.ensure(.live)
        let activity = self.activity
        let model = self.model
        let panel = PanelController(openActivity: { activity.requestOpen() },
                                    openSettings: { activity.requestSettings() },
                                    prepare: { model.prepareLauncher(startAt: $0) }) { state, actions in
            PanelView(model: model, activity: activity, panel: state, actions: actions)
        }
        self.panel = panel
        let menuBarStatus = MenuBarStatusWatcher(model: model) { [weak panel] title, label, attention in
            panel?.setStatusLabel(title: title, accessibilityLabel: label, attention: attention)
        }
        self.menuBarStatus = menuBarStatus
        model.onMenuBarLabelChanged = { [weak menuBarStatus] in menuBarStatus?.redraw() }
        menuBarStatus.onNewEvents = { [weak self] events in self?.announce(events) }
        menuBarStatus.start()
        let health = registerHotKeys() ?? AppHealth(pid: ProcessInfo.processInfo.processIdentifier, hotkeys: [:])
        model.onUpdateGlobalHotKeys = { [weak self] in
            self?.registerHotKeys()
        }
        setUpNotifications(health: health)
        crashAlert.onWillPresent = { [weak panel] in panel?.yieldToCrashAlert() }
        // A `summon://` URL that launched Summon can arrive before this method ran (Sam's review); replay it now,
        // after the status item has had a pass to get its place in the menu bar so the panel opens under it.
        let queued = launchURLs.markReady()
        if !queued.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.application(NSApp, open: queued) }
        }
        model.onNewCrashes = { [weak self] reports in self?.announce(reports) }
        model.startWatching()
        // Every launch relinks the shipped skills, so an updated or moved app still reaches every agent.
        Task {
            await model.summon(["skills", "link", "--quiet"])
            await model.summon(["home", "--quiet"])
            // Once a day: old Summon files to the Trash (summon clean shows what and why).
            await model.summon(["clean", "--apply", "--if-due", "--quiet"])
        }
    }

    /// `summon://panel` opens the menu bar panel and `summon://panel/close` closes it (use `open -g`);
    /// `summon://menu/<id>` opens the panel at that Summon Menu entry; `summon://agent` starts the agent;
    /// `summon://activity` opens the Activity window; `summon://settings` opens Settings.
    public func application(_ application: NSApplication, open urls: [URL]) {
        // Cold launch: AppKit can deliver the URL before applicationDidFinishLaunching made the panel. Queue it.
        for url in launchURLs.receive(urls) where url.scheme == "summon" {
            if let route = PanelRoute.parse(host: url.host, pathComponents: url.pathComponents) {
                if route == .open { panel?.open() } else { panel?.close() }
                continue
            }
            switch url.host {
            case "menu":
                let id = url.pathComponents.dropFirst().first
                panel?.open(at: id)
            case "agent":
                model.askAgent()
            case "activity":
                activity.requestOpen()
            case "settings":
                // summon://settings/<section> opens on that page (Visual QA captures each one this way).
                if let name = url.pathComponents.dropFirst().first, let section = SettingsSection(rawValue: name) {
                    model.requestedSettingsSection = section
                }
                activity.requestSettings()
            // A sample crash alert: debug builds, or a Visual QA runner that set the `VisualQA` default.
            case "test-crash" where Self.allowsTestCrash:
                let sample = CrashReport(
                    file: "/Library/Logs/DiagnosticReports/Ghostty-2026-10-20-100700.ips",
                    kind: .crash,
                    bugType: "309",
                    appName: "Ghostty",
                    appVersion: "1.1.2",
                    timestamp: "2026-10-20 10:07:00.00 +0300",
                    incidentID: UUID().uuidString,
                    osVersion: "macOS 26.0 (26A425)",
                    process: "Ghostty",
                    pid: 48192,
                    exceptionType: "EXC_BAD_ACCESS",
                    signal: "SIGSEGV",
                    topFrames: ["0   libsystem_kernel.dylib   0x000000018a14b534 __pthread_kill + 8", "1   GhosttyApp               0x00000001048b2910 main + 420"]
                )
                // Through the same path as a real report, so it follows Settings › Notifications.
                announce([sample])
            default:
                break
            }
        }
    }

    static var allowsTestCrash: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: "VisualQA")
        #endif
    }

    // MARK: Notifications

    /// UNUserNotificationCenter raises an exception outside an .app bundle (`swift run SummonMenu`).
    private var canNotify: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    @discardableResult
    func registerHotKeys() -> AppHealth? {
        guard let panel = self.panel else { return nil }
        let menuShortcut = model.globalMenuShortcut
        let agentShortcut = model.globalAgentShortcut

        let menuOK = HotKeyCenter.shared.register(
            id: SummonHotKey.menuID,
            keyCode: menuShortcut.keyCode,
            modifiers: menuShortcut.carbonModifiers,
            onRelease: { [weak panel] in panel?.hotKeyReleased() }
        ) { [weak panel] in
            panel?.hotKeyPressed()
        }

        let agentOK = HotKeyCenter.shared.register(
            id: SummonHotKey.agentID,
            keyCode: agentShortcut.keyCode,
            modifiers: agentShortcut.carbonModifiers
        ) { [weak self] in
            self?.model.askAgentAboutScreen()
        }

        let taken = [
            menuOK ? nil : menuShortcut.displayString,
            agentOK ? nil : agentShortcut.displayString
        ].compactMap { $0 }
        model.unavailableHotKeys = Set(taken)
        if !taken.isEmpty {
            model.lastError = "Shortcut \(taken.joined(separator: " and ")) is taken by another app."
        }

        let existing = AppHealthStore(paths: model.paths).load()
        let health = AppHealth(
            pid: ProcessInfo.processInfo.processIdentifier,
            hotkeys: [menuShortcut.displayString: menuOK, agentShortcut.displayString: agentOK],
            notifications: existing?.notifications
        )
        try? AppHealthStore(paths: model.paths).save(health)
        return health
    }

    private func setUpNotifications(health: AppHealth) {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let diagnose = UNNotificationAction(identifier: Self.diagnoseAction, title: "Diagnose with AI", options: [])
        let mute = UNNotificationAction(identifier: Self.muteAction, title: "Mute This App", options: [])
        let crash = UNNotificationCategory(identifier: Self.crashCategory, actions: [diagnose, mute], intentIdentifiers: [], options: [])
        let showLog = UNNotificationAction(identifier: Self.showLogAction, title: "Show Log", options: [])
        let ask = UNNotificationAction(identifier: Self.askAction, title: "Ask Agent", options: [])
        let task = UNNotificationCategory(identifier: Self.taskCategory, actions: [showLog, ask], intentIdentifiers: [], options: [])
        center.setNotificationCategories([crash, task])
        let store = AppHealthStore(paths: model.paths)
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                var updated = health
                updated.notifications = AppDelegate.describe(settings.authorizationStatus)
                try? store.save(updated)
            }
        }
    }

    nonisolated static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .provisional: return "provisional"
        default: return "unknown"
        }
    }

    /// One scan's new reports: Summon's alert or banners, per Settings › Notifications, never both.
    private func announce(_ reports: [CrashReport]) {
        let plan = CrashAnnouncementPlan.make(reports, style: model.crashAlertStyle, canPostBanners: canNotify)
        if let report = plan.alert { crashAlert.present(report, alsoNew: plan.alsoNew) }
        for report in plan.banners { postBanner(report) }
    }

    private func postBanner(_ report: CrashReport) {
        let content = UNMutableNotificationContent()
        switch report.kind {
        case .crash: content.title = "\(report.program) crashed"
        case .hang: content.title = "\(report.program) stopped responding"
        case .panic: content.title = "Your Mac restarted after a problem"
        case .memory: content.title = report.process == nil ? "Your Mac ran low on memory" : "macOS stopped \(report.program)"
        case .other: content.title = "\(report.program) wrote a diagnostic report"
        }
        let what = [report.exceptionType, report.signal].compactMap { $0 }.joined(separator: " · ")
        content.body = (what.isEmpty ? "" : what + ". ") + "Click to have your agent find out why."
        content.categoryIdentifier = Self.crashCategory
        // Notification Center groups a program's reports together.
        content.threadIdentifier = "summon.crash." + CrashWatcher.muteKey(report.program)
        content.userInfo = ["file": report.file, "program": report.program]
        if model.notificationSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: report.file, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Task results the CLI logged while this app runs (the CLI posts nothing itself then).
    private func announce(_ events: [LoggedEvent]) {
        guard canNotify, model.taskNotificationsEnabled else { return }
        for announcement in EventAnnouncer.announcements(in: events, after: .distantPast) {
            let content = UNMutableNotificationContent()
            content.title = announcement.title
            content.body = announcement.body
            content.categoryIdentifier = Self.taskCategory
            content.threadIdentifier = announcement.thread
            var info = ["title": announcement.title, "category": announcement.category.rawValue]
            info["log"] = announcement.logFile
            info["task"] = announcement.taskID
            content.userInfo = info
            if model.notificationSound && announcement.category == .taskFailed { content.sound = .default }
            let request = UNNotificationRequest(identifier: announcement.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let info = response.notification.request.content.userInfo
        var strings: [String: String] = [:]
        for (key, value) in info { if let key = key as? String, let value = value as? String { strings[key] = value } }
        completionHandler()
        Task { @MainActor in
            self.handle(action: action, category: category, info: strings)
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func handle(action: String, category: String, info: [String: String]) {
        if category == Self.taskCategory {
            handleTask(action: action, info: info)
            return
        }
        switch action {
        case Self.muteAction:
            if let program = info["program"] { model.mute(program: program) }
        case Self.diagnoseAction, UNNotificationDefaultActionIdentifier:
            // Clicking the banner itself also diagnoses: that is what the banner offers.
            if let file = info["file"] { model.diagnose(file: file) }
        default:
            break
        }
    }

    private func handleTask(action: String, info: [String: String]) {
        switch action {
        case Self.showLogAction:
            if let log = info["log"], FileManager.default.fileExists(atPath: log) {
                NSWorkspace.shared.open(URL(fileURLWithPath: log))
            } else {
                activity.requestOpen()
            }
        case Self.askAction:
            let announcement = EventAnnouncement(
                id: "", category: EventAnnouncement.Category(rawValue: info["category"] ?? "") ?? .taskDone,
                title: info["title"] ?? "Scheduled task", body: "", thread: "", logFile: info["log"], taskID: info["task"])
            model.askAgent(prompt: EventAnnouncer.askPrompt(announcement))
        case UNNotificationDefaultActionIdentifier:
            activity.requestOpen()
        default:
            break
        }
    }
}
