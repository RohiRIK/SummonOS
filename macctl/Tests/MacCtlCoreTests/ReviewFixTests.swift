import Foundation
import Testing
@testable import MacCtlCore

/// Sam's security review of #62: journal ids, the HMAC key, index-less intents.
@Suite("Security review fixes (#62)")
struct ReviewFixTests {
    /// An engine on real file stores in a temp dir: `<tmp>/snapshots`, `<tmp>/journal`.
    static func fileEngine() throws -> (Engine, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let engine = Engine(registry: Registry(JournalTests.settings),
                            backend: SystemBackend(runner: RecordingRunner().runner, preferences: MemoryPreferencesStore()),
                            restarter: FakeRestarter(), probe: FakeProbe(),
                            snapshots: FileSnapshotStore(directory: root.appendingPathComponent("snapshots")),
                            osVersion: { "26.0" })
        return (engine, root)
    }

    @Test func undoRefusesAJournalIDOutsideTheJournalDirectory() async throws {
        let (engine, root) = try Self.fileEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("x.jsonl")  // journal/../x.jsonl
        let bytes = Data(#"{"v":1,"seq":1,"op":"session_start","ts":"2026-10-20T00:00:00Z"}"#.utf8)  // no \n: "torn"
        try bytes.write(to: outside)
        await #expect(throws: MacCtlError.snapshotNotFound("../x")) { _ = try await engine.undo(snapshotID: "../x", force: false) }
        #expect(try Data(contentsOf: outside) == bytes)
    }

    @Test func abandonRefusesAJournalIDOutsideTheJournalDirectory() async throws {
        let (engine, root) = try Self.fileEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("x.jsonl")
        let bytes = Data("not a journal\nat all\n".utf8)
        try bytes.write(to: outside)
        await #expect(throws: MacCtlError.snapshotNotFound("../x")) { _ = try await engine.recover(force: false, abandon: "../x") }
        #expect(try Data(contentsOf: outside) == bytes)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("x.jsonl.corrupt").path))
    }

    @Test func journalStoreRejectsUnsafeIDsAtEveryEntryPoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileJournalStore(directory: root.appendingPathComponent("journal"))
        for id in ["../x", "a/b", "", ".key", "x.jsonl"] {
            #expect(throws: MacCtlError.snapshotNotFound(id)) { _ = try store.create(id) }
            #expect(throws: MacCtlError.snapshotNotFound(id)) { _ = try store.contents(id) }
            #expect(throws: MacCtlError.snapshotNotFound(id)) { _ = try store.openForAppend(id) }
            #expect(throws: MacCtlError.snapshotNotFound(id)) { try store.remove(id) }
            #expect(throws: MacCtlError.snapshotNotFound(id)) { try store.quarantine(id) }
            #expect(!store.isQuarantined(id))
        }
    }

    @Test func emptyHMACKeyLeftByAKillIsReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(".key")
        FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        let store = FileJournalStore(directory: directory)
        let key = try store.hmacKey()
        #expect(key.count == 32)
        #expect(try Data(contentsOf: file) == key)
        #expect(try store.hmacKey() == key)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test func sensitiveApplyWorksAfterAnEmptyKey() async throws {
        let (engine, root) = try Self.fileEngine()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: directory.appendingPathComponent(".key").path, contents: Data())
        let result = try await engine.apply(Profile(name: "t", settings: ["t.s": .string("/tmp/secret")]), dryRun: false, confirmed: true)
        #expect(result.snapshotID != nil)
    }

    @Test func intentWithoutIndexStillRecovers() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("B", JournalTests.typed(.int, .int(50)), appID: JournalTests.domain)
        let id = try await r.apply(["t.b": .int(40)])
        var records = try r.lines(id)
        records.removeAll { $0.op == .sessionEnd }
        for i in records.indices where records[i].op == .intent { records[i].index = nil }
        r.journal.setRaw(id, try records.reduce(into: Data()) { $0 += try JournalCodec.line($1) })
        let result = try await r.engine.recover()
        #expect(result.sessions.first?.reverted == ["t.b"])
        #expect(r.value("B") == JournalTests.typed(.int, .int(50)))
    }

    /// Open decision: a read-back that returns a third value is revert_flagged by the rollback,
    /// never overwritten; the other changes roll back to prior.
    @Test func thirdValueOnReadBackIsFlaggedNotOverwritten() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("B", JournalTests.typed(.int, .int(50)), appID: JournalTests.domain)
        r.prefs.landWrites("C", as: JournalTests.typed(.string, .string("third")), appID: JournalTests.domain)
        await expectMacCtlError("mutation_failed") {
            _ = try await r.engine.apply(Profile(name: "t", settings: ["t.b": .int(40), "t.c": .string("new")]),
                                         dryRun: false, confirmed: true)
        }
        #expect(r.value("B") == JournalTests.typed(.int, .int(50)))
        #expect(r.value("C") == JournalTests.typed(.string, .string("third")))
        let id = try #require(r.journal.ids().first)
        let ops = try r.lines(id).map(\.op)
        #expect(ops.contains(.revertFlagged))
        #expect(try r.lines(id).last?.outcome == "rolled_back")
    }

    /// Max #62 Required 1: a restore is read back; one that does not take is revert_flagged.
    @Test func restoreThatDoesNotTakeIsFlaggedNotReverted() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("B", JournalTests.typed(.int, .int(50)), appID: JournalTests.domain)
        let id = try await r.apply(["t.b": .int(40)])
        r.prefs.landWrites("B", as: JournalTests.typed(.int, .int(77)), appID: JournalTests.domain)
        await expectMacCtlError("partial_restore") { _ = try await r.engine.undo(snapshotID: id, force: false) }
        #expect(r.value("B") == JournalTests.typed(.int, .int(77)))
        let flagged = try r.lines(id).filter { $0.op == .revertFlagged }
        #expect(flagged.count == 1)
        #expect(flagged.first?.reason == "restore did not take")
        #expect(flagged.first?.observed?.value == JournalTests.typed(.int, .int(77)))
        #expect(!(try r.lines(id).contains { $0.op == .reverted }))
    }

    /// Max #62 Required 2: a legacy `failed` snapshot neither gates writes nor is rolled back by
    /// recover; it is listed by doctor and still undoable by id.
    @Test func legacyFailedSnapshotDoesNotGateAndIsNotRecovered() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("B", JournalTests.typed(.int, .int(40)), appID: JournalTests.domain)  // partial write kept
        let legacy = Snapshot(id: "20261001-120000", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                              changes: [Change(id: "t.b", from: .int(64), to: .int(40))], status: .failed)
        try r.store.save(legacy)
        let recovered = try await r.engine.recover()
        #expect(recovered.sessions.isEmpty)
        #expect(r.value("B") == JournalTests.typed(.int, .int(40)))
        _ = try await r.apply(["t.c": .string("y")])  // no recovery_pending
        let doctor = await r.engine.doctor()
        #expect(doctor.checks.contains { $0.name == "No unfinished operations" && $0.ok })
        #expect(doctor.checks.contains { $0.name == "Older failed operations" && $0.detail.contains(legacy.id) })
        #expect(r.store.saved.first { $0.id == legacy.id } == legacy)
    }
}

