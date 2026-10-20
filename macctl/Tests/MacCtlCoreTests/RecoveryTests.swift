import Foundation
import Testing
@testable import MacCtlCore

private actor RecoverableBackend: SettingBackend {
    var values: [String: Value] = ["dock.tilesize": .int(64)]
    var failingID: String?
    var active = 0
    var maximumActive = 0
    let delay: Duration

    init(delay: Duration = .zero) { self.delay = delay }
    func fail(_ id: String?) { failingID = id }
    func read(_ setting: Setting) async throws -> Value? { values[setting.id] }
    func write(_ value: Value, for setting: Setting) async throws {
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: delay)
        if failingID == setting.id {
            throw MacCtlError.commandFailed(command: "fake write", exitCode: 1, stderr: "injected failure")
        }
        values[setting.id] = value
    }
    func reset(_ setting: Setting) async throws {
        if failingID == setting.id {
            throw MacCtlError.commandFailed(command: "fake reset", exitCode: 1, stderr: "injected failure")
        }
        values[setting.id] = nil
    }
}

private actor FailingRestarter: Restarter {
    private(set) var calls = 0
    func run(_ effects: Set<SideEffect>) async throws {
        calls += 1
        throw MacCtlError.commandFailed(command: "fake restart", exitCode: 1, stderr: "injected restart failure")
    }
}

@Suite("Recovery and concurrent mutations")
struct RecoveryTests {
    private func engine(_ backend: RecoverableBackend, _ store: any SnapshotStore) -> Engine {
        Engine(registry: Registry(TestCatalog.settings), backend: backend, restarter: FakeRestarter(),
               probe: FakeProbe(), snapshots: store, osVersion: { "26.0" },
               now: { Date(timeIntervalSince1970: 1_792_154_096) })
    }

    @Test func failedUndoRemainsRetryable() async throws {
        let backend = RecoverableBackend()
        let store = InMemorySnapshotStore()
        let service = engine(backend, store)
        _ = try await service.apply(Profile(name: "change", settings: ["dock.tilesize": .int(40)]),
                                    dryRun: false, confirmed: false)
        await backend.fail("dock.tilesize")
        do {
            _ = try await service.undo(snapshotID: nil)
            Issue.record("Expected injected restore failure")
        } catch {}
        await backend.fail(nil)
        _ = try await service.undo(snapshotID: nil)
        #expect(await backend.values["dock.tilesize"] == .int(64))
    }

    @Test func failedBatchReportsRecoverySnapshot() async throws {
        let backend = RecoverableBackend()
        let store = InMemorySnapshotStore()
        let service = engine(backend, store)
        await backend.fail("dock.tilesize")
        do {
            _ = try await service.apply(Profile(name: "partial", settings: [
                "dock.autohide": .bool(true), "dock.tilesize": .int(40),
            ]), dryRun: false, confirmed: false)
            Issue.record("Expected injected write failure")
        } catch {
            let backup = try #require(store.saved.first)
            #expect(String(describing: error).contains(backup.id))
            #expect(String(describing: error).contains("dock.autohide"))
        }
        #expect(await backend.values["dock.autohide"] == .bool(true))
        await backend.fail(nil)
        _ = try await service.undo(snapshotID: nil)
        #expect(await backend.values["dock.autohide"] == nil)
    }

