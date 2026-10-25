import Foundation

/// The starter's job: a stopwatch that keeps time while you work elsewhere. Time is computed from dates, never
/// counted by a timer, so the HUD can redraw rarely (or not at all while hidden) and still be exact.
public struct Stopwatch: Equatable, Sendable {
    public enum State: Equatable, Sendable { case idle, running, paused }

    /// Time banked by earlier runs.
    private var banked: TimeInterval = 0
    /// When the current run started; nil unless running.
    private var startedAt: Date?

    public init() {}

    public var state: State {
        if startedAt != nil { return .running }
        return banked > 0 ? .paused : .idle
    }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public mutating func start(at now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    public mutating func pause(at now: Date) {
        guard let startedAt else { return }
        banked += max(0, now.timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    public mutating func toggle(at now: Date) {
        state == .running ? pause(at: now) : start(at: now)
    }

    public mutating func reset() {
        banked = 0
        startedAt = nil
    }

    /// "0:07", "12:34", "1:02:03": no leading hours under an hour, so the HUD stays small.
    public static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
