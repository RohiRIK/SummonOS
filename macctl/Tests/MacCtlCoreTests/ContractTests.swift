import Foundation
import Testing
@testable import MacCtlCore

/// The recovery contract as properties, on the in-memory CFPreferences fake:
///
/// 1. Fault schedules: whatever write attempts fail (during apply, its rollback, or a later undo,
///    independently), after `macctl recover` every preference is exactly where it started: same keys,
///    same types, same values, absent keys still absent.
/// 2. `undo --dry-run` predicts the real undo: the keys it calls hand_edited or cannot_restore are
///    exactly the keys undo leaves (`partial_restore`), and it writes nothing.
/// 3. Each setting declares its guarantee (`RecoveryContract`) before any write.
@Suite("Recovery contract")
struct ContractTests {
    static let domain = JournalTests.domain
    typealias Rig = JournalTests.Rig

    /// SplitMix64, so every seed is a fixed, reproducible schedule.
    struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        mutating func bool() -> Bool { next() & 1 == 1 }
    }

    static func typed(_ type: PlistType, _ value: Value) -> TypedValue { TypedValue(type: type, value: value) }

    /// Every prior-state case on every key: absent, explicit (also of another type than the catalog's),
    /// inherited from the global domain, and inherited from the other host scope.
    static func seedPriors(_ r: Rig, _ rng: inout Rng) {
        switch rng.int(3) {
        case 0: break
        case 1: r.prefs.seed("A", typed(.bool, .bool(rng.bool())), appID: domain)
        default: r.prefs.seed("A", typed(.int, .int(1)), appID: domain)
        }
        switch rng.int(3) {
        case 0: break
        case 1: r.prefs.seed("B", typed(.int, .int(50)), appID: domain)
        default: r.prefs.seed("B", typed(.float, .double(64)), appID: domain)
        }
        if rng.bool() { r.prefs.seed("C", typed(.string, .string("old")), appID: domain) }
        switch rng.int(3) {
        case 0: break
        case 1: r.prefs.seed("SummonOSTestInherited", typed(.int, .int(3)), appID: Backend.globalDomain)
        default: r.prefs.seed("SummonOSTestInherited", typed(.int, .int(7)), appID: domain)
        }
        switch rng.int(3) {
        case 0: break
        case 1: r.prefs.seed("H", typed(.bool, .bool(false)), appID: domain, host: .currentHost)
        default: r.prefs.seed("H", typed(.bool, .bool(true)), appID: domain, host: .anyHost)
        }
    }

    /// A random non-empty batch over the five keys.
    static func batch(_ rng: inout Rng) -> [String: Value] {
        var settings: [String: Value] = [:]
        while settings.isEmpty {
            if rng.bool() { settings["t.a"] = .bool(rng.bool()) }
            if rng.bool() { settings["t.b"] = .int(16 + rng.int(100)) }
            if rng.bool() { settings["t.c"] = .string("v\(rng.int(5))") }
            if rng.bool() { settings["t.i"] = .int(rng.int(20)) }
            if rng.bool() { settings["t.h"] = .bool(rng.bool()) }
        }
        return settings
    }

    /// One or two failing write attempts out of the next `limit`.
    static func faults(_ rng: inout Rng, limit: Int) -> Set<Int> {
        var set: Set<Int> = [1 + rng.int(limit)]
        if rng.bool() { set.insert(1 + rng.int(limit)) }
        return set
    }

    /// Runs `recover` when a session is unfinished; returns whether it did.
    @discardableResult
    static func settle(_ r: Rig) async throws -> Bool {
        guard try r.engine.snapshots().contains(where: { $0.status == .pending }) else { return false }
        _ = try await r.engine.recover()
        return true
    }

    // MARK: 1. Fault schedules

    @Test(arguments: 0..<120)
    func anyFaultScheduleRecoversToTheExactStartingState(_ seed: Int) async throws {
        var rng = Rng(state: UInt64(seed) &* 7919 &+ 17)
        let r = JournalTests.rig()
        Self.seedPriors(r, &rng)
        let pre = r.prefs.contents
        let profile = Profile(name: "fault", settings: Self.batch(&rng))

        // Apply with one or two failing write attempts: in the batch itself, in its rollback, or both.
        r.prefs.failAttempts(Self.faults(&rng, limit: 2 * profile.settings.count + 1))
        var applied: String?
        do {
            applied = try await r.engine.apply(profile, dryRun: false, confirmed: true).snapshotID
        } catch let error as MacCtlError {
            #expect(error.code == "mutation_failed", "seed \(seed): \(error)")
        }
        r.prefs.failAttempts([])
        try await Self.settle(r)

        if let applied {
            // The batch is in place; now undo it with failing restores.
            r.prefs.failAttempts(Self.faults(&rng, limit: profile.settings.count + 1))
            do {
                _ = try await r.engine.undo(snapshotID: applied)
            } catch let error as MacCtlError {
                #expect(error.code == "command_failed", "seed \(seed): \(error)")
            }
            r.prefs.failAttempts([])
            if !(try await Self.settle(r)), try r.engine.snapshots().first(where: { $0.id == applied })?.status == .completed {
                _ = try await r.engine.undo(snapshotID: applied)
            }
        }

        #expect(r.prefs.contents == pre, "seed \(seed): preferences differ from the starting state")
        #expect(try r.engine.snapshots().allSatisfy { $0.status != .pending }, "seed \(seed): a session is unfinished")
        let writes = r.prefs.writes
        #expect(try await r.engine.recover().sessions.isEmpty, "seed \(seed): recover found work after settling")
        #expect(r.prefs.writes == writes)
    }

    @Test func applyFailureAndRollbackFailureAreRecoveredIndependently() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("B", Self.typed(.float, .double(64)), appID: Self.domain)
        let pre = r.prefs.contents
        // Attempts: 1 = t.a write, 2 = t.b write (fails), 3 = rollback of t.a (fails too).
        r.prefs.failAttempts([2, 3])
        await expectMacCtlError("mutation_failed") {
            try await r.engine.apply(Profile(name: "t", settings: ["t.a": .bool(true), "t.b": .int(40)]),
                                     dryRun: false, confirmed: true)
        }
        r.prefs.failAttempts([])
        #expect(r.value("A") == Self.typed(.bool, .bool(true)))  // left by the failed rollback
        await expectMacCtlError("recovery_pending") { try await r.apply(["t.c": .string("x")]) }
        let result = try await r.engine.recover()
        #expect(result.sessions.first?.reverted == ["t.a"])
        #expect(r.prefs.contents == pre)
        #expect(r.value("B") == Self.typed(.float, .double(64)))  // never touched, type kept
    }

    @Test func failedUndoRestoreIsFinishedByRecover() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("C", Self.typed(.string, .string("old")), appID: Self.domain)
        let pre = r.prefs.contents
        let id = try await r.apply(["t.a": .bool(true), "t.c": .string("new")])
        r.prefs.failAttempts([2])  // undo walks newest first: 1 = t.c restore, 2 = t.a delete (fails)
        await expectMacCtlError("command_failed") { try await r.engine.undo(snapshotID: id) }
        r.prefs.failAttempts([])
        #expect(r.value("C") == Self.typed(.string, .string("old")))
        #expect(try r.engine.snapshots().first?.status == .pending)
        _ = try await r.engine.recover()
        #expect(r.prefs.contents == pre)
        #expect(try r.engine.snapshots().first?.status == .recovered)
    }

    // MARK: 2. undo --dry-run predicts undo

    @Test func previewPredictsRestoreAndDeleteAndWritesNothing() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("B", Self.typed(.int, .int(50)), appID: Self.domain)
        r.prefs.seed("SummonOSTestInherited", Self.typed(.int, .int(3)), appID: Backend.globalDomain)
        let id = try await r.apply(["t.a": .bool(true), "t.b": .int(40), "t.i": .int(9)])
        let writes = r.prefs.writes
        let lines = try r.lines(id).count
        let preview = try await r.engine.previewUndo(snapshotID: nil, force: false)
        #expect(preview.snapshotID == id)
        let actions = Dictionary(uniqueKeysWithValues: preview.items.map { ($0.id, $0.action) })
        #expect(actions == ["t.a": .delete, "t.b": .restore, "t.i": .delete])
        #expect(preview.items.map(\.id) == ["t.i", "t.b", "t.a"])  // newest first, like undo
        #expect(preview.items.first { $0.id == "t.b" }?.restoresTo == .int(50))
        #expect(preview.wouldSucceed)
        #expect(r.prefs.writes == writes)
        #expect(try r.lines(id).count == lines)
        _ = try await r.engine.undo(snapshotID: id)
        #expect(try await r.engine.previewUndo(snapshotID: id, force: false).items.isEmpty)
    }

    @Test func previewFlagsHandEditsSensitiveAndForce() async throws {
        let r = JournalTests.rig()
        r.prefs.seed("S", Self.typed(.string, .string("/secret/old")), appID: Self.domain)
        let id = try await r.apply(["t.b": .int(40), "t.s": .string("/secret/new")])
        r.prefs.seed("B", Self.typed(.int, .int(44)), appID: Self.domain)
        let preview = try await r.engine.previewUndo(snapshotID: id, force: false)
        let actions = Dictionary(uniqueKeysWithValues: preview.items.map { ($0.id, $0.action) })
        #expect(actions == ["t.b": .handEdited, "t.s": .cannotRestore])
        #expect(!preview.wouldSucceed)
        #expect(preview.items.first { $0.id == "t.s" }?.current == nil)  // never shows a sensitive value
        let forced = try await r.engine.previewUndo(snapshotID: id, force: true)
        #expect(forced.items.first { $0.id == "t.b" }?.action == .delete)
    }

    @Test func previewRefusesWhileRecoveryIsPending() async throws {
        let r = JournalTests.rig()
        _ = try await JournalTests.crashed(r, ["t.a": .bool(true)], keep: 2)
        await expectMacCtlError("recovery_pending") { try await r.engine.previewUndo(snapshotID: nil, force: false) }
    }

    @Test(arguments: 0..<60)
    func previewAgreesWithUndo(_ seed: Int) async throws {
        var rng = Rng(state: UInt64(seed) &* 104_729 &+ 3)
        let r = JournalTests.rig()
        Self.seedPriors(r, &rng)
        guard let id = try await r.engine.apply(Profile(name: "p", settings: Self.batch(&rng)),
                                                dryRun: false, confirmed: true).snapshotID else { return }
        // Hand-edit some keys: to a third value, or back to where they started.
        for key in ["A", "B", "C"] where rng.int(3) == 0 {
            r.prefs.seed(key, rng.bool() ? Self.typed(.string, .string("hand")) : nil, appID: Self.domain)
        }
        let preview = try await r.engine.previewUndo(snapshotID: id, force: false)
        let predicted = Set(preview.items.filter { $0.action == .handEdited || $0.action == .cannotRestore }.map(\.id))
        var flagged: Set<String> = []
        do {
            _ = try await r.engine.undo(snapshotID: id)
        } catch let MacCtlError.partialRestore(_, keys) {
            flagged = Set(keys)
        }
        #expect(predicted == flagged, "seed \(seed): preview \(preview.items) vs undo \(flagged)")
        #expect(preview.wouldSucceed == flagged.isEmpty)
    }

    // MARK: 3. Declared guarantees and macOS gating

    @Test func everyCatalogSettingDeclaresItsRecovery() {
        for setting in Catalog.all {
            let contract = setting.recovery
            #expect(contract.verifiedByReadBack)
            switch setting.backend {
            case .defaults:
                #expect(contract.restore == (setting.sensitive ? .compareOnly : .exact), "\(setting.id)")
                #expect(contract.priorStates == [.absent, .explicit, .inherited])
            case .appleScript: #expect(contract.restore == .value, "\(setting.id)")
            case .wallpaper: #expect(contract.restore == .conditional, "\(setting.id)")
            }
            for case .restart(let process) in setting.after {
                #expect(contract.notUndone.contains { $0.hasPrefix("restart:\(process)") }, "\(setting.id)")
            }
        }
        let location = Catalog.all.first { $0.id == "screenshots.location" }
        #expect(location?.recovery.notUndone.contains { $0.hasPrefix("creates-folder") } == true)
    }

    @Test func dryRunStatesWhatUndoCannotTakeBack() async throws {
        let h = Harness()
        let result = try await h.engine.apply(
            Profile(name: "t", settings: ["keyboard.key-repeat": .int(2), "appearance.mode": .string("dark")]),
            dryRun: true, confirmed: false)
        #expect(result.notes.contains { $0.hasPrefix("keyboard.key-repeat: not undone: logout") })
        #expect(result.notes.contains { $0.hasPrefix("appearance.mode: undo is value") })
    }

    static let future = Setting(
        id: "t.future", summary: "macOS 27 only", type: .bool,
        backend: .defaults(domain: domain, key: "F", type: .bool), minimumOS: "27.0")

    static func engine(os: String, prefs: MemoryPreferencesStore) -> Engine {
        let clock = TestClock()
        return Engine(registry: Registry([future]),
                      backend: SystemBackend(runner: RecordingRunner().runner, preferences: prefs),
                      restarter: FakeRestarter(), probe: FakeProbe(), snapshots: InMemorySnapshotStore(),
                      journal: MemoryJournalStore(), osVersion: { os }, now: { clock.next() })
    }

    @Test func settingNewerThanThisMacIsRefusedBeforeAnyWrite() async throws {
        let prefs = MemoryPreferencesStore()
        let old = Self.engine(os: "26.6.2", prefs: prefs)
        let profile = Profile(name: "t", settings: ["t.future": .bool(true)])
        await expectMacCtlError("unsupported") { try await old.apply(profile, dryRun: false, confirmed: true) }
        await expectMacCtlError("unsupported") { try await old.diff(profile) }
        #expect(prefs.writes == 0)
        let new = Self.engine(os: "27.1", prefs: prefs)
        #expect(try await new.apply(profile, dryRun: false, confirmed: true).changes.count == 1)
    }

    @Test func osVersionsCompareNumerically() {
        #expect(OSVersion("26.10")! > OSVersion("26.9")!)
        #expect(OSVersion("27")! == OSVersion("27.0")!)
        #expect(!(OSVersion("27.0")! < OSVersion("27")!))
        #expect(OSVersion("27.beta") == nil)
        #expect(Self.future.isAvailable(on: "27.0.1"))
        #expect(!Self.future.isAvailable(on: "15.7"))
        #expect(Self.future.isAvailable(on: "unknown"))
    }
}

