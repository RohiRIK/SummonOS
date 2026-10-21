import Foundation
import Testing
@testable import MacCtlCore

struct EngineTests {
    // MARK: get / parse

    @Test func getFallsBackToSystemDefault() async throws {
        let h = Harness(stored: ["dock.tilesize": .int(48)])
        #expect(try await h.engine.get("dock.tilesize") == .int(48))
        #expect(try await h.engine.get("dock.autohide") == .bool(false))
        #expect(try await h.engine.get("system.hostname") == nil)
        await expectMacCtlError("unknown_setting") { try await h.engine.get("dock.nope") }
    }

    @Test func parseUsesSettingType() async throws {
        let h = Harness()
        #expect(try h.engine.parse("yes", for: "dock.autohide") == .bool(true))
        await expectMacCtlError("invalid_value") { try h.engine.parse("500", for: "dock.tilesize") }
        await expectMacCtlError("unknown_setting") { try h.engine.parse("1", for: "nope.nope") }
    }

    // MARK: diff

    @Test func diffSkipsEqualValues() async throws {
        let h = Harness(stored: ["dock.tilesize": .int(40), "dock.autohide": .bool(false)])
        let changes = try await h.engine.diff(Profile(name: "t", settings: [
            "dock.tilesize": .int(40),
            "dock.autohide": .bool(true),
        ]))
        #expect(changes.core == [Change(id: "dock.autohide", from: .bool(false), to: .bool(true))])
    }

    @Test func diffUsesSystemDefaultWhenUnset() async throws {
        let h = Harness()
        let same = try await h.engine.diff(Profile(name: "t", settings: ["dock.autohide": .bool(false)]))
        #expect(same.isEmpty)
        let changed = try await h.engine.diff(Profile(name: "t", settings: ["dock.autohide": .bool(true)]))
        #expect(changed.core == [Change(id: "dock.autohide", from: nil, to: .bool(true))])
    }

    @Test func diffRejectsUnknownAndInvalid() async {
        let h = Harness()
        await expectMacCtlError("unknown_setting") {
            try await h.engine.diff(Profile(name: "t", settings: ["dock.nope": .bool(true)]))
        }
        await expectMacCtlError("invalid_value") {
            try await h.engine.diff(Profile(name: "t", settings: ["dock.tilesize": .int(1000)]))
        }
        await expectMacCtlError("invalid_value") {
            try await h.engine.diff(Profile(name: "t", settings: ["dock.autohide": .string("yes")]))
        }
    }

    // MARK: apply

