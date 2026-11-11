import AppKit
import Foundation
import Observation
import SummonCore
import SwiftUI

private struct ActivityRead: Sendable {
    let sources: ActivitySources
    let events: [ActivityEvent]
    let status: SummonStatus
    let results: [String: String]
    let undoOffer: UndoOffer?
    let agent: Agent?
    let agentInstalled: Bool
    let macctlInstalled: Bool
    let macctlProblems: [String]
}

private enum ActivityReadResult: Sendable {
    case success(ActivityRead)
    case failure(String)
}

/// State for the Activity window and the panel's Recent Activity rows: the merged timeline, the status
/// strip, the filter, and the undo actions. Crash reports come from `SummonModel`'s watcher, never re-parsed.
@MainActor
@Observable
public final class ActivityModel {
    public enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case settings = "Settings"
        case agent = "Agent"
        case checkpoints = "Checkpoints"
        case problems = "Problems"

        public var id: String { rawValue }

        func matches(_ category: ActivityEvent.Category) -> Bool {
            switch self {
            case .all: return true
            case .settings: return category == .settings || category == .theme
            case .agent: return category == .agent
            case .checkpoints: return category == .checkpoint
            case .problems: return category == .problem
            }
        }
    }

    let summon: SummonModel
    let runner: Runner

    public private(set) var sources = ActivitySources()
    public private(set) var events: [ActivityEvent] = []
    public private(set) var status: SummonStatus? = nil
    /// Observable acknowledgement of a completed shared source publication.
    public private(set) var lastPublishedGeneration = 0
    public private(set) var macctlProblems: [String] = []
    public private(set) var macctlPath: String? = nil
    /// The last undo or doctor failure, shown above the timeline.
    public var lastError: String? = nil
    /// An undo is running; the buttons are disabled meanwhile.
    public private(set) var busy = false

    public var filter: Filter = .all
    public var query = ""
    public var selection: ActivityEvent.ID? = nil
    /// Bumped to ask the always-alive menu bar label to open the window (for `summon://activity`).
    public private(set) var openRequest = 0
    /// Bumped by `summon://settings`; the menu bar label opens the Settings window.
    public private(set) var settingsRequest = 0
    /// Bumped by `summon://welcome`; the opener shows the first-run setup window again.
    public private(set) var onboardingRequest = 0
    /// Bumped by the panel's Update row and tag, and the updates notification; the opener shows the Updates window.
    public private(set) var updatesRequest = 0

    /// False for previews: no disk reads, commands or activation-policy changes.
    @ObservationIgnored public internal(set) var live = true
    public enum Interest: Hashable { case panel, window }
    @ObservationIgnored private var interests: Set<Interest> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var doctorTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<ActivityReadResult, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var publishedGeneration = 0
    @ObservationIgnored private var dirty = true
    @ObservationIgnored private var nextReconcile = Date()
    @ObservationIgnored private var watches: [URL: FileWatch] = [:]
    private let bell = Doorbell()
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var activityReadError: String?

    public init(summon: SummonModel, runner: @escaping Runner = Shell.live) {
        self.summon = summon
        self.runner = runner
    }

    // MARK: Derived

    public var visibleEvents: [ActivityEvent] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return events.filter { event in
            guard filter.matches(event.category) else { return false }
            guard !needle.isEmpty else { return true }
            let haystack = ([event.title, event.detail ?? ""] + event.changes.map(\.id)).joined(separator: " ").lowercased()
            return haystack.contains(needle)
        }
    }

    public struct DayGroup: Identifiable {
        public let day: Date
        public var events: [ActivityEvent]
        public var id: Date { day }
    }

    /// Visible events grouped by calendar day, newest day first.
    public var days: [DayGroup] {
        let calendar = Calendar.current
        var groups: [DayGroup] = []
        for event in visibleEvents {
            let day = calendar.startOfDay(for: event.date)
            if groups.last?.day == day {
                groups[groups.count - 1].events.append(event)
            } else {
                groups.append(DayGroup(day: day, events: [event]))
            }
        }
        return groups
    }

    public var selectedEvent: ActivityEvent? {
        guard let selection else { return nil }
        return events.first { $0.id == selection }
    }

    // MARK: Loading

    public func requestOpen() {
        openRequest += 1
    }

    public func requestSettings() {
        settingsRequest += 1
    }

    public func requestOnboarding() {
        onboardingRequest += 1
    }

    public func requestUpdates() {
        updatesRequest += 1
    }

    /// Every caller joins the same in-flight disk read. A non-nil acknowledgement means this exact
    /// generation has actually published (not that another refresh was merely in progress).
    @discardableResult
    public func refresh(whileInterested interest: Interest? = nil) async -> Int? {
        guard !stopped, !Task.isCancelled, interest.map(interests.contains) != false else { return nil }
        while !stopped, !Task.isCancelled {
            guard interest.map(interests.contains) != false else { return nil }
            let current: Task<ActivityReadResult, Never>
            let expected: Int
            if let worker {
                current = worker
                expected = generation
            } else {
                generation += 1
                expected = generation
                let paths = summon.paths
                let crashes = summon.recentCrashes
                let agent = summon.defaultAgent
                let installed = summon.agentInstalled
                let macctlInstalled = macctlPath != nil
                let macctlProblems = macctlProblems
                current = Task.detached(priority: .utility) {
                    let interval = PanelTrace.signposter.beginInterval("SourceCollection", id: PanelTrace.signposter.makeSignpostID())
                    defer { PanelTrace.signposter.endInterval("SourceCollection", interval, "activity") }
                    let events: [LoggedEvent]
                    do {
                        var cursor = EventLogCursor(file: paths.eventLogFile)
                        events = try cursor.read().events
                    } catch {
                        return .failure("Could not read the activity log: \(error.localizedDescription)")
                    }
                    var loaded = ActivitySources.load(paths: paths, crashLimit: 0, log: events)
                    loaded.crashes = crashes
                    for report in crashes where loaded.crashDates[report.file] == nil {
                        loaded.crashDates[report.file] = ActivityFeed.crashDate(report)
                            ?? (try? URL(fileURLWithPath: report.file).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    }
                    let status = StatusProbe.build(agent: agent, agentInstalled: installed, log: loaded.log,
                                                   macctlInstalled: macctlInstalled, macctlProblems: macctlProblems,
                                                   snapshots: loaded.snapshots, checkpoints: loaded.checkpoints,
                                                   configIsRepo: loaded.configIsRepo, crashes: loaded.crashes,
                                                   crashDates: loaded.crashDates)
                    return .success(ActivityRead(sources: loaded, events: loaded.events, status: status,
                                                 results: TaskResults.latest(in: loaded.log), undoOffer: UndoOffer.latest(loaded),
                                                 agent: agent, agentInstalled: installed, macctlInstalled: macctlInstalled,
                                                 macctlProblems: macctlProblems))
                }
                worker = current
            }
            let result = await current.value
            guard !stopped, !Task.isCancelled, interest.map(interests.contains) != false else {
                if expected == generation { worker = nil }
                return nil
            }
            if current.isCancelled || expected != generation { continue }
            guard case .success(let collected) = result else {
                if case .failure(let message) = result {
                    activityReadError = message
                    lastError = message
                }
                worker = nil
                return nil
            }
            if lastError == activityReadError { lastError = nil }
            activityReadError = nil
            if publishedGeneration != expected {
                let interval = PanelTrace.signposter.beginInterval("MainPublication", id: PanelTrace.signposter.makeSignpostID())
                let sameInputs = collected.agent == summon.defaultAgent && collected.agentInstalled == summon.agentInstalled
                    && collected.macctlInstalled == (macctlPath != nil) && collected.macctlProblems == macctlProblems
                apply(collected.sources, events: collected.events, status: sameInputs ? collected.status : nil)
                summon.acceptActivity(taskResults: collected.results, undoOffer: collected.undoOffer)
                PanelTrace.signposter.endInterval("MainPublication", interval, "activity")
                publishedGeneration = expected
                lastPublishedGeneration = expected
                worker = nil
            }
            return expected
        }
        return nil
    }

    func apply(_ loaded: ActivitySources) { apply(loaded, events: loaded.events, status: nil) }

    func refreshStatus() {
        guard !stopped else { return }
        updateStatus(from: sources, collected: nil)
    }

    private func apply(_ loaded: ActivitySources, events latest: [ActivityEvent], status collected: SummonStatus?) {
        if loaded != sources {
            sources = loaded
            if events != latest { events = latest }
        }
        updateStatus(from: loaded, collected: collected)
    }

    private func updateStatus(from loaded: ActivitySources, collected: SummonStatus?) {
        let current = collected ?? StatusProbe.build(
            agent: summon.defaultAgent,
            agentInstalled: summon.agentInstalled,
            log: loaded.log,
            macctlInstalled: macctlPath != nil,
            macctlProblems: macctlProblems,
            snapshots: loaded.snapshots,
            checkpoints: loaded.checkpoints,
            configIsRepo: loaded.configIsRepo,
            crashes: loaded.crashes,
            crashDates: loaded.crashDates
        )
        if status != current { status = current }
    }

    /// `macctl doctor` probes Automation through AppleScript, so it runs on window open only.
    public func checkMacctl() async {
        let path = await Task.detached(priority: .utility) { ToolLocator.live().find("macctl") }.value
        guard !Task.isCancelled, interests.contains(.window) else { return }
        if macctlPath != path { macctlPath = path }
        guard let path else {
            if !macctlProblems.isEmpty { macctlProblems = [] }
            refreshStatus()
            return
        }
        do {
            let problems = StatusProbe.doctorProblems(fromJSON: try await runner(path, ["doctor", "--json"]))
            guard !Task.isCancelled, interests.contains(.window) else { return }
            if macctlProblems != problems { macctlProblems = problems }
            refreshStatus()
        } catch {
            guard !Task.isCancelled, interests.contains(.window) else { return }
            lastError = "macctl doctor failed: \(error)"
        }
    }

    /// The panel and Activity window explicitly own interest. One loop watches their shared data;
    /// there is no hidden one-second polling or second panel-specific reload loop.
    public func startInterest(_ interest: Interest) {
        guard live, !stopped, interests.insert(interest).inserted else { return }
        if interest == .window {
            doctorTask = Task { [weak self] in await self?.checkMacctl() }
        }
        guard refreshTask == nil else { return }
        dirty = true
        nextReconcile = Date()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let bell = await self?.reconcileIfNeeded() else { return }
                guard !Task.isCancelled else { return }
                await bell.wait(for: .seconds(60), tolerance: .seconds(15))
            }
        }
    }

    private func reconcileIfNeeded() async -> Doorbell {
        armWatches()
        if dirty || Date() >= nextReconcile {
            dirty = false
            nextReconcile = Date().addingTimeInterval(60)
            _ = await refresh()
        }
        return bell
    }

    public func stopInterest(_ interest: Interest) {
        guard interests.remove(interest) != nil else { return }
        if interest == .window { doctorTask?.cancel(); doctorTask = nil }
        guard interests.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = nil
        worker?.cancel()
        worker = nil
        generation += 1
        watches = [:]
        bell.ring()
    }

    /// The log watcher or a command can mark data dirty even while the window is closed.
    public func markDirty() {
        guard !stopped else { return }
        dirty = true
        if let worker {
            worker.cancel()
            self.worker = nil
            generation += 1
        }
        bell.ring()
    }

    private func armWatches() {
        let paths = summon.paths
        let targets = [paths.state, paths.config, paths.macctlSnapshots,
                       paths.macctlSnapshots.deletingLastPathComponent().appendingPathComponent("journal", isDirectory: true)]
        let directories = Set(targets.compactMap(FileWatch.nearestExistingDirectory(to:)))
        for directory in directories where watches[directory]?.isGone ?? true {
            watches[directory] = FileWatch(directory) { [weak self] in
                Task { @MainActor [weak self] in self?.markDirty() }
            }
        }
        watches = watches.filter { directories.contains($0.key) }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        stopInterest(.panel)
        stopInterest(.window)
        doctorTask?.cancel()
        doctorTask = nil
        worker?.cancel()
        worker = nil
        generation += 1
        actionTask?.cancel()
        actionTask = nil
    }

    // MARK: Actions

    public func runAgent(prompt: String) {
        guard !stopped else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        summon.askAgent(prompt: trimmed.isEmpty ? nil : trimmed)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { _ = await self?.refresh() }
        }
    }

    /// `macctl undo <id>`: restores the values that snapshot replaced.
    public func undo(snapshot id: String) {
        guard let macctlPath else {
            lastError = "macctl is not installed."
            return
        }
        let runner = runner
        perform { try await runner(macctlPath, ["undo", id, "--json"]) }
    }

    /// `summon checkpoint undo <id>`: settings and `~/.config` files back to that checkpoint.
    public func undo(checkpoint id: String) {
        guard let summonPath = summon.summonPath else {
            lastError = "The summon command is missing. Reinstall Summon."
            return
        }
        let runner = runner
        perform { try await runner(summonPath, ["checkpoint", "undo", id]) }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> String) {
        guard !stopped, !busy else { return }
        busy = true
        actionTask = Task { [weak self] in
            let result: Result<String, Error>
            do { result = .success(try await work()) }
            catch { result = .failure(error) }
            guard !Task.isCancelled, let self, !self.stopped else { return }
            switch result {
            case .success: self.lastError = nil
            case .failure(let error): self.lastError = String(describing: error)
            }
            self.busy = false
            self.actionTask = nil
            _ = await self.refresh()
        }
    }

    public func reveal(_ file: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)])
    }
}

