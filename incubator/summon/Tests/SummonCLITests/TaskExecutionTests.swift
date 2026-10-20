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
