import AppKit
import Foundation
import Observation
import SummonCore
import SwiftUI

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

    /// False for previews: no disk reads, commands or activation-policy changes.
    @ObservationIgnored public internal(set) var live = true
    @ObservationIgnored private var refreshTask: Task<Void, Never>? = nil
    @ObservationIgnored private var loading = false

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

    /// Reloads every source off the main actor. Cheap: small JSON files, no crash parsing.
    public func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let paths = summon.paths
        var loaded = await Task.detached { ActivitySources.load(paths: paths, crashLimit: 0) }.value
        loaded.crashes = summon.recentCrashes
        for report in loaded.crashes where loaded.crashDates[report.file] == nil {
            loaded.crashDates[report.file] = ActivityFeed.crashDate(report)
        }
        apply(loaded)
    }

    func apply(_ loaded: ActivitySources) {
        if loaded != sources {
            sources = loaded
            events = loaded.events
        }
        status = StatusProbe.build(
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
    }

    /// `macctl doctor` probes Automation through AppleScript, so it runs on open, not on every refresh.
    public func checkMacctl() async {
        macctlPath = ToolLocator.live().find("macctl")
        guard let macctlPath else {
            macctlProblems = []
            return
        }
        do {
            macctlProblems = StatusProbe.doctorProblems(fromJSON: try await runner(macctlPath, ["doctor", "--json"]))
        } catch {
            macctlProblems = ["doctor failed: \(error)"]
        }
        apply(sources)
    }

    /// Refreshes every few seconds while the window is open; the event files are tiny.
    public func startAutoRefresh(interval: Duration = .seconds(3)) {
        guard live, refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.checkMacctl()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Actions

    public func runAgent(prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        summon.askAgent(prompt: trimmed.isEmpty ? nil : trimmed)
        Task {
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    /// `macctl undo <id>`: restores the values that snapshot replaced.
    public func undo(snapshot id: String) {
        guard let macctlPath else {
            lastError = "macctl is not installed."
            return
        }
        perform { try await self.runner(macctlPath, ["undo", id, "--json"]) }
    }

    /// `summon checkpoint undo <id>`: settings and `~/.config` files back to that checkpoint.
    public func undo(checkpoint id: String) {
        guard let summonPath = summon.summonPath else {
            lastError = "The summon command is missing. Reinstall Summon."
            return
        }
        perform { try await self.runner(summonPath, ["checkpoint", "undo", id]) }
    }

    private func perform(_ work: @escaping @MainActor () async throws -> String) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                _ = try await work()
                lastError = nil
            } catch {
                lastError = String(describing: error)
            }
            busy = false
            await refresh()
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
    public static let settingsWindowID = "settings"
    let activity: ActivityModel
    @Environment(\.openWindow) private var openWindow

    public init(activity: ActivityModel) {
        self.activity = activity
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: activity.openRequest) {
                present(id: Self.windowID, title: "Summon Activity")
            }
            .onChange(of: activity.settingsRequest) {
                present(id: Self.settingsWindowID, title: "Summon Settings")
            }
    }

    private func present(id: String, title: String) {
        openWindow(id: id)
        bringToFront(title: title)
    }

    private func bringToFront(title: String) {
        DispatchQueue.main.async {
            NSApp.activate()
            DispatchQueue.main.async {
                guard let window = NSApp.windows.first(where: { $0.title == title || $0.title.contains(title) }) else {
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