extension ActivityModel {
    /// Sample timeline for previews; never runs commands.
    public static func preview(selecting index: Int? = nil) -> ActivityModel {
        let summon = SummonModel.preview()
        let model = ActivityModel(summon: summon) { _, _ in "" }
        let now = Date()
        let checkpoint = Checkpoint(id: "20261018-071000", label: "agent: tidy my Dock", createdAt: now.addingTimeInterval(-50 * 60),
                                    configCommit: nil, macctlSnapshot: "20261018-090000")
        let sources = ActivitySources(
            log: [
                LoggedEvent(time: now.addingTimeInterval(-49 * 60), kind: EventKind.agentLaunch, title: "Started Claude Code",
                            detail: "tidy my Dock", refs: ["agent": "claude", "folder": "~/Summon/mac-battery", "checkpoint": checkpoint.id]),
                LoggedEvent(time: now.addingTimeInterval(-48 * 60), kind: EventKind.sessionStart, title: "Claude Code session",
                            refs: ["session": "a1", "folder": "~/Summon/mac-battery"]),
                LoggedEvent(time: now.addingTimeInterval(-26 * 60 * 60), kind: EventKind.themeSet, title: "Theme: Summon Night",
                            refs: ["theme": "summon-night"]),
            ],
            snapshots: [
                MacctlSnapshot(id: "20261018-095500", createdAt: now.addingTimeInterval(-12 * 60), changes: [
                    SettingChange(id: "dock.autohide", from: "false", to: "true"),
                ]),
                MacctlSnapshot(id: "20261018-094000", createdAt: now.addingTimeInterval(-30 * 60), changes: [
                    SettingChange(id: "dock.tilesize", from: "64", to: "48"),
                    SettingChange(id: "dock.show-recents", from: "true", to: "false"),
                    SettingChange(id: "dock.minimize-effect", from: nil, to: "scale"),
                ]),
            ],
            checkpoints: [checkpoint],
            crashes: summon.recentCrashes,
            configIsRepo: false
        )
        model.live = false
        model.macctlPath = "/usr/local/bin/macctl"
        model.apply(sources)
        if let index, index < model.events.count {
            model.selection = model.events[index].id
        }
        return model
    }
}

