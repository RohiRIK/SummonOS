import Foundation
import Testing
@testable import MacCtlCore

/// ADR D3 unit rows on the in-memory CFPreferences fake (Linux and macOS). Domains follow test mode's
/// rule (`com.summonos.test.`); nothing here touches real preferences.
@Suite("Journal and recovery (ADR D3)")
struct JournalTests {
    static let domain = "com.summonos.test.unit"

    static let settings: [Setting] = [
        Setting(id: "t.a", summary: "bool", type: .bool,
                backend: .defaults(domain: domain, key: "A", type: .bool), after: [.restart(process: "Dock")],
                systemDefault: .bool(false)),
        Setting(id: "t.b", summary: "int", type: .int(min: 0, max: 200),
                backend: .defaults(domain: domain, key: "B", type: .int), after: [.restart(process: "Dock")]),
        Setting(id: "t.c", summary: "string", type: .string,
                backend: .defaults(domain: domain, key: "C", type: .string)),
        Setting(id: "t.h", summary: "currentHost bool", type: .bool,
                backend: .defaults(domain: domain, key: "H", type: .bool), scope: .currentHost),
        Setting(id: "t.i", summary: "inherited int", type: .int(min: 0, max: 100),
                backend: .defaults(domain: domain, key: "SummonOSTestInherited", type: .int)),
        Setting(id: "t.s", summary: "sensitive path", type: .string,
                backend: .defaults(domain: domain, key: "S", type: .string), sensitive: true),
    ]

    struct Rig {
        let engine: Engine
        let prefs: MemoryPreferencesStore
        let journal: MemoryJournalStore
        let store: InMemorySnapshotStore
        let restarter: FakeRestarter

        func value(_ key: String, host: PreferenceHost = .anyHost, appID: String = JournalTests.domain) -> TypedValue? {
            try? prefs.copyValue(key, appID: appID, host: host)
        }

        func lines(_ id: String) throws -> [JournalRecord] {
            try JournalCodec.parse(try #require(journal.raw(id)), id: id).records
        }

        func apply(_ settings: [String: Value]) async throws -> String {
            let result = try await engine.apply(Profile(name: "t", settings: settings), dryRun: false, confirmed: true)
            return try #require(result.snapshotID)
        }
    }

    static func rig() -> Rig {
        let prefs = MemoryPreferencesStore()
        let journal = MemoryJournalStore()
        let store = InMemorySnapshotStore()
        let restarter = FakeRestarter()
        let clock = TestClock()
        let engine = Engine(registry: Registry(settings),
                            backend: SystemBackend(runner: RecordingRunner().runner, preferences: prefs),
                            restarter: restarter, probe: FakeProbe(), snapshots: store, journal: journal,
                            osVersion: { "26.0" }, now: { clock.next() })
        return Rig(engine: engine, prefs: prefs, journal: journal, store: store, restarter: restarter)
    }

    static func typed(_ type: PlistType, _ value: Value) -> TypedValue { TypedValue(type: type, value: value) }

    // MARK: D3.1 round trips

    @Test func roundTripAbsent() async throws {
        let r = Self.rig()
        let id = try await r.apply(["t.a": .bool(true)])
        #expect(r.value("A") == Self.typed(.bool, .bool(true)))
        let ops = try r.lines(id).map(\.op)
        #expect(ops == [.sessionStart, .intent, .applied, .sessionEnd])
        #expect(try r.lines(id)[1].prior?.state == .absent)
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("A") == nil)
    }

