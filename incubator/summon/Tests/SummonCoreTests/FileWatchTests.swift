import Foundation
import os
import Testing
@testable import SummonCore

@Suite("FileWatch: changes without polling")
struct FileWatchTests {
    @Test func reportsANewFileInAFolderAndAWriteToAFile() async throws {
        let dir = try makeTempHome()
        let file = dir.appendingPathComponent("log.jsonl")
        try Data().write(to: file)
        let folderChanged = OSAllocatedUnfairLock(initialState: 0)
        let fileChanged = OSAllocatedUnfairLock(initialState: 0)
        let folder = try #require(FileWatch(dir) { folderChanged.withLock { $0 += 1 } })
        let watch = try #require(FileWatch(file) { fileChanged.withLock { $0 += 1 } })

        try Data("x".utf8).write(to: dir.appendingPathComponent("new.ips"))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()
        try await Task.sleep(for: .milliseconds(300))
        #expect(folderChanged.withLock { $0 } > 0)
        #expect(fileChanged.withLock { $0 } > 0)
        #expect(!watch.isGone)

        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(300))
        #expect(watch.isGone, "a replaced or deleted file needs a new watch")
        #expect(FileWatch(dir.appendingPathComponent("missing")) { } == nil)
        _ = folder
    }
}
