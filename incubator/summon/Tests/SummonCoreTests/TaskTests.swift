import Foundation
import Testing
@testable import SummonCore

@Suite("Recurring agent tasks")
struct TaskTests {
    @Test func everyParsesUnitsAndRefusesTooOften() {
        #expect(TaskSchedule.parseEvery("30m") == .every(minutes: 30))
        #expect(TaskSchedule.parseEvery("2h") == .every(minutes: 120))
        #expect(TaskSchedule.parseEvery("1d") == .every(minutes: 1440))
        #expect(TaskSchedule.parseEvery("1m") == nil)
        #expect(TaskSchedule.parseEvery("0h") == nil)
        #expect(TaskSchedule.parseEvery("soon") == nil)
    }

    @Test func atParsesTimeAndDays() {
        #expect(TaskSchedule.parseAt("09:30") == .daily(hour: 9, minute: 30, weekdays: []))
        #expect(TaskSchedule.parseAt("07:05", days: "weekdays") == .daily(hour: 7, minute: 5, weekdays: [1, 2, 3, 4, 5]))
        #expect(TaskSchedule.parseAt("18:00", days: "fri,mon") == .daily(hour: 18, minute: 0, weekdays: [1, 5]))
        #expect(TaskSchedule.parseAt("18:00", days: "mon,tue,wed,thu,fri,sat,sun") == .daily(hour: 18, minute: 0, weekdays: []))
        #expect(TaskSchedule.parseAt("24:00") == nil)
        #expect(TaskSchedule.parseAt("9") == nil)
        #expect(TaskSchedule.parseAt("09:00", days: "someday") == nil)
    }

