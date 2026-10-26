import Foundation

/// The widget's kind: the app reloads it by this name (`WidgetCenter.reloadTimelines(ofKind:)`).
public enum StarterWidgetKind {
    public static let countdown = "StarterCountdown"
}

/// Days to (or since) one date. Counts calendar days, so "1 day left" means tomorrow, whatever the hour.
public struct Countdown: Equatable, Sendable {
    public var title: String
    public var target: Date

    public init(title: String, target: Date) {
        self.title = title
        self.target = target
    }

    public enum Phase: Equatable, Sendable {
        /// The date is on a later day.
        case upcoming(days: Int)
        /// The date is later today: the widget shows a live timer.
        case today
        /// The date has passed; 0 means earlier today.
        case passed(days: Int)
    }

    public func phase(at now: Date, calendar: Calendar = .current) -> Phase {
        if now >= target { return .passed(days: Self.days(from: target, to: now, calendar: calendar)) }
        let days = Self.days(from: now, to: target, calendar: calendar)
        return days == 0 ? .today : .upcoming(days: days)
    }

    /// When the widget must redraw: now, the target, and each midnight after now, at most `limit` dates. Within a
    /// day the timer text updates itself, so the timeline stays well inside WidgetKit's daily reload budget.
    public func timelineDates(from now: Date, limit: Int = 8, calendar: Calendar = .current) -> [Date] {
        guard limit > 0 else { return [] }
        var dates: Set<Date> = [now]
        if target > now { dates.insert(target) }
        var day = calendar.startOfDay(for: now)
        for _ in 0..<limit {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            dates.insert(next)
            day = next
        }
        return Array(dates.sorted().prefix(limit))
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
