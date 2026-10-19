import Foundation
import Testing
@testable import SummonCore

@Suite("Recurring agent tasks")
struct RecurringTaskTests {
    @Test func schedulesParseAndDescribeThemselves() throws {
        let daily = try TaskSchedule.parse(at: "9:05", weekdays: false, every: nil)
        #expect(daily == TaskSchedule(kind: .daily, hour: 9, minute: 5))
        #expect(daily.summary == "Every day at 09:05")
        let weekdays = try TaskSchedule.parse(at: "18:30", weekdays: true, every: nil)
        #expect(weekdays.summary == "Weekdays at 18:30")
        let interval = try TaskSchedule.parse(at: nil, weekdays: false, every: "3h")
        #expect(interval == TaskSchedule(kind: .interval, everyHours: 3))
        #expect(interval.summary == "Every 3 hours")
        #expect(try TaskSchedule.parse(at: nil, weekdays: false, every: "1h").summary == "Every hour")
        #expect(throws: TaskSchedule.ParseError.self) { try TaskSchedule.parse(at: "25:00", weekdays: false, every: nil) }
        #expect(throws: TaskSchedule.ParseError.self) { try TaskSchedule.parse(at: nil, weekdays: false, every: "0h") }
        #expect(throws: TaskSchedule.ParseError.self) { try TaskSchedule.parse(at: nil, weekdays: false, every: nil) }
        #expect(throws: TaskSchedule.ParseError.self) { try TaskSchedule.parse(at: "9:00", weekdays: false, every: "2h") }
    }

    @Test func launchdPlistRunsTheTaskOnSchedule() throws {
        let task = RecurringTask(id: "brew-check", name: "Brew check", prompt: "Check brew", agent: "claude",
                                 schedule: TaskSchedule(kind: .weekdays, hour: 9, minute: 0))
        let data = try TaskPlist.data(for: task, summon: "/u/a/.local/bin/summon", path: "/usr/bin:/bin", logDir: "/tmp/logs")
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "local.macplugins.summon.task.brew-check")
        #expect(plist["ProgramArguments"] as? [String] == ["/u/a/.local/bin/summon", "task", "run", "brew-check"])
        let times = try #require(plist["StartCalendarInterval"] as? [[String: Int]])
        #expect(times.count == 5)
        #expect(times.allSatisfy { $0["Hour"] == 9 && $0["Minute"] == 0 })
        #expect(Set(times.compactMap { $0["Weekday"] }) == [1, 2, 3, 4, 5])
        #expect((plist["EnvironmentVariables"] as? [String: String])?["PATH"] == "/usr/bin:/bin")
        let hourly = RecurringTask(id: "x", name: "x", prompt: "p", agent: nil, schedule: TaskSchedule(kind: .interval, everyHours: 2))
        let hourlyPlist = try #require(try PropertyListSerialization.propertyList(
            from: try TaskPlist.data(for: hourly, summon: "/s", path: "/bin", logDir: "/tmp"), format: nil) as? [String: Any])
        #expect(hourlyPlist["StartInterval"] as? Int == 7200)
    }

    @Test func headlessCommandsPerAgent() throws {
        #expect(try #require(AgentRegistry.find("claude")).headless(prompt: "p", model: nil)
            == ["claude", "-p", "--dangerously-skip-permissions", "--", "p"])
        #expect(try #require(AgentRegistry.find("codex")).headless(prompt: "p", model: "o3")
            == ["codex", "--model", "o3", "exec", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check", "--", "p"])
        #expect(try #require(AgentRegistry.find("agy")).headless(prompt: "p", model: nil)
            == ["agy", "--dangerously-skip-permissions", "-p", "p"])
        #expect(try #require(AgentRegistry.find("pi")).headless(prompt: "p", model: nil) == ["pi", "-p", "--", "p"])
        #expect(try #require(AgentRegistry.find("opencode")).headless(prompt: "p", model: nil) == ["opencode", "run", "--auto", "p"])
        #expect(try #require(AgentRegistry.find("grok")).headless(prompt: "p", model: nil) == nil)
    }

    @Test func storeRoundTripsAndMakesUniqueIDs() throws {
        let store = TaskStore(paths: SummonPaths(home: try makeTempHome()))
        #expect(store.load().isEmpty)
        let first = RecurringTask(id: store.newID(for: "Brew check!"), name: "Brew check!", prompt: "p", agent: nil,
                                  schedule: TaskSchedule(kind: .daily, hour: 8, minute: 0))
        #expect(first.id == "brew-check")
        try store.save([first])
        #expect(store.newID(for: "brew check") == "brew-check-2")
        #expect(store.load() == [first])
    }
}
