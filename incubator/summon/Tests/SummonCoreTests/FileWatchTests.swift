import Foundation
import Testing
@testable import SummonCore

@Suite("FileWatch: changes without polling")
struct FileWatchTests {
    @Test func missingNestedDirectoryUsesExistingAncestorUntilCreated() throws {
        let home = try makeTempHome()
        let state = home.appendingPathComponent(".local/state/summon", isDirectory: true)
        #expect(FileWatch.nearestExistingDirectory(to: state) == home)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        #expect(FileWatch.nearestExistingDirectory(to: state) == state)
    }

    @Test func reportsANewFileInAFolderAndAWriteToAFile() async throws {
        let dir = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("log.jsonl")
        try Data().write(to: file)
        let (folderChanges, folderSignal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let (fileChanges, fileSignal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        defer { folderSignal.finish(); fileSignal.finish() }
        let folder = try #require(FileWatch(dir) { folderSignal.yield(()) })
        let watch = try #require(FileWatch(file) { fileSignal.yield(()) })
        defer { withExtendedLifetime((folder, watch)) {} }

        // The initial callbacks mean kevent registration is complete. Consume both before mutating:
        // neither readiness invalidation may count as evidence that the following writes were observed.
        try await waitForWatchChange(folderChanges, "folder registration")
        try await waitForWatchChange(fileChanges, "file registration")

        try Data("x".utf8).write(to: dir.appendingPathComponent("new.ips"))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        try await waitForWatchChange(folderChanges, "new folder entry")
        try await waitForWatchChange(fileChanges, "file write")
        #expect(!watch.isGone)

        try FileManager.default.removeItem(at: file)
        // A write can yield coalesced callbacks; only the deletion event marks this watch gone.
        try await waitForWatchChange(fileChanges, "file deletion", until: { watch.isGone })
        #expect(watch.isGone, "a replaced or deleted file needs a new watch")
        #expect(FileWatch(dir.appendingPathComponent("missing")) { } == nil)
    }

    @Test @MainActor func registrationReconcilesAWriteBeforeTheConsumerIsReady() async throws {
        let dir = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("log.jsonl")
        try Data().write(to: file)
        let contents = Data("written before readiness\n".utf8)
        let (changes, signal) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        defer { signal.finish() }
        let watch = try #require(FileWatch(file, queue: .main) {
            // This models consumers reconciling disk state, not counting the initial invalidation as an event.
            if (try? Data(contentsOf: file)) == contents { signal.yield(()) }
        })
        defer { withExtendedLifetime(watch) {} }

        // The callback queue cannot run until this MainActor operation suspends. The initial reconciliation
        // must see the write, regardless of whether kevent registration precedes or follows the mutation.
        try contents.write(to: file)
        try await waitForWatchChange(changes, "startup reconciliation")
        #expect(!watch.isGone)
    }
}

private enum FileWatchWaitError: Error {
    case timedOut(String)
    case streamEnded(String)
}

private func waitForWatchChange(_ changes: AsyncStream<Void>, _ operation: String,
                                until condition: @escaping @Sendable () -> Bool = { true }) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            for await _ in changes {
                if condition() { return }
            }
            throw FileWatchWaitError.streamEnded(operation)
        }
        group.addTask {
            // A failure deadline, never a delay used to infer that a notification must have arrived.
            try await Task.sleep(for: .seconds(5))
            throw FileWatchWaitError.timedOut(operation)
        }
        defer { group.cancelAll() }
        _ = try await group.next()
    }
}
