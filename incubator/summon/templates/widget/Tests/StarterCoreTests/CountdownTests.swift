import Foundation
import Testing
@testable import StarterCore

struct CountdownTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour, minute: minute))!
    }

    let now = Self.date(10, 15)

    @Test func countsCalendarDaysToALaterDay() {
        let countdown = Countdown(title: "Launch", target: Self.date(20, 9))
        #expect(countdown.phase(at: now, calendar: Self.calendar) == .upcoming(days: 10))
        // Tomorrow at 1 a.m. is 1 day left, though it is only 10 hours away.
        let tomorrow = Countdown(title: "Soon", target: Self.date(11, 1))
        #expect(tomorrow.phase(at: now, calendar: Self.calendar) == .upcoming(days: 1))
    }

    @Test func laterTodayIsToday() {
        let countdown = Countdown(title: "Call", target: Self.date(10, 18))
        #expect(countdown.phase(at: now, calendar: Self.calendar) == .today)
    }

    @Test func pastDatesCountDaysSince() {
        #expect(Countdown(title: "Trip", target: Self.date(8, 20)).phase(at: now, calendar: Self.calendar) == .passed(days: 2))
        #expect(Countdown(title: "Lunch", target: Self.date(10, 12)).phase(at: now, calendar: Self.calendar) == .passed(days: 0))
        #expect(Countdown(title: "Exactly", target: now).phase(at: now, calendar: Self.calendar) == .passed(days: 0))
    }

    @Test func timelineStartsNowHasTheTargetAndEachMidnight() {
        let countdown = Countdown(title: "Launch", target: Self.date(12, 9))
        let dates = countdown.timelineDates(from: now, limit: 5, calendar: Self.calendar)
        #expect(dates == [now, Self.date(11), Self.date(12), Self.date(12, 9), Self.date(13)])
        #expect(dates == dates.sorted())
    }

    @Test func timelineHasNoDuplicatesAndKeepsTheLimit() {
        let atMidnight = Countdown(title: "New day", target: Self.date(11))
        let dates = atMidnight.timelineDates(from: now, limit: 3, calendar: Self.calendar)
        #expect(dates == [now, Self.date(11), Self.date(12)])
        #expect(atMidnight.timelineDates(from: now, limit: 0, calendar: Self.calendar).isEmpty)
    }

    @Test func aPassedTargetIsNotInTheTimeline() {
        let past = Countdown(title: "Trip", target: Self.date(8))
        let dates = past.timelineDates(from: now, limit: 3, calendar: Self.calendar)
        #expect(dates == [now, Self.date(11), Self.date(12)])
    }
}
