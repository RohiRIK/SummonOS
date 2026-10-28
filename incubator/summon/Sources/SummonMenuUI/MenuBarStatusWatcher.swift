import Foundation
import SummonCore

/// Keeps the status item's label live while the panel is closed: Summon's icon alone, or the icon plus the running
/// agent's elapsed `mm:ss`. A `FileWatch` on the event log and observation of the model wake it, so it sleeps while
/// nothing happens; the clock ticks once a second only while it shows a session. A slow fallback round catches a
/// log that did not exist yet or was replaced.
/// The same read hands events newer than the app's launch to `onNewEvents` (task results become notifications).
@MainActor
final class MenuBarStatusWatcher {
    private let model: SummonModel
    private let apply: (_ title: String?, _ accessibilityLabel: String, _ attention: Bool) -> Void
    private var task: Task<Void, Never>?
    private var logWatch: FileWatch?
    private let bell = Doorbell()
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
        observeModel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.logWatch?.isGone ?? true { self.watchLog() }
                await self.reloadIfChanged()
                self.redraw()
                let ticking = self.session != nil && self.model.menuBarShowsAgentTime
                await self.bell.wait(for: ticking ? .seconds(1) : .seconds(60),
                                     tolerance: ticking ? .milliseconds(100) : .seconds(15))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        logWatch = nil
        bell.ring()
    }

    private func watchLog() {
        let bell = bell
        logWatch = FileWatch(model.paths.eventLogFile) { Task { @MainActor in bell.ring() } }
    }

    /// What the label shows besides the log: the attention dot, the clock setting and the agent's name.
    private func observeModel() {
        withObservationTracking {
            _ = model.doctorReport
            _ = model.menuBarShowsAgentTime
            _ = model.defaultAgent
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.task != nil else { return }
                self.bell.ring()
                self.observeModel()
            }
        }
    }

    /// Redraws now, for example after the Settings toggle changed.
    func redraw() {
        let now = Date()
        // A session older than `StatusProbe.staleSession` stops counting even if the log never moves again.
        if let start = session?.time, now.timeIntervalSince(start) >= StatusProbe.staleSession { session = nil }
        apply(MenuBarStatus.title(session: session, enabled: model.menuBarShowsAgentTime, now: now),
              MenuBarStatus.accessibilityLabel(agentName: model.defaultAgent?.name, session: session, now: now),
              !PanelAttention(doctor: model.doctorReport).isEmpty)
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

/// Wakes a waiting loop early; a ring while nobody waits is kept for the next wait.
@MainActor
final class Doorbell {
    private var waiter: CheckedContinuation<Void, Never>?
    private var rung = false

    func ring() {
        if let waiter {
            self.waiter = nil
            waiter.resume()
        } else {
            rung = true
        }
    }

    func wait(for timeout: Duration, tolerance: Duration) async {
        if rung {
            rung = false
            return
        }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout, tolerance: tolerance)
            if !Task.isCancelled { self?.ring() }
        }
        await withCheckedContinuation { waiter = $0 }
        timer.cancel()
    }
}
