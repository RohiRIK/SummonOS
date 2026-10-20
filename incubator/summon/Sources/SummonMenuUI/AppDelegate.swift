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

    static let crashCategory = "summon.crash"
    static let diagnoseAction = "summon.crash.diagnose"
    static let muteAction = "summon.crash.mute"

    /// `summon://` URLs that arrived before the panel existed; replayed at the end of applicationDidFinishLaunching.
    private var pendingURLs: [URL] = []

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Every project lives in ~/Summon and agents start there, so it exists from the first launch.
        try? ProjectsFolder.ensure(.live)
        let activity = self.activity
        let model = self.model
        let panel = PanelController(openSettings: { activity.requestSettings() },
                                    prepare: { model.prepareLauncher(startAt: $0) }) { state, actions in
            PanelView(model: model, activity: activity, panel: state, actions: actions)
        }
        self.panel = panel
        // ⌃⌥Space toggles the panel (the launcher merged into it, decision 4). Releases let a held key open once (C3).
        let menuOK = HotKeyCenter.shared.register(id: SummonHotKey.menuID, keyCode: SummonHotKey.menuKey,
                                                  modifiers: SummonHotKey.menuModifiers,
                                                  onRelease: { [weak panel] in panel?.hotKeyReleased() }) { [weak panel] in
            panel?.hotKeyPressed()
        }
        let agentOK = HotKeyCenter.shared.register(id: SummonHotKey.agentID, keyCode: SummonHotKey.agentKey, modifiers: SummonHotKey.agentModifiers) { [weak self] in
            self?.model.askAgent()
        }
        // Another app may own the combination; say so instead of failing silently.
        let taken = [menuOK ? nil : "⌃⌥Space", agentOK ? nil : "⌃⌥⌘A"].compactMap { $0 }
        model.unavailableHotKeys = Set(taken)
        if !taken.isEmpty {
            model.lastError = "Shortcut \(taken.joined(separator: " and ")) is taken by another app."
        }
        // `summon doctor` reads this to report whether the app runs and its shortcuts registered.
        let health = AppHealth(pid: ProcessInfo.processInfo.processIdentifier,
                               hotkeys: ["⌃⌥Space": menuOK, "⌃⌥⌘A": agentOK])
        try? AppHealthStore(paths: model.paths).save(health)
        setUpNotifications(health: health)
        crashAlert.onWillPresent = { [weak panel] in panel?.yieldToCrashAlert() }
        // A `summon://` URL that launched Summon can arrive before this method ran (Sam's review); replay it now,
        // after the status item has had a pass to get its place in the menu bar so the panel opens under it.
        let queued = pendingURLs
        pendingURLs = []
        if !queued.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.application(NSApp, open: queued) }
        }
        model.onNewCrash = { [weak self] report in
            self?.notify(report)
            self?.crashAlert.present(report)
        }
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
        guard panel != nil else {
            pendingURLs += urls
            return
        }
        for url in urls where url.scheme == "summon" {
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
                activity.requestSettings()
            #if DEBUG
            case "test-crash":
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
                crashAlert.present(sample)
            #endif
            default:
                break
            }
        }
    }

    // MARK: Notifications

    /// UNUserNotificationCenter raises an exception outside an .app bundle (`swift run SummonMenu`).
    private var canNotify: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private func setUpNotifications(health: AppHealth) {
        guard canNotify else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let diagnose = UNNotificationAction(identifier: Self.diagnoseAction, title: "Diagnose", options: [])
        let mute = UNNotificationAction(identifier: Self.muteAction, title: "Mute This App", options: [])
        let category = UNNotificationCategory(identifier: Self.crashCategory, actions: [diagnose, mute], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
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

    private func notify(_ report: CrashReport) {
        // A process over its own memory cap, or stopped while idle, is normal macOS life: listed, not announced.
        guard canNotify, !report.isRoutine else { return }
        let content = UNMutableNotificationContent()
        switch report.kind {
        case .crash: content.title = "\(report.program) crashed"
        case .hang: content.title = "\(report.program) stopped responding"
        case .panic: content.title = "Your Mac restarted after a problem"
        case .memory: content.title = report.process == nil ? "Your Mac ran low on memory" : "macOS stopped \(report.program)"
        case .other: content.title = "\(report.program) wrote a diagnostic report"
        }
        content.body = "Click Diagnose to hand it to your agent."
        content.categoryIdentifier = Self.crashCategory
        content.userInfo = ["file": report.file, "program": report.program]
        let request = UNNotificationRequest(identifier: report.file, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let file = info["file"] as? String
        let program = info["program"] as? String
        completionHandler()
        Task { @MainActor in
            self.handle(action: action, file: file, program: program)
        }
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func handle(action: String, file: String?, program: String?) {
        switch action {
        case Self.muteAction:
            if let program { model.mute(program: program) }
        case Self.diagnoseAction, UNNotificationDefaultActionIdentifier:
            // Clicking the notification itself also diagnoses, like Omarchy's "Process crashed" toast.
            if let file { model.diagnose(file: file) }
        default:
            break
        }
    }
}
