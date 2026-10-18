import AppKit
import SummonCore
import UserNotifications

/// Owns everything that outlives a view: hotkeys, the launcher, the crash watcher, notifications, `summon://` URLs.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    public let model = SummonModel()
    public private(set) lazy var launcher = LauncherController(model: model)
    public private(set) lazy var activity = ActivityModel(summon: model)

    static let crashCategory = "summon.crash"
    static let diagnoseAction = "summon.crash.diagnose"
    static let muteAction = "summon.crash.mute"

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Every project lives in ~/Summon and agents start there, so it exists from the first launch.
        try? ProjectsFolder.ensure(.live)
        let menuOK = HotKeyCenter.shared.register(id: SummonHotKey.menuID, keyCode: SummonHotKey.menuKey, modifiers: SummonHotKey.menuModifiers) { [weak self] in
            self?.launcher.toggle()
        }
        let agentOK = HotKeyCenter.shared.register(id: SummonHotKey.agentID, keyCode: SummonHotKey.agentKey, modifiers: SummonHotKey.agentModifiers) { [weak self] in
            self?.model.askAgent()
        }
        // Another app may own the combination; say so instead of failing silently.
        let taken = [menuOK ? nil : "⌃⌥Space", agentOK ? nil : "⌃⌥⌘A"].compactMap { $0 }
        if !taken.isEmpty {
            model.lastError = "Shortcut \(taken.joined(separator: " and ")) is taken by another app."
        }
        // `summon doctor` reads this to report whether the app runs and its shortcuts registered.
        let health = AppHealth(pid: ProcessInfo.processInfo.processIdentifier,
                               hotkeys: ["⌃⌥Space": menuOK, "⌃⌥⌘A": agentOK])
        try? AppHealthStore(paths: model.paths).save(health)
        setUpNotifications(health: health)
        model.onNewCrash = { [weak self] report in
            self?.notify(report)
        }
        model.startWatching()
        // Every launch relinks the shipped skills, so an updated or moved app still reaches every agent.
        Task { await model.summon(["skills", "link", "--quiet"]) }
    }

    /// `summon://menu/<id>` opens the launcher at that entry; `summon://agent` starts the agent;
    /// `summon://activity` opens the Activity window; `summon://settings` opens Settings.
    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "summon" {
            switch url.host {
            case "menu":
                let id = url.pathComponents.dropFirst().first
                launcher.show(startAt: id)
            case "agent":
                model.askAgent()
            case "activity":
                activity.requestOpen()
            case "settings":
                activity.requestSettings()
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
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        switch report.kind {
        case .crash: content.title = "\(report.program) crashed"
        case .hang: content.title = "\(report.program) stopped responding"
        case .panic: content.title = "Your Mac restarted after a problem"
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