    @Test func independentEnginesSerializePlanningAndKeepBothBackups() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let backend = RecoverableBackend(delay: .milliseconds(100))
        let first = engine(backend, FileSnapshotStore(directory: folder))
        let second = engine(backend, FileSnapshotStore(directory: folder))
        async let a = first.apply(Profile(name: "first", settings: ["dock.tilesize": .int(40)]),
                                  dryRun: false, confirmed: false)
        async let b = second.apply(Profile(name: "second", settings: ["dock.tilesize": .int(30)]),
                                   dryRun: false, confirmed: false)
        _ = try await (a, b)
        #expect(await backend.maximumActive == 1)
        let backups = try FileSnapshotStore(directory: folder).list().reversed()
        #expect(backups.count == 2)
        let changes = backups.flatMap(\.changes)
        #expect(changes.first?.from == .int(64))
        #expect(changes.last?.from == changes.first?.to)
    }

    @Test func duplicateSnapshotCannotOverwriteOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-exclusive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileSnapshotStore(directory: folder)
        let original = Snapshot(id: "same", createdAt: Date(timeIntervalSince1970: 1_792_154_096), changes: [
            Change(id: "dock.tilesize", from: .int(64), to: .int(40)),
        ])
        try store.save(original)
        #expect(throws: (any Error).self) {
            try store.save(Snapshot(id: "same", createdAt: Date(), changes: []))
        }
        #expect(try store.load(id: "same") == original)
    }

    @Test func lockIsVisibleToOtherProcessesAndReleased() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-process-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileSnapshotStore(directory: folder)
        let lease = try await store.acquireTransaction()
        defer { lease.release() }
        // A separate process probes the kernel lock without touching any real preference or setting.
        let script = """
        import fcntl, sys
        with open(sys.argv[1], 'r+') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                print('acquired')
            except BlockingIOError:
                print('blocked')
        """
        let runner = ProcessRunner.live(timeout: .seconds(5))
        let arguments = ["-c", script, folder.appendingPathComponent(".transaction.lock").path]
        let blocked = try await runner("/usr/bin/python3", arguments)
        #expect(blocked.exitCode == 0)
        #expect(blocked.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "blocked")
        lease.release()
        let acquired = try await runner("/usr/bin/python3", arguments)
        #expect(acquired.exitCode == 0)
        #expect(acquired.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "acquired")
    }

    @Test func lockWaitCanBeCancelledWithoutLeakingLease() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-cancel-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileSnapshotStore(directory: folder)
        let held = try await store.acquireTransaction()
        defer { held.release() }
        let waiter = Task { try await store.acquireTransaction() }
        waiter.cancel()
        do {
            let unexpected = try await waiter.value
            unexpected.release()
            Issue.record("Cancelled waiter acquired the lock")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        held.release()
        let next = try await store.acquireTransaction()
        next.release()
    }

    @Test func legacySnapshotsDecodeAsCompleted() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(Snapshot.self, from: Data("""
        {"id":"old","createdAt":"2026-10-16T12:34:56Z","changes":[
          {"id":"dock.tilesize","from":64,"to":40}
        ]}
        """.utf8))
        #expect(old.completed)
        #expect(old.status == nil)
        #expect(old.changes.first?.wallpaperBefore == nil)
    }

    @Test func restartFailureDoesNotRunTheSameBatchTwice() async throws {
        let backend = RecoverableBackend()
        let restarter = FailingRestarter()
        let store = InMemorySnapshotStore()
        let service = Engine(registry: Registry(TestCatalog.settings), backend: backend, restarter: restarter,
                             probe: FakeProbe(), snapshots: store, osVersion: { "26.0" })
        do {
            _ = try await service.apply(Profile(name: "change", settings: ["dock.tilesize": .int(40)]),
                                        dryRun: false, confirmed: false)
            Issue.record("Expected restart failure")
        } catch {}
        #expect(await restarter.calls == 1)
        #expect(store.saved.first?.status == .failed)
        #expect(store.saved.first?.appliedSettings == ["dock.tilesize"])
    }

    @Test func interruptedUndoAndAlreadyRestoredValueDoNotBlockOlderHistory() async throws {
        let backend = RecoverableBackend()
        let store = InMemorySnapshotStore()
        let service = engine(backend, store)
        let first = try await service.apply(Profile(name: "first", settings: ["dock.tilesize": .int(40)]),
                                            dryRun: false, confirmed: false)
        let second = try await service.apply(Profile(name: "second", settings: ["dock.tilesize": .int(30)]),
                                             dryRun: false, confirmed: false)
        let secondID = try #require(second.snapshotID)
        // Simulate a previous process dying after recording undo intent, before changing anything.
        try store.save(Snapshot(id: "interrupted", createdAt: Date(), changes: [],
                                undoes: secondID, status: .pending))
        _ = try await service.undo(snapshotID: nil)
        #expect(await backend.values["dock.tilesize"] == .int(40))
        // If the older target was already restored externally, a no-op undo must consume it.
        try await backend.write(.int(64), for: TestCatalog.settings.first { $0.id == "dock.tilesize" }!)
        _ = try await service.undo(snapshotID: first.snapshotID)
        await expectMacCtlError("no_snapshots") { try await service.undo(snapshotID: nil) }
    }
}
