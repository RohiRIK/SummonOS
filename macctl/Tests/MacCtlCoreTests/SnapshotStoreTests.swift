import Foundation
import Testing
@testable import MacCtlCore

struct SnapshotStoreTests {
    /// 2026-10-16 12:34:56 UTC.
    private let date = Date(timeIntervalSince1970: 1_792_154_096)
    private let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

    private func makeStore() -> (FileSnapshotStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "macctl-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return (FileSnapshotStore(directory: dir), dir)
    }

    @Test func makeIDFormat() {
        #expect(FileSnapshotStore.makeID(date: date, timeZone: utc) == "20261016-123456")
    }

    @Test func makeIDAvoidsCollisions() {
        let base = "20261016-123456"
        #expect(FileSnapshotStore.makeID(date: date, existing: [base], timeZone: utc) == "\(base)-2")
        #expect(FileSnapshotStore.makeID(date: date, existing: [base, "\(base)-2"], timeZone: utc) == "\(base)-3")
    }

    @Test func saveLoadRoundTrip() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snapshot = Snapshot(id: "20261016-123456", createdAt: date, changes: [
            Change(id: "dock.autohide", from: nil, to: .bool(true)),
            Change(id: "dock.tilesize", from: .int(64), to: .int(40)),
            Change(id: "appearance.mode", from: .string("light"), to: .string("dark")),
        ])
        try store.save(snapshot)
        #expect(try store.load(id: snapshot.id) == snapshot)

        let text = try String(contentsOf: dir.appending(path: "20261016-123456.json"), encoding: .utf8)
        #expect(text.contains("2026-10-16T12:34:56Z"))
    }

    @Test func listIsNewestFirst() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try store.list().isEmpty)

        let old = Snapshot(id: "a", createdAt: date, changes: [])
        let new = Snapshot(id: "b", createdAt: date.addingTimeInterval(60), changes: [])
        try store.save(old)
        try store.save(new)
        #expect(try store.list().map(\.id) == ["b", "a"])
    }

    @Test func sameSecondCollisionSuffixesSortNumerically() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        for id in ["20261018-040000", "20261018-040000-2", "20261018-040000-9", "20261018-040000-10"] {
            try store.save(Snapshot(id: id, createdAt: date, changes: []))
        }
        #expect(try store.list().first?.id == "20261018-040000-10")
    }

    @Test func loadMissingOrUnsafeID() async {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await expectMacCtlError("snapshot_not_found") { try store.load(id: "20990101-000000") }
        await expectMacCtlError("snapshot_not_found") { try store.load(id: "../etc/passwd") }
    }

    @Test func writableCheckCreatesDirectory() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = store.writableCheck()
        #expect(result.ok)
        #expect(FileManager.default.fileExists(atPath: dir.path(percentEncoded: false)))
    }
}