@Suite("macctl discover")
struct DiscoveryTests {
    static let domain = "com.summonos.test.discover"

    @Test func diffListsAddedChangedAndRemovedKeysWithTypes() {
        let prefs = MemoryPreferencesStore()
        prefs.seed("Glass", TypedValue(type: .float, value: .double(0.5)), appID: Self.domain)
        prefs.seed("Old", TypedValue(type: .bool, value: .bool(true)), appID: Self.domain)
        prefs.seed("Same", TypedValue(type: .int, value: .int(1)), appID: Self.domain)
        let before = Discovery.capture(prefs, domains: [Self.domain], macOSVersion: "27.0")

        prefs.seed("Glass", TypedValue(type: .float, value: .double(0.8)), appID: Self.domain)
        prefs.seed("Old", nil, appID: Self.domain)
        prefs.seed("New", TypedValue(type: .string, value: .string("x")), appID: Self.domain, host: .currentHost)
        prefs.seed("Blob", TypedValue(type: .data, value: .data(Data([1]))), appID: Self.domain)
        let after = Discovery.capture(prefs, domains: [Self.domain], macOSVersion: "27.0")

        let report = Discovery.diff(before, after)
        let byKey = Dictionary(uniqueKeysWithValues: report.changes.map { ($0.key, $0) })
        #expect(Set(byKey.keys) == ["Glass", "Old", "New", "Blob"])
        #expect(byKey["Glass"]?.kind == .changed)
        #expect(byKey["Glass"]?.after == TypedValue(type: .float, value: .double(0.8)))
        #expect(byKey["Old"]?.kind == .removed)
        #expect(byKey["New"]?.kind == .added)
        #expect(byKey["New"]?.host == .currentHost)
        #expect(byKey["Glass"]?.suggestion?.contains("key: \"Glass\", type: .float") == true)
        #expect(byKey["New"]?.suggestion?.contains("scope: .currentHost") == true)
        #expect(byKey["Blob"]?.suggestion == nil)
    }

    @Test func typeChangeAloneCounts() {
        let prefs = MemoryPreferencesStore()
        prefs.seed("K", TypedValue(type: .int, value: .int(1)), appID: Self.domain)
        let before = Discovery.capture(prefs, domains: [Self.domain], macOSVersion: "27.0")
        prefs.seed("K", TypedValue(type: .bool, value: .bool(true)), appID: Self.domain)
        let report = Discovery.diff(before, Discovery.capture(prefs, domains: [Self.domain], macOSVersion: "27.0"))
        #expect(report.changes.map(\.kind) == [.changed])
    }

    @Test func baselineIsPrivateAndRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-discover-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DiscoveryStore(file: root.appendingPathComponent("discover/baseline.json"))
        let prefs = MemoryPreferencesStore()
        prefs.seed("A", TypedValue(type: .array, value: .array([.int(1), .double(2.5)])), appID: Self.domain)
        let baseline = Discovery.capture(prefs, domains: [Self.domain], macOSVersion: "27.0",
                                         now: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(baseline)
        #expect(try store.load() == baseline)
        let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(throws: MacCtlError.self) { try DiscoveryStore(file: root.appendingPathComponent("none.json")).load() }
    }
}