/// Opens the Activity and Settings windows when requested from outside any view.
public struct ActivityOpener: ViewModifier {
    public static let windowID = "activity"
    let activity: ActivityModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init(activity: ActivityModel) {
        self.activity = activity
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: activity.openRequest) {
                openWindow(id: Self.windowID)
                bringToFront { $0.title.contains("Activity") }
            }
            .onChange(of: activity.settingsRequest) {
                openSettings()
                // The Settings scene's window is titled after the page shown, so it is found by its identifier.
                bringToFront { $0.identifier?.rawValue.contains("Settings") == true }
            }
            .onChange(of: activity.updatesRequest) {
                openWindow(id: UpdatesView.windowID)
                bringToFront { $0.title == UpdatesView.title }
            }
            .onChange(of: activity.onboardingRequest) {
                openWindow(id: OnboardingView.windowID)
                bringToFront { $0.title == OnboardingView.title }
            }
            // First launch: the opener is the one window open from launch, so it decides about the setup window.
            .task {
                guard activity.live else { return }
                let defaults = UserDefaults.standard
                switch OnboardingFlow.launch(completed: defaults.bool(forKey: OnboardingFlow.completedKey),
                                             visualQA: defaults.bool(forKey: "VisualQA"),
                                             hasDefaultAgent: activity.summon.defaultAgent != nil,
                                             accessibilityGranted: activity.summon.accessibilityGranted) {
                case .show: openWindow(id: OnboardingView.windowID)
                case .markCompleted: defaults.set(true, forKey: OnboardingFlow.completedKey)
                case .none: break
                }
            }
    }

    private func bringToFront(_ matches: @escaping (NSWindow) -> Bool) {
        DispatchQueue.main.async {
            NSApp.activate()
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: matches) else {
                    NSApp.activate()
                    return
                }
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                let mouse = NSEvent.mouseLocation
                let pointerScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                let targetScreen = pointerScreen ?? NSScreen.main ?? window.screen
                if let targetScreen, !targetScreen.frame.intersects(window.frame) {
                    let visible = targetScreen.visibleFrame
                    let x = visible.midX - window.frame.width / 2
                    let y = visible.midY - window.frame.height / 2
                    window.setFrameOrigin(NSPoint(x: x, y: y))
                }
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
    }
}

/// Hosts `ActivityOpener` in a 1×1 invisible window that lives for the whole session. The menu bar label is drawn
/// as an image, so modifiers on it never run, and `openSettings` needs a live SwiftUI view (MacUX Windows.md).
public struct OpenerHost: View {
    let activity: ActivityModel

    public init(activity: ActivityModel) {
        self.activity = activity
    }

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(InvisibleWindow())
            .modifier(ActivityOpener(activity: activity))
    }
}

/// Makes its window invisible, click-through, and out of ⌘` and the Window menu.
struct InvisibleWindow: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask = [.borderless]
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isExcludedFromWindowsMenu = true
            window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
            window.setFrame(NSRect(x: 0, y: 0, width: 1, height: 1), display: false)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