    @Test func applyWritesSnapshotsAndRestartsEachProcessOnce() async throws {
        let h = Harness(stored: ["dock.tilesize": .int(64)])
        let result = try await h.engine.apply(Profile(name: "t", settings: [
            "dock.autohide": .bool(true),
            "dock.tilesize": .int(40),
            "finder.show-extensions": .bool(true),
        ]), dryRun: false, confirmed: false)

        let expected = [
            Change(id: "dock.autohide", from: nil, to: .bool(true)),
            Change(id: "dock.tilesize", from: .int(64), to: .int(40)),
            Change(id: "finder.show-extensions", from: nil, to: .bool(true)),
        ]
        #expect(result.changes.core == expected)
        #expect(result.dryRun == false)
        #expect(await h.backend.ops == [
            .write("dock.autohide", .bool(true)),
            .write("dock.tilesize", .int(40)),
            .write("finder.show-extensions", .bool(true)),
        ])

        // A write-once header (still `pending` on disk); the status shown comes from the journal.
        #expect(h.store.saved.map(\.status) == [.pending])
        let snapshots = try h.engine.snapshots()
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.id == result.snapshotID)
        #expect(snapshots.first?.status == .completed)
        #expect(snapshots.first?.changes.core == expected)
        #expect(result.changes.map(\.prior?.state) == [.absent, .explicit, .absent])

        // One restart per process, in name order (ADR Q-K).
        #expect(await h.restarter.calls == [[.restart(process: "Dock")], [.restart(process: "Finder")]])
    }

    @Test func applyWithNothingToChangeDoesNothing() async throws {
        let h = Harness(stored: ["dock.autohide": .bool(true)])
        let result = try await h.engine.apply(
            Profile(name: "t", settings: ["dock.autohide": .bool(true)]), dryRun: false, confirmed: false)
        #expect(result.changes.isEmpty)
        #expect(result.snapshotID == nil)
        #expect(await h.backend.ops.isEmpty)
        #expect(h.store.saved.isEmpty)
        #expect(await h.restarter.calls.isEmpty)
    }

    @Test func dryRunTouchesNothing() async throws {
        let h = Harness()
        let result = try await h.engine.apply(Profile(name: "t", settings: [
            "dock.autohide": .bool(true),
            "system.hostname": .string("box"),
        ]), dryRun: true, confirmed: false)
        #expect(result.dryRun)
        #expect(result.snapshotID == nil)
        #expect(result.changes.count == 2)
        #expect(await h.backend.ops.isEmpty)
        #expect(h.store.saved.isEmpty)
        #expect(await h.restarter.calls.isEmpty)
    }

    @Test func adminNeedsConfirmation() async throws {
        let h = Harness()
        let profile = Profile(name: "t", settings: [
            "dock.autohide": .bool(true),
            "system.hostname": .string("box"),
        ])
        await expectMacCtlError("needs_confirmation") {
            try await h.engine.apply(profile, dryRun: false, confirmed: false)
        }
        #expect(await h.backend.ops.isEmpty)
        #expect(h.store.saved.isEmpty)

        let result = try await h.engine.apply(profile, dryRun: false, confirmed: true)
        #expect(result.changes.count == 2)
        #expect(await h.backend.stored["system.hostname"] == .string("box"))
    }

    @Test func missingPermissionBlocksBeforeAnyWrite() async throws {
        let h = Harness(denied: [TestCatalog.automation])
        do {
            _ = try await h.engine.apply(Profile(name: "t", settings: [
                "appearance.mode": .string("dark"),
                "dock.autohide": .bool(true),
            ]), dryRun: false, confirmed: true)
            Issue.record("expected permissionMissing")
        } catch let error as MacCtlError {
            #expect(error == .permissionMissing(TestCatalog.automation, settingsURL: "x-apple.systempreferences:test"))
            #expect(error.exitCode == 2)
        }
        #expect(await h.backend.ops.isEmpty)
        #expect(h.store.saved.isEmpty)
        #expect(await h.restarter.calls.isEmpty)
    }

    @Test func logoutBecomesANote() async throws {
        let h = Harness()
        let result = try await h.engine.apply(
            Profile(name: "t", settings: ["keyboard.key-repeat": .int(2)]), dryRun: false, confirmed: false)
        #expect(result.notes.count == 1)
        #expect(result.notes.first?.contains("keyboard.key-repeat") == true)
        #expect(await h.restarter.calls.isEmpty)
    }

    // MARK: undo

    @Test func undoRestoresAndResetsUnsetKeys() async throws {
        let h = Harness(stored: ["dock.tilesize": .int(64)])
        let applied = try await h.engine.apply(Profile(name: "t", settings: [
            "dock.autohide": .bool(true),
            "dock.tilesize": .int(40),
        ]), dryRun: false, confirmed: false)

        let undone = try await h.engine.undo(snapshotID: nil)

        #expect(await h.backend.stored == ["dock.tilesize": .int(64)])
        let ops = await h.backend.ops
        // Newest change first.
        #expect(Array(ops.suffix(2)) == [.write("dock.tilesize", .int(64)), .reset("dock.autohide")])
        #expect(undone.changes.core == [
            Change(id: "dock.tilesize", from: .int(40), to: .int(64)),
            Change(id: "dock.autohide", from: .bool(true), to: .bool(false)),
        ])

        // Undo of a journaled session is rolled back in place (ADR Q-U): same id, now recovered.
        let snapshots = try h.engine.snapshots()
        #expect(snapshots.count == 1)
        #expect(undone.snapshotID == applied.snapshotID)
        #expect(snapshots.first?.status == .undone)

        // Side effects ran once for the apply and once for the undo.
        #expect(await h.restarter.calls == [[.restart(process: "Dock")], [.restart(process: "Dock")]])
    }

    @Test func repeatedUndoStepsBackInsteadOfToggling() async throws {
        let h = Harness(stored: ["dock.tilesize": .int(64)])
        let first = try await h.engine.apply(
            Profile(name: "a", settings: ["dock.tilesize": .int(40)]), dryRun: false, confirmed: false)
        _ = try await h.engine.apply(
            Profile(name: "b", settings: ["dock.tilesize": .int(30)]), dryRun: false, confirmed: false)

        _ = try await h.engine.undo(snapshotID: nil)
        #expect(await h.backend.stored["dock.tilesize"] == .int(40))
        let second = try await h.engine.undo(snapshotID: nil)
        #expect(await h.backend.stored["dock.tilesize"] == .int(64))
        #expect(second.snapshotID == first.snapshotID)
        #expect(try h.engine.snapshots().allSatisfy { $0.status == .undone })

        // Everything is undone: a third bare undo has nothing left.
        await expectMacCtlError("no_snapshots") { try await h.engine.undo(snapshotID: nil) }
    }

    @Test func undoByIDAndErrors() async throws {
        let h = Harness()
        await expectMacCtlError("no_snapshots") { try await h.engine.undo(snapshotID: nil) }
        await expectMacCtlError("snapshot_not_found") { try await h.engine.undo(snapshotID: "20260101-000000") }

        let applied = try await h.engine.apply(
            Profile(name: "t", settings: ["dock.tilesize": .int(30)]), dryRun: false, confirmed: false)
        let id = try #require(applied.snapshotID)
        _ = try await h.engine.undo(snapshotID: id)
        #expect(await h.backend.stored["dock.tilesize"] == nil)
    }

    // MARK: doctor

    @Test func doctorReportsPermissionsAndSnapshots() async {
        let h = Harness(denied: [TestCatalog.automation])
        let report = await h.engine.doctor()
        #expect(report.macOSVersion == "26.0")
        #expect(report.checks.count == 3)
        #expect(report.checks.contains { $0.name == "No unfinished operations" && $0.ok })
        let automation = report.checks.first { $0.name == "Automation: com.apple.systemevents" }
        #expect(automation?.ok == false)
        #expect(automation?.fixURL == "x-apple.systempreferences:test")
        #expect(report.checks.contains { $0.name == "Snapshots writable" && $0.ok })
    }
}
