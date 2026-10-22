import Foundation
import Testing
@testable import SummonCore

@Suite("Production recovery regressions")
struct RecoveryRegressionTests {
    @Test func pendingMacctlJournalCannotBecomeACheckpointMarker() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let json = #"{"ok":true,"result":[{"id":"in-flight","createdAt":"2026-10-20T07:00:00Z","status":"pending"}]}"#
        let service = CheckpointService(paths: paths, runner: { _, _ in json }, gitPath: nil, macctlPath: "/fixture/macctl")
        let (checkpoint, problems) = await service.create(label: "overlapping write")
        #expect(checkpoint.macctlSnapshot == nil)
        #expect(problems.contains { $0.contains("in-flight") })
        #expect(service.list().last?.problems?.isEmpty == false)
    }

    @Test func diagnosticsRedactKnownSensitiveFieldsAndSavePrivately() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let input = "Serial Number (system): EXAMPLE-SERIAL\nHardware UUID: EXAMPLE-UUID\nAuthorization: Bearer example-credential\napi_key=example-key\n\(home.path)/file\n00:00:5e:00:53:01\n"
        let redacted = DebugRedactor.redact(input, home: home.path)
        #expect(!redacted.contains("EXAMPLE-SERIAL"))
        #expect(!redacted.contains("EXAMPLE-UUID"))
        #expect(!redacted.contains("example-credential"))
        #expect(!redacted.contains("example-key"))
        #expect(!redacted.contains(home.path))
        #expect(!redacted.contains("00:00:5e:00:53:01"))
        let file = home.appendingPathComponent("debug.txt")
        try DebugBundle.save(redacted, to: file)
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func failedJournalsAreVisibleAsProblemsRatherThanCompletedChanges() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let json = #"{"id":"failed","createdAt":"2026-10-20T07:00:00Z","status":"failed","appliedSettings":[],"failure":"write rejected","changes":[{"id":"dock.autohide","from":false,"to":true}]}"#
        let snapshot = try decoder.decode(MacctlSnapshot.self, from: Data(json.utf8))
        let event = try #require(ActivityFeed.build(log: [], snapshots: [snapshot], checkpoints: [], crashes: []).first)
        #expect(event.category == .problem)
        #expect(event.kind == "setting.failed")
        #expect(event.detail == "write rejected")
        #expect(event.changes.isEmpty)
        #expect(ActivityLog.level(event) == .error)
    }

    @Test func failedCommitNeverAdvertisesOldHeadAsCapturedState() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        try FileManager.default.createDirectory(at: paths.userConfig.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let runner: Runner = { path, args in
            if args.contains("commit") { throw RunnerError.failed(path: path, status: 1, output: "commit rejected") }
            return args.contains("rev-parse") ? "old-head\n" : ""
        }
        let service = CheckpointService(paths: paths, runner: runner, gitPath: "/usr/bin/git", macctlPath: nil)
        let (checkpoint, problems) = await service.create(label: "failed capture")
        #expect(!problems.isEmpty)
        #expect(checkpoint.configCommit == nil)
    }

    @Test func corruptTaskStoreCannotBeOverwrittenByAMutation() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        try writeFile("{broken", to: paths.tasksFile)
        let store = TaskStore(paths: paths)
        #expect(throws: (any Error).self) { try store.save(store.load()) }
        #expect(try String(contentsOf: paths.tasksFile, encoding: .utf8) == "{broken")
    }

    @Test func shellCannotRetainUnboundedCommandOutput() throws {
        #expect(throws: RunnerError.outputLimit(path: "/bin/sh", limit: 16_777_216)) {
            _ = try Shell.runSync("/bin/sh", ["-c", "/usr/bin/head -c 20000000 /dev/zero"])
        }
    }
}
