import Foundation
import SummonCore

/// Keeps the status label live from file/directory changes. Clock ticks only while a session is displayed;
/// an independent slow reconciliation recovers missed vnode notifications without scanning at clock frequency.
/// Appended records are consumed by byte position, not by their writer-assigned timestamps.
@MainActor
final class MenuBarStatusWatcher {
    private let model: SummonModel
    private let apply: (_ title: String?, _ accessibilityLabel: String, _ attention: Bool) -> Void
    private var task: Task<Void, Never>?
    private var logWatch: FileWatch?
    private var directoryWatch: FileWatch?
    private var watchedDirectory: URL?
    private let bell = Doorbell()
    private var cursor: EventLogCursor
    private var delivered = EventDeliveryLedger()
    private var hasBaseline = false
    private var sessionEvents: [LoggedEvent] = []
    private var dirty = true
    private var nextReconcile = Date()
    private var generation = 0
    private var session: LoggedEvent?
    var onNewEvents: (([LoggedEvent]) -> Void)?
    var onLogChanged: (() -> Void)?
    var onBaselineReady: (() -> Void)?

    init(model: SummonModel, apply: @escaping (_ title: String?, _ accessibilityLabel: String, _ attention: Bool) -> Void) {
        self.model = model
        self.apply = apply
        self.cursor = EventLogCursor(file: model.paths.eventLogFile)
    }

    func start() {
        guard task == nil else { return }
        generation += 1
        dirty = true
        observeModel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let next = await self?.tick() else { return }
                guard !Task.isCancelled else { return }
                await next.0.wait(for: next.1 ? .seconds(1) : .seconds(60),
                                  tolerance: next.1 ? .milliseconds(100) : .seconds(15))
            }
        }
    }

    private func tick() async -> (Doorbell, Bool) {
        if dirty || Date() >= nextReconcile {
            watchDirectory()
            if logWatch?.isGone ?? true { watchLog() }
            dirty = false
            nextReconcile = Date().addingTimeInterval(60)
            await reloadIfChanged()
        }
        redraw()
        return (bell, session != nil && model.menuBarShowsAgentTime)
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        logWatch = nil
        directoryWatch = nil
        onBaselineReady = nil
        watchedDirectory = nil
        bell.ring()
    }

    private func watchDirectory() {
        let parent = model.paths.eventLogFile.deletingLastPathComponent()
        guard let directory = FileWatch.nearestExistingDirectory(to: parent) else { return }
        guard watchedDirectory != directory || (directoryWatch?.isGone ?? true) else { return }
        watchedDirectory = directory
        directoryWatch = FileWatch(directory) { [weak self] in
            Task { @MainActor [weak self] in self?.markDirty() }
        }
    }

    private func watchLog() {
        logWatch = FileWatch(model.paths.eventLogFile) { [weak self] in
            Task { @MainActor [weak self] in self?.markDirty() }
        }
    }

    private func markDirty() {
        dirty = true
        bell.ring()
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
        let current = cursor
        let expected = generation
        do {
            let result = try await Task.detached(priority: .utility) { () throws -> (EventLogCursor, EventLogCursor.Batch) in
                var reader = current
                let batch = try reader.read()
                return (reader, batch)
            }.value
            guard !Task.isCancelled, expected == generation else { return }
            cursor = result.0
            let batch = result.1
            if batch.reset { sessionEvents = [] }
            if !batch.events.isEmpty {
                sessionEvents.append(contentsOf: batch.events.filter {
                    $0.kind == EventKind.sessionStart || $0.kind == EventKind.sessionEnd
                })
                if sessionEvents.count > 256 { sessionEvents.removeFirst(sessionEvents.count - 256) }
            }
            session = StatusProbe.openSession(in: sessionEvents)
            let firstRead = !hasBaseline
            let newEvents = delivered.receive(batch.events, baseline: firstRead)
            hasBaseline = true
            if firstRead { onBaselineReady?(); onBaselineReady = nil }
            if !newEvents.isEmpty { onNewEvents?(newEvents) }
            if batch.reset || !batch.events.isEmpty { onLogChanged?() }
        } catch {
            PanelTrace.log.error("event log refresh failed: \(String(describing: error), privacy: .private)")
        }
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
        guard !Task.isCancelled else { return }
        if rung {
            rung = false
            return
        }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout, tolerance: tolerance)
            if !Task.isCancelled { self?.ring() }
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if rung {
                    rung = false
                    continuation.resume()
                } else {
                    waiter = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.ring() }
        }
        timer.cancel()
    }
}