    @Test func roundTripExplicitEqualToDefaultIsWrittenBackNotDeleted() async throws {
        let r = Self.rig()
        r.prefs.seed("A", Self.typed(.bool, .bool(false)), appID: Self.domain)
        _ = try await r.apply(["t.a": .bool(true)])
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("A") == Self.typed(.bool, .bool(false)))
    }

    @Test func roundTripInherited() async throws {
        let r = Self.rig()
        r.prefs.seed("SummonOSTestInherited", Self.typed(.int, .int(3)), appID: Backend.globalDomain)
        let id = try await r.apply(["t.i": .int(9)])
        let intent = try #require(try r.lines(id).first { $0.op == .intent })
        #expect(intent.prior?.state == .inherited)
        #expect(intent.prior?.layer == "global")
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("SummonOSTestInherited") == nil)
        #expect(r.value("SummonOSTestInherited", appID: Backend.globalDomain) == Self.typed(.int, .int(3)))
    }

    // MARK: D3.7 types

    @Test func typePreserved() async throws {
        let r = Self.rig()
        r.prefs.seed("A", Self.typed(.int, .int(1)), appID: Self.domain)      // int under a bool setting
        r.prefs.seed("B", Self.typed(.float, .double(64)), appID: Self.domain)  // real under an int setting (QA R-a)
        _ = try await r.apply(["t.a": .bool(false), "t.b": .int(40)])
        #expect(r.value("B") == Self.typed(.int, .int(40)))
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("A") == Self.typed(.int, .int(1)))
        #expect(r.value("B") == Self.typed(.float, .double(64)))
    }

    // MARK: D3.2 / D3.8 crash states, built as the journal a SIGKILL leaves

    /// Applies, then cuts the journal back to its first `keep` lines, as if killed there.
    static func crashed(_ r: Rig, _ settings: [String: Value], keep: Int, prefs undoWrites: Bool = false) async throws -> String {
        let id = try await r.apply(settings)
        let data = try #require(r.journal.raw(id))
        let lines = data.split(separator: 0x0a).prefix(keep)
        r.journal.setRaw(id, Data(lines.joined(separator: [0x0a])) + Data([0x0a]))
        return id
    }

    @Test func crashBetweenIntentAndWrite() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        // Killed at I1.3: intent durable, value untouched. Simulate by putting the prior back.
        let id = try await Self.crashed(r, ["t.b": .int(40)], keep: 2)
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        await expectMacCtlError("recovery_pending") { try await r.apply(["t.a": .bool(true)]) }
        let result = try await r.engine.recover()
        #expect(result.sessions.first?.notApplied == ["t.b"])
        #expect(result.changes == 0)
        #expect(r.value("B") == Self.typed(.int, .int(50)))
        #expect(try r.lines(id).suffix(2).map(\.op) == [.failed, .sessionEnd])
        #expect(try r.lines(id).last?.outcome == "recovered")
    }

    @Test func crashAfterWriteBeforeApplied() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        _ = try await Self.crashed(r, ["t.b": .int(40)], keep: 2)  // W1.2 / A1.1: value = new, no applied
        let result = try await r.engine.recover()
        #expect(result.changes == 1)
        #expect(r.value("B") == Self.typed(.int, .int(50)))
    }

    @Test func crashAtK1ClosesEmptySession() async throws {
        let r = Self.rig()
        let id = try await Self.crashed(r, ["t.a": .bool(true)], keep: 1)
        r.prefs.seed("A", nil, appID: Self.domain)
        let result = try await r.engine.recover()
        #expect(result.changes == 0)
        #expect(try r.lines(id).map(\.op) == [.sessionStart, .sessionEnd])
    }

    @Test func crashAtE1RevertsEverythingNewestFirst() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        r.prefs.seed("C", Self.typed(.string, .string("x")), appID: Self.domain)
        // K2/E1: every change applied, no session_end.
        let id = try await Self.crashed(r, ["t.a": .bool(true), "t.b": .int(40), "t.c": .string("y")], keep: 7)
        _ = try await r.engine.recover()
        #expect(r.value("A") == nil)
        #expect(r.value("B") == Self.typed(.int, .int(50)))
        #expect(r.value("C") == Self.typed(.string, .string("x")))
        let refs = try r.lines(id).filter { $0.op == .revertIntent }.compactMap(\.ref)
        #expect(refs == refs.sorted(by: >))
        #expect(refs.count == 3)
    }

    @Test func headerWithoutJournalIsAdoptedAndWritesNothing() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        // Killed at H1: the header exists, the journal does not.
        try r.store.save(Snapshot(id: "20261020-100000", createdAt: Date(timeIntervalSince1970: 1_792_154_000),
                                  changes: [Change(id: "t.b", from: .int(50), to: .int(40),
                                                   prior: PriorState(state: .explicit, value: Self.typed(.int, .int(50))),
                                                   new: RecordedValue(absent: nil, value: Self.typed(.int, .int(40)), type: .int, hmac: nil))],
                                  status: .pending))
        let before = r.prefs.writes
        let result = try await r.engine.recover()
        #expect(result.changes == 0)
        #expect(r.prefs.writes == before)
        #expect(try r.engine.snapshots().first?.status == .recovered)
        #expect(r.store.saved.first?.status == .pending)  // the header itself is never rewritten
    }

    @Test func crashAtK3NeedsNothingAndUndoStillWorks() async throws {
        let r = Self.rig()
        _ = try await r.apply(["t.a": .bool(true)])
        #expect(try await r.engine.recover().sessions.isEmpty)
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("A") == nil)
    }

    @Test func danglingRevertIntentIsResolvedByReadingBack() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        let id = try await r.apply(["t.b": .int(40)])
        _ = try await r.engine.undo(snapshotID: id)
        // Cut back to just after revert_intent (killed at RI1): the value is still the new one.
        let lines = try r.lines(id)
        let cut = try #require(lines.firstIndex { $0.op == .revertIntent })
        let data = try #require(r.journal.raw(id)).split(separator: 0x0a).prefix(cut + 1)
        r.journal.setRaw(id, Data(data.joined(separator: [0x0a])) + Data([0x0a]))
        r.prefs.seed("B", Self.typed(.int, .int(40)), appID: Self.domain)
        _ = try await r.engine.recover()
        #expect(r.value("B") == Self.typed(.int, .int(50)))
        // Exactly one revert_intent: the open one is resumed, not duplicated.
        #expect(try r.lines(id).filter { $0.op == .revertIntent }.count == 1)

        // A third value after revert_intent: revert_flagged, left alone (before-state not matched).
        let r2 = Self.rig()
        r2.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        let id2 = try await r2.apply(["t.b": .int(40)])
        _ = try await r2.engine.undo(snapshotID: id2)
        let cut2 = try #require(try r2.lines(id2).firstIndex { $0.op == .revertIntent })
        let data2 = try #require(r2.journal.raw(id2)).split(separator: 0x0a).prefix(cut2 + 1)
        r2.journal.setRaw(id2, Data(data2.joined(separator: [0x0a])) + Data([0x0a]))
        r2.prefs.seed("B", Self.typed(.int, .int(77)), appID: Self.domain)
        await expectMacCtlError("partial_restore") { try await r2.engine.recover() }
        #expect(r2.value("B") == Self.typed(.int, .int(77)))
        #expect(try r2.lines(id2).contains { $0.op == .revertFlagged })
    }

    // MARK: D3.3 torn / corrupt

    @Test func tornLastLineIgnored() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        let id = try await Self.crashed(r, ["t.b": .int(40)], keep: 3)
        r.journal.setRaw(id, try #require(r.journal.raw(id)) + Data(#"{"v":1,"seq":4,"op":"ses"#.utf8))
        _ = try await r.engine.recover()
        #expect(r.value("B") == Self.typed(.int, .int(50)))
        #expect(try r.lines(id).last?.op == .sessionEnd)
    }

    @Test func corruptMiddleLineRefuses() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        let id = try await Self.crashed(r, ["t.b": .int(40)], keep: 3)
        var lines = try #require(r.journal.raw(id)).split(separator: 0x0a).map { Data($0) }
        lines[1] = Data("garbage".utf8)
        let corrupted = Data(lines.joined(separator: [0x0a])) + Data([0x0a])
        r.journal.setRaw(id, corrupted)
        await expectMacCtlError("journal_corrupt") { try await r.engine.recover() }
        #expect(r.journal.raw(id) == corrupted)
        #expect(r.value("B") == Self.typed(.int, .int(40)))
        await expectMacCtlError("recovery_pending") { try await r.apply(["t.a": .bool(true)]) }
        // After inspection it can be set aside (bytes kept); the header no longer blocks.
        _ = try await r.engine.recover(force: false, abandon: id)
        #expect(r.journal.quarantined[id] == corrupted)
        _ = try await r.apply(["t.a": .bool(true)])
    }

    // MARK: D3.4 hand edits

    @Test func handEditAfterApplyIsFlagged() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        let id = try await r.apply(["t.a": .bool(true), "t.b": .int(40)])
        r.prefs.seed("B", Self.typed(.int, .int(44)), appID: Self.domain)
        do {
            _ = try await r.engine.undo(snapshotID: nil)
            Issue.record("expected partial_restore")
        } catch let MacCtlError.partialRestore(sid, flagged) {
            #expect(sid == id)
            #expect(flagged == ["t.b"])
        }
        #expect(r.value("B") == Self.typed(.int, .int(44)))
        #expect(r.value("A") == nil)
        let flagged = try #require(try r.lines(id).first { $0.op == .revertFlagged })
        #expect(flagged.observed?.value == Self.typed(.int, .int(44)))
        #expect(try r.engine.snapshots().first?.status == .undone)
    }

    @Test func forceOverwrites() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        let id = try await r.apply(["t.b": .int(40)])
        r.prefs.seed("B", Self.typed(.int, .int(44)), appID: Self.domain)
        await expectMacCtlError("partial_restore") { try await r.engine.undo(snapshotID: nil) }
        _ = try await r.engine.undo(snapshotID: id, force: true)
        #expect(r.value("B") == Self.typed(.int, .int(50)))
        #expect(try r.lines(id).contains { $0.op == .revertIntent && $0.forced == true })
    }

    // MARK: D3.5 / D3.6

    @Test func forcedKeyRefused() async throws {
        let r = Self.rig()
        r.prefs.force("A", Self.typed(.bool, .bool(true)), appID: Self.domain)
        await expectMacCtlError("managed_setting") { try await r.apply(["t.a": .bool(false)]) }
        #expect(r.store.saved.isEmpty)
        #expect(try r.journal.ids().isEmpty)
        #expect(r.prefs.writes == 0)
    }

    @Test func currentHostScope() async throws {
        let r = Self.rig()
        r.prefs.seed("H", Self.typed(.bool, .bool(false)), appID: Self.domain, host: .anyHost)
        _ = try await r.apply(["t.h": .bool(true)])
        #expect(r.value("H", host: .currentHost) == Self.typed(.bool, .bool(true)))
        #expect(r.value("H", host: .anyHost) == Self.typed(.bool, .bool(false)))
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("H", host: .currentHost) == nil)
        #expect(r.value("H", host: .anyHost) == Self.typed(.bool, .bool(false)))
    }

    @Test func currentHostShadowWarns() async throws {
        let r = Self.rig()
        r.prefs.seed("C", Self.typed(.string, .string("host")), appID: Self.domain, host: .currentHost)
        let result = try await r.engine.apply(Profile(name: "t", settings: ["t.c": .string("any")]), dryRun: false, confirmed: true)
        #expect(result.notes.contains { $0.contains("shadowedBy: currentHost") })
        _ = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("C", host: .currentHost) == Self.typed(.string, .string("host")))
    }

    // MARK: D3.9 failure branch

    @Test func failureRollsBackAtOnce() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        r.prefs.failWrites("B", appID: Self.domain)
        await expectMacCtlError("mutation_failed") {
            try await r.apply(["t.a": .bool(true), "t.b": .int(40), "t.c": .string("z")])
        }
        let id = try #require(try r.journal.ids().first)
        #expect(r.value("A") == nil)
        #expect(r.value("B") == Self.typed(.int, .int(50)))
        #expect(r.value("C") == nil)
        let ops = try r.lines(id).map(\.op)
        #expect(ops == [.sessionStart, .intent, .applied, .intent, .failed, .revertIntent, .reverted, .sessionEnd])
        #expect(try r.lines(id).last?.outcome == "rolled_back")
        #expect(try await r.engine.recover().sessions.isEmpty)
    }

    // MARK: D3.10 undo journal

    @Test func undoAddsOnlyRevertLinesToTheSameJournal() async throws {
        let r = Self.rig()
        let id = try await r.apply(["t.a": .bool(true), "t.c": .string("y")])
        let before = try r.lines(id).count
        _ = try await r.engine.undo(snapshotID: nil)
        let added = Set(try r.lines(id).dropFirst(before).map(\.op))
        #expect(added.isSubset(of: [.revertIntent, .reverted, .revertFlagged, .sessionEnd]))
        #expect(try r.journal.ids() == [id])
        #expect(r.store.saved.count == 1)
    }

    // MARK: D3.11 / D3.13

    @Test func recoverIsIdempotent() async throws {
        let r = Self.rig()
        let id = try await Self.crashed(r, ["t.a": .bool(true), "t.c": .string("y")], keep: 5)
        _ = try await r.engine.recover()
        let bytes = r.journal.raw(id)
        let writes = r.prefs.writes
        let second = try await r.engine.recover()
        #expect(second.sessions.isEmpty)
        #expect(r.journal.raw(id) == bytes)
        #expect(r.prefs.writes == writes)
    }

    @Test func sensitiveStoresHmacOnly() async throws {
        let r = Self.rig()
        r.prefs.seed("S", Self.typed(.string, .string("/secret/prior-path")), appID: Self.domain)
        let id = try await r.apply(["t.s": .string("/secret/new-path")])
        let text = String(decoding: try #require(r.journal.raw(id)), as: UTF8.self)
        #expect(!text.contains("prior-path"))
        #expect(!text.contains("new-path"))
        #expect(text.contains("hmac"))
        // The prior is comparable but not restorable (ADR Q2): undo flags it and leaves it.
        await expectMacCtlError("partial_restore") { try await r.engine.undo(snapshotID: nil) }
    }

    @Test func hmacMatchesRFC4231() {
        // RFC 4231 test case 2.
        let mac = HMACSHA256.hex(Data("what do ya want for nothing?".utf8), key: Data("Jefe".utf8))
        #expect(mac == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        // Test case 1.
        let key = Data(repeating: 0x0b, count: 20)
        #expect(HMACSHA256.hex(Data("Hi There".utf8), key: key)
            == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    }

    @Test func legacySnapshotStillUndoesThroughAJournaledSession() async throws {
        let r = Self.rig()
        r.prefs.seed("B", Self.typed(.int, .int(40)), appID: Self.domain)
        let legacy = Snapshot(id: "20261001-120000", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                              changes: [Change(id: "t.b", from: .int(64), to: .int(40))])
        try r.store.save(legacy)
        let result = try await r.engine.undo(snapshotID: nil)
        #expect(r.value("B") == Self.typed(.int, .int(64)))
        let id = try #require(result.snapshotID)
        #expect(id != legacy.id)
        #expect(try r.lines(id).first?.undoes == legacy.id)
        #expect(r.store.saved.first { $0.id == legacy.id } == legacy)  // read, never rewritten
        // Undoing the undo session is the old redo.
        _ = try await r.engine.undo(snapshotID: id)
        #expect(r.value("B") == Self.typed(.int, .int(40)))
    }

    // MARK: files on disk

    @Test func fileModesAndWriteOnceHeader() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-modes-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = root.appendingPathComponent("snapshots")
        let prefs = MemoryPreferencesStore()
        let engine = Engine(registry: Registry(Self.settings),
                            backend: SystemBackend(runner: RecordingRunner().runner, preferences: prefs),
                            restarter: FakeRestarter(), probe: FakeProbe(),
                            snapshots: FileSnapshotStore(directory: snapshots), osVersion: { "26.0" })
        // A stale temp left by a SIGKILL before the header link (QA R-g) is cleaned under the lock.
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: snapshots.appendingPathComponent(".snapshot-stale.tmp"))
        let id = try #require(try await engine.apply(Profile(name: "t", settings: ["t.s": .string("v"), "t.a": .bool(true)]),
                                                     dryRun: false, confirmed: true).snapshotID)
        #expect(!FileManager.default.fileExists(atPath: snapshots.appendingPathComponent(".snapshot-stale.tmp").path))
        let journal = root.appendingPathComponent("journal")
        func mode(_ url: URL) throws -> Int {
            try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        #expect(try mode(journal) == 0o700)
        #expect(try mode(journal.appendingPathComponent("\(id).jsonl")) == 0o600)
        #expect(try mode(journal.appendingPathComponent(".key")) == 0o600)
        let header = snapshots.appendingPathComponent("\(id).json")
        #expect(try mode(header) == 0o600)
        let attributes = { try FileManager.default.attributesOfItem(atPath: header.path) }
        let before = (try attributes()[.systemFileNumber] as? NSNumber, try attributes()[.modificationDate] as? Date,
                      try Data(contentsOf: header))
        _ = try await engine.undo(snapshotID: nil)
        _ = try await engine.recover()
        #expect(try attributes()[.systemFileNumber] as? NSNumber == before.0)
        #expect(try attributes()[.modificationDate] as? Date == before.1)
        #expect(try Data(contentsOf: header) == before.2)
        #expect(String(decoding: before.2, as: UTF8.self).contains("\"pending\""))
        #expect(try engine.snapshots().first?.status == .undone)
    }
}
