import Foundation
import Testing
@testable import MacCtlCore

/// An in-memory desktop picture. Records every path it is asked to set.
actor FakeWallpaper: WallpaperControlling {
    private(set) var current: String?
    private(set) var sets: [String] = []

    init(current: String? = nil) {
        self.current = current
    }

    func currentWallpaper() async throws -> String? {
        current
    }

    func setWallpaper(_ path: String) async throws {
        current = path
        sets.append(path)
    }
}

@Suite("Wallpaper")
struct WallpaperTests {
    static var setting: Setting {
        Catalog.all.first { $0.id == "desktop.wallpaper" }!
    }

    /// A real, empty file in a fresh temp folder (validation only checks that it exists).
    static func makeImage(_ name: String = "wall.jpg") throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macctl-wallpaper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data().write(to: file)
        return file.path
    }

    // MARK: catalog

    @Test func catalogEntry() {
        let setting = Self.setting
        #expect(setting.type == .path)
        #expect(setting.risk == .user)
        #expect(setting.after.isEmpty)
        #expect(setting.permissions.isEmpty)
        #expect(setting.backend == .wallpaper)
        #expect(setting.systemDefault == nil)
    }

    // MARK: SystemBackend

    @Test func readReturnsCurrentPathWithoutRunningTools() async throws {
        let runner = RecordingRunner()
        let fake = FakeWallpaper(current: "/Library/Desktop Pictures/Sky.heic")
        let backend = SystemBackend(runner: runner.runner, wallpaper: fake)
        let value = try await backend.read(Self.setting)
        #expect(value == .string("/Library/Desktop Pictures/Sky.heic"))
        #expect(runner.calls.isEmpty)
    }

    @Test func readWithNoScreenIsNil() async throws {
        let backend = SystemBackend(runner: RecordingRunner().runner, wallpaper: FakeWallpaper())
        let value = try await backend.read(Self.setting)
        #expect(value == nil)
    }

    @Test func writeSetsExistingFile() async throws {
        let path = try Self.makeImage()
        let fake = FakeWallpaper()
        let backend = SystemBackend(runner: RecordingRunner().runner, wallpaper: fake)
        try await backend.write(.string(path), for: Self.setting)
        #expect(await fake.sets == [path])
    }

    @Test func writeRejectsMissingFileAndFolder() async throws {
        let fake = FakeWallpaper()
        let backend = SystemBackend(runner: RecordingRunner().runner, wallpaper: fake)
        await expectMacCtlError("invalid_value") {
            try await backend.write(.string("/nonexistent/macctl/wall.jpg"), for: Self.setting)
        }
        let folder = FileManager.default.temporaryDirectory.path
        await expectMacCtlError("invalid_value") {
            try await backend.write(.string(folder), for: Self.setting)
        }
        #expect(await fake.sets.isEmpty)
    }

    @Test func resetIsUnsupported() async throws {
        let fake = FakeWallpaper(current: "/a.jpg")
        let backend = SystemBackend(runner: RecordingRunner().runner, wallpaper: fake)
        await expectMacCtlError("unsupported") { try await backend.reset(Self.setting) }
        #expect(await fake.sets.isEmpty)
    }

    // MARK: Engine

    struct Rig {
        let engine: Engine
        let wallpaper: FakeWallpaper
        let store: InMemorySnapshotStore
    }

    static func makeRig(current: String?) -> Rig {
        let wallpaper = FakeWallpaper(current: current)
        let store = InMemorySnapshotStore()
        let clock = TestClock()
        let engine = Engine(
            registry: Registry([setting]),
            backend: SystemBackend(runner: RecordingRunner().runner, wallpaper: wallpaper),
            restarter: FakeRestarter(),
            probe: FakeProbe(),
            snapshots: store,
            osVersion: { "26.0" },
            now: { clock.next() }
        )
        return Rig(engine: engine, wallpaper: wallpaper, store: store)
    }

    @Test func setThenUndoRestoresPreviousPicture() async throws {
        let old = try Self.makeImage("old.jpg")
        let new = try Self.makeImage("new.jpg")
        let rig = Self.makeRig(current: old)

        let value = try rig.engine.parse(new, for: "desktop.wallpaper")
        let applied = try await rig.engine.apply(
            Profile(name: "t", settings: ["desktop.wallpaper": value]), dryRun: false, confirmed: false)
        #expect(applied.changes == [Change(id: "desktop.wallpaper", from: .string(old), to: .string(new))])
        #expect(applied.snapshotID != nil)
        #expect(await rig.wallpaper.current == new)

        let undone = try await rig.engine.undo(snapshotID: nil)
        #expect(undone.changes == [Change(id: "desktop.wallpaper", from: .string(new), to: .string(old))])
        #expect(await rig.wallpaper.sets == [new, old])
    }

    @Test func missingFileFailsBeforeSnapshotOrWrite() async throws {
        let rig = Self.makeRig(current: "/a.jpg")
        await expectMacCtlError("invalid_value") {
            try await rig.engine.apply(
                Profile(name: "t", settings: ["desktop.wallpaper": .string("/nonexistent/macctl/wall.jpg")]),
                dryRun: false, confirmed: false)
        }
        #expect(rig.store.saved.isEmpty)
        #expect(await rig.wallpaper.sets.isEmpty)
    }

    @Test func undoSkipsPictureThatIsGoneAndMovesOn() async throws {
        let new = try Self.makeImage("new.jpg")
        let rig = Self.makeRig(current: "/nonexistent/macctl/old.jpg")
        let applied = try await rig.engine.apply(
            Profile(name: "t", settings: ["desktop.wallpaper": .string(new)]), dryRun: false, confirmed: false)
        #expect(applied.notes.contains { $0.contains("Undo cannot restore the current desktop.wallpaper") })

        let undone = try await rig.engine.undo(snapshotID: nil)
        #expect(undone.changes.isEmpty)
        #expect(undone.notes.contains { $0.contains("Could not restore desktop.wallpaper") })
        #expect(await rig.wallpaper.sets == [new])
        #expect(rig.store.saved.count == 2)  // the undo is recorded, so the next undo steps further back
        await expectMacCtlError("no_snapshots") { try await rig.engine.undo(snapshotID: nil) }
    }

    @Test func relativePathIsRejected() async throws {
        let rig = Self.makeRig(current: nil)
        await expectMacCtlError("invalid_value") { try rig.engine.parse("wall.jpg", for: "desktop.wallpaper") }
    }
}
