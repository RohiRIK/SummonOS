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

    /// Set by the app delegate to post a notification for each new report.
    @ObservationIgnored public var onNewCrash: ((CrashReport) -> Void)? = nil
    @ObservationIgnored private var recentKey: [String] = []
    @ObservationIgnored private var watchTask: Task<Void, Never>? = nil

    static let crashCaptureKey = "crashCaptureEnabled"

    public init(paths: SummonPaths = .live, runner: @escaping Runner = Shell.live) {
        self.paths = paths
        self.runner = runner
        self.menu = MenuTree.standard
        self.crashCaptureEnabled = UserDefaults.standard.object(forKey: Self.crashCaptureKey) as? Bool ?? true
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
        loadMenu()
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
        return model
    }
}
