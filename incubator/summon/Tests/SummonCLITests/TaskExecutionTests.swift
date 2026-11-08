import Foundation
import Testing
import SummonCore
@testable import SummonCLI

@Suite("Task failure and recovery")
struct TaskExecutionTests {
    @MainActor @Test func failedUnloadPreservesTaskAndLaunchAgentForRecovery() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let task = RecurringTask(id: "retained", name: "Fixture", prompt: "p", agent: "claude", schedule: .init(kind: .daily))
        try TaskStore(paths: paths).save([task])
        let file = TaskPlist.file(task.id, home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture plist".utf8).write(to: file)
        let context = Context(paths: paths, runner: { path, _ in throw RunnerError.failed(path: path, status: 1, output: "permission denied") },
                              tools: ToolLocator(searchPath: [], isExecutable: { _ in false }))
        var args = Arguments([task.id])
        await #expect(throws: RunnerError.self) { try await TaskCommands.remove(&args, context) }
        #expect(try TaskStore(paths: paths).loadValidated() == [task])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor @Test func addAndRemoveSerializeTheEntireSchedulingLifecycle() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let scheduler = FixtureScheduler()
        let context = Context(paths: paths, runner: { _, args in try await scheduler.run(args) },
                              tools: ToolLocator(searchPath: [], isExecutable: { _ in false }))
        let adding = Task {
            var args = Arguments(["p", "--at", "09:00", "--agent", "claude", "--name", "race", "--execution", "normal", "--directory", home.path])
            try await TaskCommands.add(&args, context)
        }
        for _ in 0..<200 {
            if await scheduler.bootstrapping { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await scheduler.bootstrapping)
        let saved = try #require(try TaskStore(paths: paths).loadValidated().first)
        #expect(saved.agent == "claude")
        #expect(saved.execution == .normal)
        #expect(saved.directory != nil)
        var removal = Arguments(["race"])
        try await TaskCommands.remove(&removal, context)
        try await adding.value
        #expect(try TaskStore(paths: paths).loadValidated().isEmpty)
        #expect(await scheduler.installed == false)
        #expect(!FileManager.default.fileExists(atPath: TaskPlist.file("race", home: home).path))
    }

    @MainActor @Test func unknownPinnedAgentDoesNotFallBackToDefault() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        try DefaultAgentStore(paths: paths).save(#require(AgentRegistry.find("claude")))
        let task = RecurringTask(id: "unknown", name: "Fixture", prompt: "p", agent: "unknown-agent", schedule: .init(kind: .daily))
        try TaskStore(paths: paths).save([task])
        let context = Context(paths: paths, runner: { _, _ in "" }, tools: ToolLocator(searchPath: [], isExecutable: { _ in false }))
        do {
            try await TaskCommands.runTask(task.id, context)
            Issue.record("Task unexpectedly selected a fallback agent")
        } catch let error as CLIError {
            #expect(error.message.contains("saved agent is unknown"))
        }
    }

    @MainActor @Test func failedAgentThrowsAndLeavesAFailureEvent() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let agent = bin.appendingPathComponent("claude")
        try Data("#!/bin/sh\nprintf 'fixture failure'\nexit 7\n".utf8).write(to: agent)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        let locator = ToolLocator(searchPath: [bin.path], isExecutable: { $0 == agent.path })
        let context = Context(paths: paths, runner: { _, _ in "" }, tools: locator)
        let task = RecurringTask(id: "failed", name: "Fixture", prompt: "local test", agent: "claude", schedule: .init(kind: .daily))
        try TaskStore(paths: paths).save([task])
        await #expect(throws: CLIError.self) { try await TaskCommands.runTask(task.id, context) }
        let events = EventLog(paths: paths).read()
        #expect(events.last?.kind == EventKind.taskFailed)
        #expect(events.last?.detail?.contains("7") == true)
        #expect(!events.contains { $0.kind == EventKind.taskDone })
    }

