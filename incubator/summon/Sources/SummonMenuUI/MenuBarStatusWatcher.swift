import Foundation
import SummonCore

/// Keeps the status item's label live while the panel is closed: Summon's icon alone, or the icon plus the running
/// agent's elapsed `mm:ss`. It checks the event log's modification date every `MenuBarStatus.pollInterval` seconds
/// and only re-reads the log when that date moves; the clock ticks once a second only while a session is open.
/// The same read hands events newer than the app's launch to `onNewEvents` (task results become notifications).
@MainActor
final class MenuBarStatusWatcher {
    private let model: SummonModel
    private let apply: (_ title: String?, _ accessibilityLabel: String, _ attention: Bool) -> Void
    private var task: Task<Void, Never>?
    private var logDate: Date?
    private var session: LoggedEvent?
    /// Events up to this time were seen; starts at launch (whole seconds, as the log stores them), so older events
    /// are never announced. `seenAtBoundary` holds the events of that last second already handed on.
    private var seenUntil = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    private var seenAtBoundary: [LoggedEvent] = []
    var onNewEvents: (([LoggedEvent]) -> Void)?

    init(model: SummonModel, apply: @escaping (_ title: String?, _ accessibilityLabel: String, _ attention: Bool) -> Void) {
        self.model = model
        self.apply = apply
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            var sinceCheck = MenuBarStatus.pollInterval
            while !Task.isCancelled {
                guard let self else { return }
                if sinceCheck >= MenuBarStatus.pollInterval {
                    sinceCheck = 0
                    await self.reloadIfChanged()
                }
                self.redraw()
                try? await Task.sleep(for: .seconds(1))
                sinceCheck += 1
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Redraws now, for example after the Settings toggle changed.
    func redraw() {
        let now = Date()
        // A session older than `StatusProbe.staleSession` stops counting even if the log never moves again.
        if let start = session?.time, now.timeIntervalSince(start) >= StatusProbe.staleSession { session = nil }
        apply(MenuBarStatus.title(session: session, enabled: model.menuBarShowsAgentTime, now: now),
              MenuBarStatus.accessibilityLabel(agentName: model.defaultAgent?.name, session: session, now: now),
              !PanelAttention(reports: model.panelProblems, doctor: model.doctorReport).isEmpty)
    }

    private func reloadIfChanged() async {
        let file = model.paths.eventLogFile
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != logDate else { return }
        logDate = modified
        let paths = model.paths
        let events = await Task.detached { EventLog(paths: paths).read() }.value
        session = StatusProbe.openSession(in: events)
        let fresh = events.filter { $0.time > seenUntil || ($0.time == seenUntil && !seenAtBoundary.contains($0)) }
        let newest = max(seenUntil, EventAnnouncer.baseline(events))
        if newest > seenUntil { seenAtBoundary = [] }
        seenUntil = newest
        seenAtBoundary += fresh.filter { $0.time == newest }
        if !fresh.isEmpty { onNewEvents?(fresh) }
    }
}
