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
}
