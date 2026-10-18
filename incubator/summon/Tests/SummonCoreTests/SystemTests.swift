import Foundation
import Testing
@testable import SummonCore

@Suite("Checkpoints, hooks, debug bundle, catalog")
struct SystemTests {
    @Test func checkpointStepsWithoutRepoOnlySnapshot() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let service = CheckpointService(paths: paths, runner: { _, _ in "" }, gitPath: "/usr/bin/git", macctlPath: "/usr/local/bin/macctl")
        let steps = service.createSteps(label: "x")
        #expect(steps == [LaunchPlan(executable: "/usr/local/bin/macctl", arguments: ["snapshot", "create", "--label", "x"])])
    }

    @Test func checkpointCommitsConfigRepoAndRecordsIt() async throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        try FileManager.default.createDirectory(at: paths.userConfig.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let log = CallLog()
        let runner = fakeRunner(log, responses: ["git": "abc123\n", "macctl": "{\"id\": \"snap-1\"}"])
        let service = CheckpointService(paths: paths, runner: runner, gitPath: "/usr/bin/git", macctlPath: "/usr/local/bin/macctl")

        let (checkpoint, problems) = await service.create(label: "agent session", now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(problems.isEmpty)
        #expect(checkpoint.configCommit == "abc123")
        #expect(checkpoint.macctlSnapshot == "snap-1")
        #expect(checkpoint.id == "20270115-080000")

        let calls = await log.calls
        #expect(calls.count == 4)
        #expect(calls[1] == ["/usr/bin/git", "-C", paths.userConfig.path, "add", "-A"])
        #expect(calls[3] == ["/usr/bin/git", "-C", paths.userConfig.path, "rev-parse", "HEAD"])

        #expect(service.list() == [checkpoint])
        #expect(service.find(nil) == checkpoint)
        #expect(service.find("20270115-080000") == checkpoint)
        #expect(service.find("nope") == nil)

        let undo = service.undoSteps(checkpoint)
        #expect(undo.count == 2)
        #expect(undo[0].arguments.contains("abc123"))
        #expect(undo[0].arguments.contains("checkout"))  // restore never deletes files the commit lacks
        #expect(undo[0].arguments.contains(":(exclude)summon/checkpoints.json"))
        #expect(undo[1].arguments == ["undo", "snap-1"])
    }

    @Test func checkpointFailuresAreReportedNotThrown() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let log = CallLog()
        let service = CheckpointService(paths: paths, runner: fakeRunner(log, responses: ["macctl": nil]), gitPath: nil, macctlPath: "/usr/local/bin/macctl")
        let (checkpoint, problems) = await service.create(label: "x")
        #expect(problems.count == 1)
        #expect(checkpoint.macctlSnapshot == nil)
        #expect(service.undoSteps(checkpoint).isEmpty)
    }

    @Test func snapshotIDFromPlainOutput() {
        #expect(CheckpointService.snapshotID(fromOutput: "Saved snapshot\n2026-10-17T20-00-00") == "2026-10-17T20-00-00")
        #expect(CheckpointService.snapshotID(fromOutput: "") == "latest")
    }

    @Test func hooksRunInNameOrderAndSkipNonExecutables() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let dir = paths.hooks.appendingPathComponent("theme-set.d")
        try writeFile("#!/bin/sh\n", to: dir.appendingPathComponent("20-b"), executable: true)
        try writeFile("#!/bin/sh\n", to: dir.appendingPathComponent("10-a"), executable: true)
        try writeFile("notes", to: dir.appendingPathComponent("README"))
        try writeFile("#!/bin/sh\n", to: dir.appendingPathComponent(".hidden"), executable: true)

        let log = CallLog()
        let runner = HookRunner(paths: paths, runner: fakeRunner(log))
        #expect(runner.scripts(for: .themeSet).map(\.lastPathComponent) == ["10-a", "20-b"])
        let failures = await runner.run(.themeSet, arguments: ["summon-night"])
        #expect(failures.isEmpty)
        let calls = await log.calls
        #expect(calls.map { ($0[0] as NSString).lastPathComponent } == ["10-a", "20-b"])
        #expect(calls.allSatisfy { $0.last == "summon-night" })
        #expect(runner.scripts(for: .wake).isEmpty)
    }

    @Test func debugBundleRecordsFailuresInPlace() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let log = CallLog()
        let bundle = DebugBundle(paths: paths, runner: fakeRunner(log, responses: ["sw_vers": "ProductVersion: 26.0", "log": nil]), brewPath: nil, macctlPath: nil)
        let text = await bundle.collect(logWindow: "30m", now: Date(timeIntervalSince1970: 0))
        #expect(text.contains("ProductVersion: 26.0"))
        #expect(text.contains("UNIFIED LOG (ERRORS, LAST 30m)"))
        #expect(text.contains("(failed:"))
        let calls = await log.calls
        #expect(calls.contains(["/usr/bin/log", "show", "--last", "30m", "--predicate", "messageType == error", "--style", "compact"]))
        #expect(!calls.contains { $0[0].hasSuffix("brew") })
    }

    @Test func truncateKeepsTheNewestLines() {
        let text = (1...10).map(String.init).joined(separator: "\n")
        let cut = DebugBundle.truncate(text, maxLines: 3)
        #expect(cut == "(7 earlier lines omitted)\n8\n9\n10\n")
        #expect(DebugBundle.truncate("a", maxLines: 3) == "a\n")
        #expect(DebugBundle.truncate("a\nb\nc\n", maxLines: 3) == "a\nb\nc\n")
    }

    @Test func catalogIsUniqueAndEncodes() throws {
        let routes = CommandCatalog.all.map(\.route)
        #expect(Set(routes).count == routes.count)
        let decoded = try JSONDecoder().decode([CommandInfo].self, from: Data(try CommandCatalog.json().utf8))
        #expect(decoded == CommandCatalog.all)
        #expect(CommandCatalog.helpText().contains("summon agent prompt"))
        #expect(CommandCatalog.find("theme set") != nil)
    }
}