    @Test func summaryAndArgumentsRoundTrip() {
        let schedules: [TaskSchedule] = [
            .every(minutes: 45), .every(minutes: 120), .every(minutes: 1440),
            .daily(hour: 9, minute: 0, weekdays: []), .daily(hour: 9, minute: 0, weekdays: [1, 2, 3, 4, 5]),
            .daily(hour: 21, minute: 15, weekdays: [3, 7]),
        ]
        #expect(schedules.map(\.summary) == [
            "every 45 minutes", "every 2 hours", "every day",
            "every day at 09:00", "weekdays at 09:00", "Wed, Sun at 21:15",
        ])
        for schedule in schedules {
            let args = schedule.arguments
            let parsed: TaskSchedule?
            if args[0] == "--every" {
                parsed = TaskSchedule.parseEvery(args[1])
            } else {
                parsed = TaskSchedule.parseAt(args[1], days: args.count > 3 ? args[3] : nil)
            }
            #expect(parsed == schedule)
        }
    }

    @Test func editorChoicesMakeSchedules() {
        #expect(TaskRepeat.hourly.schedule(hours: 6, hour: 9, minute: 0) == .every(minutes: 360))
        #expect(TaskRepeat.daily.schedule(hours: 6, hour: 8, minute: 30) == .daily(hour: 8, minute: 30, weekdays: []))
        #expect(TaskRepeat.weekdays.schedule(hours: 6, hour: 8, minute: 30) == .daily(hour: 8, minute: 30, weekdays: [1, 2, 3, 4, 5]))
    }

    @Test func idsAreKebabCase() {
        #expect(AgentTask.isValidID("morning-crashes"))
        #expect(!AgentTask.isValidID("Morning"))
        #expect(!AgentTask.isValidID("-x"))
        #expect(!AgentTask.isValidID("a b"))
        #expect(!AgentTask.isValidID(String(repeating: "a", count: 41)))
    }

    @Test func storeRoundTripsAndRefusesABrokenFile() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let store = TaskStore(paths: paths)
        #expect(try store.load().tasks.isEmpty)
        var list = TaskList()
        list.upsert(AgentTask(id: "a", prompt: "one", schedule: .every(minutes: 60), created: Date(timeIntervalSince1970: 1_800_000_000)))
        list.upsert(AgentTask(id: "b", prompt: "two", schedule: .daily(hour: 9, minute: 0, weekdays: [1]), agent: "codex",
                              created: Date(timeIntervalSince1970: 1_800_000_000)))
        list.upsert(AgentTask(id: "a", prompt: "one again", schedule: .every(minutes: 60), created: Date(timeIntervalSince1970: 1_800_000_000)))
        try store.save(list)
        #expect(try store.load() == list)
        #expect(list.tasks.map(\.prompt) == ["one again", "two"])
        #expect(list.remove("b")?.agent == "codex")
        try writeFile("{ broken", to: paths.tasksFile)
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test func headlessModesNeverSkipPermissions() throws {
        let claude = try #require(AgentRegistry.find("claude"))
        #expect(claude.headlessArgv(prompt: "check", model: "opus") == ["claude", "--print", "--model", "opus", "--", "check"])
        let codex = try #require(AgentRegistry.find("codex"))
        #expect(codex.headlessArgv(prompt: "check", model: nil) == ["codex", "exec", "--sandbox", "read-only", "--", "check"])
        let copilot = try #require(AgentRegistry.find("copilot"))
        #expect(copilot.headlessArgv(prompt: "check", model: "x")?.last == "check")
        #expect(AgentRegistry.find("grok")?.headlessArgv(prompt: "check", model: nil) == nil)
        for agent in AgentRegistry.all {
            let argv = agent.headlessArgv(prompt: "p", model: nil) ?? []
            #expect(!argv.contains { $0.contains("dangerously") || $0.hasPrefix("--allow-all") || $0 == "--yolo" }, "\(agent.id)")
        }
    }

    @Test func launchAgentRunsTheTaskOnItsSchedule() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let interval = AgentTask(id: "disk", prompt: "p", schedule: .every(minutes: 90))
        let job = TaskLaunchAgent.plist(interval, summonPath: "/Users/x/.local/bin/summon", paths: paths)
        #expect(job["Label"] as? String == "local.macplugins.summon.task.disk")
        #expect(job["ProgramArguments"] as? [String] == ["/Users/x/.local/bin/summon", "task", "run", "disk", "--scheduled"])
        #expect(job["StartInterval"] as? Int == 5400)
        #expect(job["StartCalendarInterval"] == nil)

        let daily = AgentTask(id: "morning", prompt: "p", schedule: .daily(hour: 9, minute: 5, weekdays: []))
        let dailyJob = TaskLaunchAgent.plist(daily, summonPath: "/s", paths: paths)
        #expect(dailyJob["StartCalendarInterval"] as? [String: Int] == ["Hour": 9, "Minute": 5])

        let weekly = AgentTask(id: "weekly", prompt: "p", schedule: .daily(hour: 9, minute: 0, weekdays: [1, 5]))
        let weeklyJob = TaskLaunchAgent.plist(weekly, summonPath: "/s", paths: paths)
        #expect(weeklyJob["StartCalendarInterval"] as? [[String: Int]] == [
            ["Weekday": 1, "Hour": 9, "Minute": 0], ["Weekday": 5, "Hour": 9, "Minute": 0],
        ])
        let data = try TaskLaunchAgent.data(weekly, summonPath: "/s", paths: paths)
        let decoded = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(decoded?["Label"] as? String == "local.macplugins.summon.task.weekly")
    }

    @Test func syncWritesAndLoadsOrRemovesTheJob() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let log = CallLog()
        var task = AgentTask(id: "disk", prompt: "p", schedule: .every(minutes: 60))
        let problems = try await TaskLaunchAgent.sync(task, summonPath: "/s", paths: paths, runner: fakeRunner(log), uid: 501)
        #expect(problems.isEmpty)
        let file = TaskLaunchAgent.file("disk", paths: paths)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(await log.calls == [
            ["/bin/launchctl", "bootout", "gui/501/local.macplugins.summon.task.disk"],
            ["/bin/launchctl", "bootstrap", "gui/501", file.path],
        ])

        task.enabled = false
        _ = try await TaskLaunchAgent.sync(task, summonPath: "/s", paths: paths, runner: fakeRunner(log), uid: 501)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await log.calls.last == ["/bin/launchctl", "bootout", "gui/501/local.macplugins.summon.task.disk"])
    }

    /// A runner whose agent is a fake `claude` in /fake/bin and whose executor writes `output` to the log.
    func makeRunner(paths: SummonPaths, log: CallLog, status: Int32 = 0, timedOut: Bool = false, output: String = "All good.\n") -> TaskRunner {
        let tools = ToolLocator(searchPath: ["/fake/bin"]) { path in (path as NSString).lastPathComponent == "claude" }
        let execute: TaskExecutor = { path, arguments, directory, file, _ in
            await log.add([path] + arguments + ["@" + directory.path])
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(output.utf8).write(to: file)
            return TaskExit(status: status, timedOut: timedOut)
        }
        return TaskRunner(paths: paths, runner: fakeRunner(log), execute: execute, tools: tools, gitPath: nil, macctlPath: nil)
    }

    @Test func runTakesACheckpointRunsHeadlessAndRecordsTheResult() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        try writeFile("claude\n", to: paths.defaultAgentFile)
        let log = CallLog()
        let task = AgentTask(id: "morning", prompt: "Summarize crashes", schedule: .every(minutes: 60))
        let result = await makeRunner(paths: paths, log: log).run(task, footer: " [skills]", now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(result.status == .ok)
        #expect(result.summary == "All good.")
        #expect(await log.calls == [["/fake/bin/claude", "--print", "--", "Summarize crashes [skills]", "@" + paths.projects.path]])
        #expect(CheckpointService(paths: paths, runner: fakeRunner(log), gitPath: nil, macctlPath: nil).list().last?.label == "task: morning")
        let run = try #require(EventLog(paths: paths).lastTaskRuns()["morning"])
        #expect(run.title == "Task morning finished")
        #expect(run.refs["status"] == "ok")
        #expect(run.refs["checkpoint"] == result.checkpoint)
        #expect(ActivityFeed.event(from: run).category == .agent)
        #expect(FileManager.default.fileExists(atPath: paths.taskState.appendingPathComponent("morning/running").path) == false)
    }

    @Test func failuresAndSkipsShowAsProblems() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let log = CallLog()
        let noAgent = await makeRunner(paths: paths, log: log).run(AgentTask(id: "a", prompt: "p", schedule: .every(minutes: 60)))
        #expect(noAgent.status == .skipped)
        #expect(await log.calls.isEmpty)

        let grok = await makeRunner(paths: paths, log: log).run(AgentTask(id: "b", prompt: "p", schedule: .every(minutes: 60), agent: "grok"))
        #expect(grok.status == .skipped)

        let failed = await makeRunner(paths: paths, log: log, status: 3, output: "boom\n")
            .run(AgentTask(id: "c", prompt: "p", schedule: .every(minutes: 60), agent: "claude"))
        #expect(failed.status == .failed)
        #expect(failed.summary == "Exit 3: boom")

        let slow = await makeRunner(paths: paths, log: log, status: 15, timedOut: true)
            .run(AgentTask(id: "d", prompt: "p", schedule: .every(minutes: 60), agent: "claude", timeoutMinutes: 5))
        #expect(slow.status == .timeout)

        let runs = EventLog(paths: paths).lastTaskRuns()
        #expect(runs.keys.sorted() == ["a", "b", "c", "d"])
        #expect(runs.values.allSatisfy { ActivityFeed.event(from: $0).category == .problem })
    }

    @Test func aRunStillGoingIsNotStartedTwice() throws {
        let lock = try makeTempHome().appendingPathComponent("t/running")
        // pid 1 (launchd) is always alive and is not this process.
        try writeFile("1\n", to: lock)
        #expect(!TaskRunner.acquire(lock))
        // A lock left by a process that is gone is taken over.
        try writeFile("999999\n", to: lock)
        #expect(TaskRunner.acquire(lock))
    }

    @Test func onlyTheNewestLogsAreKept() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let runner = makeRunner(paths: paths, log: CallLog())
        let folder = paths.taskState.appendingPathComponent("x", isDirectory: true)
        for index in 0..<(TaskRunner.keptLogs + 5) {
            try writeFile("run \(index)", to: folder.appendingPathComponent(String(format: "20261018-%06d.log", index)))
        }
        try writeFile("launchd", to: folder.appendingPathComponent("launchd.log"))
        runner.pruneLogs("x")
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != "launchd.log" }
        #expect(left.count == TaskRunner.keptLogs)
        #expect(runner.latestLog("x")?.lastPathComponent == String(format: "20261018-%06d.log", TaskRunner.keptLogs + 4))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("launchd.log").path))
    }

    @Test func executorStopsARunThatTakesTooLong() async throws {
        let home = try makeTempHome()
        let log = home.appendingPathComponent("out.log")
        let quick = try await Shell.logged("/bin/sh", ["-c", "pwd; echo done"], home, log, 10)
        #expect(quick == TaskExit(status: 0, timedOut: false))
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.hasSuffix("done\n"))
        let slow = try await Shell.logged("/bin/sleep", ["30"], home, log, 0.5)
        #expect(slow.timedOut)
    }

    @Test func catalogListsTheTaskCommands() {
        for route in ["task add", "task list", "task run", "task log", "task enable", "task disable", "task remove"] {
            #expect(CommandCatalog.find(route) != nil, "\(route)")
        }
    }
}