    @MainActor @Test func scheduledRunTellsTheAgentItIsUnattended() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let agent = bin.appendingPathComponent("claude")
        let received = home.appendingPathComponent("argv.txt")
        try Data("#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > '\(received.path)'\nprintf 'All good'\n".utf8).write(to: agent)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        let locator = ToolLocator(searchPath: [bin.path], isExecutable: { $0 == agent.path })
        let context = Context(paths: paths, runner: { _, _ in "" }, tools: locator)
        let task = RecurringTask(id: "brief", name: "Brew check", prompt: "Check brew updates.", agent: "claude", schedule: .init(kind: .daily))
        try TaskStore(paths: paths).save([task])
        try await TaskCommands.runTask(task.id, context)
        let argv = try String(contentsOf: received, encoding: .utf8)
        #expect(argv.contains("scheduled Summon task \"Brew check\""))
        #expect(argv.contains("Check brew updates."))
        #expect(argv.contains(SessionBrief.heading))
        #expect(argv.contains("Stopped after 30 minutes"))
        #expect(EventLog(paths: paths).read().last?.kind == EventKind.taskDone)
    }

    @MainActor @Test func checkpointFailurePreventsAgentExecution() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let agent = bin.appendingPathComponent("claude")
        let marker = home.appendingPathComponent("must-not-run")
        try Data("#!/bin/sh\n/usr/bin/touch '\(marker.path)'\n".utf8).write(to: agent)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        let locator = ToolLocator(searchPath: [bin.path], isExecutable: { $0 == agent.path || $0.hasSuffix("/macctl") })
        let context = Context(paths: paths, runner: { path, _ in throw RunnerError.failed(path: path, status: 1, output: "capture failed") }, tools: locator)
        let task = RecurringTask(id: "blocked", name: "Fixture", prompt: "local test", agent: "claude", schedule: .init(kind: .daily))
        try TaskStore(paths: paths).save([task])
        await #expect(throws: CLIError.self) { try await TaskCommands.runTask(task.id, context) }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(EventLog(paths: paths).read().last?.detail?.contains("Checkpoint failed") == true)
        let checkpoints = try CheckpointService(paths: paths, runner: { _, _ in "" }, gitPath: nil, macctlPath: nil).listValidated()
        #expect(checkpoints.last?.problems?.isEmpty == false)
    }

    // MARK: Finish: one accurate terminal outcome per run

    @MainActor @Test func longEscapedFinalLineRecordsOneDoneResultAndKeepsTheLog() async throws {
        // 72,000 bytes on one final line: Unicode, a quote, a backslash and a control character per 6 bytes.
        let fixture = try makeFixture(#"i=0; while [ $i -lt 12000 ]; do printf 'é"\\\001x'; i=$((i+1)); done"#, task: "long")
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try await TaskCommands.runTask("long", fixture.context)
        let events = EventLog(paths: fixture.paths).read()
        let terminals = TaskResults.terminals(in: events)
        #expect(terminals.map(\.outcome) == [.done])
        let record = try #require(terminals.first?.event)
        let log = try #require(record.refs["file"])
        #expect(record.refs["run"] == URL(fileURLWithPath: log).deletingPathExtension().lastPathComponent)
        #expect(try Data(contentsOf: URL(fileURLWithPath: log)).count == 72_000)
        #expect(record.detail?.hasPrefix("…") == true && record.detail?.hasSuffix("x") == true)
        #expect((record.detail?.utf8.count ?? .max) <= 4_100)
        #expect(TaskResults.latest(in: events) == ["long": "done"])
        #expect(try TaskRunJournal(paths: fixture.paths, task: "long").pending().isEmpty)
    }

    @MainActor @Test func cancellationRecordsOneCancelledOutcome() async throws {
        let fixture = try makeFixture("printf started > \"$PWD/started\"; exec /bin/sleep 30", task: "cancel")
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let operation = Task { try await TaskCommands.runTask("cancel", fixture.context) }
        let marker = fixture.paths.summonHome.appendingPathComponent("started")
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        let terminals = TaskResults.terminals(in: EventLog(paths: fixture.paths).read())
        #expect(terminals.map(\.outcome) == [.cancelled])
        #expect(terminals.first?.event.title == "Task cancelled: Fixture")
        let log = try #require(terminals.first?.event.refs["file"])
        #expect(try String(contentsOfFile: log, encoding: .utf8).contains("summon: cancelled"))
    }

    @MainActor @Test func aKilledRunIsRecordedOnceAsInterruptedByTheNextRun() async throws {
        let fixture = try makeFixture("printf ok", task: "recover")
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let journal = TaskRunJournal(paths: fixture.paths, task: "recover")
        let lost = UUID().uuidString
        let lostLog = fixture.paths.taskLogs.appendingPathComponent("recover/\(lost).log")
        try FileManager.default.createDirectory(at: lostLog.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("partial output".utf8).write(to: lostLog)
        try journal.begin(TaskRunMarker(run: lost, task: "recover", name: "Fixture", file: lostLog.path))
        try await TaskCommands.runTask("recover", fixture.context)
        try await TaskCommands.runTask("recover", fixture.context)
        let events = EventLog(paths: fixture.paths).read()
        let terminals = TaskResults.terminals(in: events)
        #expect(terminals.map(\.outcome) == [.interrupted, .done, .done])
        #expect(terminals.first?.run == lost)
        #expect(Set(terminals.compactMap(\.run)).count == 3)
        #expect(try journal.pending().isEmpty)
        #expect(TaskResults.latest(in: events) == ["recover": "done"])
        #expect(try String(contentsOf: lostLog, encoding: .utf8).contains("Task interrupted"))
    }

    @MainActor @Test func committedRunWithLeftoverMarkerIsNotRecoveredAsInterrupted() async throws {
        let fixture = try makeFixture("printf ok", task: "committed")
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let journal = TaskRunJournal(paths: fixture.paths, task: "committed")
        let run = UUID().uuidString
        let log = fixture.paths.taskLogs.appendingPathComponent("committed/\(run).log")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("finished output".utf8).write(to: log)
        try journal.begin(TaskRunMarker(run: run, task: "committed", name: "Fixture", file: log.path))
        try EventLog(paths: fixture.paths).append(TaskRunRecord(run: run, task: "committed", name: "Fixture",
                                                             outcome: .done, started: true, logFile: log).event())
        try await TaskCommands.runTask("committed", fixture.context)
        let records = TaskResults.terminals(in: EventLog(paths: fixture.paths).read())
        #expect(records.map(\.outcome) == [.done, .done])
        #expect(records.filter { $0.run == run }.count == 1)
        #expect(try journal.pending().isEmpty)
        #expect(try String(contentsOf: log, encoding: .utf8) == "finished output")
    }

    @MainActor @Test func cancelledCheckpointRemainsCancelledBeforeAgentStarts() async throws {
        let probe = NotificationProbe()
        let fixture = try makeFixture("printf agent > \"$PWD/agent-started\"", task: "checkpoint-cancel",
                                      runner: { _, _ in
            await probe.record("checkpoint")
            try await Task.sleep(for: .seconds(30))
            return ""
        })
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let bin = fixture.home.appendingPathComponent("bin")
        let locator = ToolLocator(searchPath: [bin.path], isExecutable: { $0.hasSuffix("/claude") || $0.hasSuffix("/macctl") })
        let context = Context(paths: fixture.paths, runner: fixture.context.runner, tools: locator)
        let running = Task { try await TaskCommands.runTask("checkpoint-cancel", context) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await probe.paths.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await probe.paths == ["checkpoint"])
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        #expect(TaskResults.terminals(in: EventLog(paths: fixture.paths).read()).map(\.outcome) == [.cancelled])
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.summonHome.appendingPathComponent("agent-started").path))
    }

    @MainActor @Test func aPreflightFailureReplacesAnEarlierSuccessWithItsOwnRun() async throws {
        let fixture = try makeFixture("printf ok", task: "missing")
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try EventLog(paths: fixture.paths).append(LoggedEvent(kind: EventKind.taskDone, title: "Task done: Fixture",
                                                              refs: ["task": "missing", "run": "EARLIER", "outcome": "done"]))
        let uninstalled = Context(paths: fixture.paths, runner: { _, _ in "" }, tools: ToolLocator(searchPath: [], isExecutable: { _ in false }))
        await #expect(throws: CLIError.self) { try await TaskCommands.runTask("missing", uninstalled) }
        let latest = try #require(TaskResults.latestRuns(in: EventLog(paths: fixture.paths).read())["missing"])
        #expect(latest.outcome == .failed)
        #expect(latest.event.title == "Task stopped: Fixture")
        let log = try #require(latest.event.refs["file"])
        #expect(latest.run == URL(fileURLWithPath: log).deletingPathExtension().lastPathComponent)
        #expect(try String(contentsOfFile: log, encoding: .utf8).contains("not installed"))
    }

    @MainActor @Test func anUnrecordableSuccessIsReportedDistinctlyAndStillAnnounced() async throws {
        let calls = NotificationProbe()
        let fixture = try makeFixture("printf 'All good'", task: "unrecorded", runner: { path, _ in
            await calls.record(path)
            return ""
        })
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        // The app is running, but it can only announce what reaches the event log.
        try AppHealthStore(paths: fixture.paths).save(AppHealth(pid: getpid(), hotkeys: [:], notifications: "authorized"))
        try FileManager.default.createDirectory(at: fixture.paths.eventLogFile, withIntermediateDirectories: true)
        do {
            try await TaskCommands.runTask("unrecorded", fixture.context)
            Issue.record("An unrecorded result must not look like a recorded success")
        } catch let error as CLIError {
            #expect(error.message.contains("succeeded"))
            #expect(error.message.contains("could not be recorded"))
        }
        #expect(await calls.paths.contains("/usr/bin/osascript"))
        // The outcome was known, so no later run replays it as interrupted.
        #expect(try TaskRunJournal(paths: fixture.paths, task: "unrecorded").pending().isEmpty)
        let logs = try FileManager.default.contentsOfDirectory(atPath: fixture.paths.taskLogs.appendingPathComponent("unrecorded").path)
        #expect(logs.count == 1)
    }

    @MainActor @Test func slowNotificationRunsAfterTheLeaseAndIsBounded() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let lease = TaskRunLease.file(SummonPaths(home: home), task: "slow")
        let calls = NotificationProbe()
        let fixture = try makeFixture("printf ok", task: "slow", home: home, runner: { path, _ in
            guard path == "/usr/bin/osascript" else { return "" }
            // The next run must be able to start while the banner is still being delivered.
            await calls.leaseFree((try? FileLease.acquireSync(lease, timeout: 0)) != nil)
            try await Task.sleep(for: .seconds(30))
            return ""
        })
        let began = ContinuousClock.now
        try await TaskCommands.runTask("slow", fixture.context, notificationDeadline: .milliseconds(200))
        #expect(began.duration(to: .now) < .seconds(10))
        #expect(await calls.leaseWasFree == true)
        #expect(TaskResults.terminals(in: EventLog(paths: fixture.paths).read()).map(\.outcome) == [.done])
    }

    @MainActor @Test func aFailedNotificationNeverChangesASuccess() async throws {
        let fixture = try makeFixture("printf ok", task: "quiet", runner: { path, _ in
            if path == "/usr/bin/osascript" { throw RunnerError.failed(path: path, status: 1, output: "denied") }
            return ""
        })
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try await TaskCommands.runTask("quiet", fixture.context)
        #expect(TaskResults.terminals(in: EventLog(paths: fixture.paths).read()).map(\.outcome) == [.done])
    }

    /// A task whose agent is a local shell script; nothing real is invoked.
    private func makeFixture(_ script: String, task id: String,
                             home: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                             runner: @escaping Runner = { _, _ in "" }) throws -> (home: URL, paths: SummonPaths, context: Context) {
        let paths = SummonPaths(home: home)
        let bin = home.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let agent = bin.appendingPathComponent("claude")
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: agent)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: agent.path)
        let agentPath = agent.path
        let locator = ToolLocator(searchPath: [bin.path], isExecutable: { $0 == agentPath })
        try TaskStore(paths: paths).save([RecurringTask(id: id, name: "Fixture", prompt: "local test", agent: "claude", schedule: .init(kind: .daily))])
        return (home, paths, Context(paths: paths, runner: runner, tools: locator))
    }
}

private actor FixtureScheduler {
    var bootstrapping = false
    var installed = false
    func run(_ arguments: [String]) async throws -> String {
        if arguments.first == "bootstrap" {
            bootstrapping = true
            try await Task.sleep(for: .milliseconds(150))
            installed = true
        } else if arguments.first == "bootout" { installed = false }
        return ""
    }
}

private actor NotificationProbe {
    var paths: [String] = []
    var leaseWasFree: Bool?
    func record(_ path: String) { paths.append(path) }
    func leaseFree(_ free: Bool) { leaseWasFree = free }
}
