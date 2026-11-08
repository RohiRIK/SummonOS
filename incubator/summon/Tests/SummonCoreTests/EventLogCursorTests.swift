import Foundation
import Testing
@testable import SummonCore

@Suite("Incremental event delivery")
struct EventLogCursorTests {
    @Test func missingCreateAppendPartialAndReplacementDoNotDependOnTimestamps() throws {
        let home = try makeTempHome()
        let file = home.appendingPathComponent("events.jsonl")
        var cursor = EventLogCursor(file: file)
        #expect(try cursor.read().events.isEmpty)

        let log = EventLog(file: file)
        let later = Date(timeIntervalSince1970: 1_800_000_100)
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        try log.append(LoggedEvent(time: later, kind: EventKind.taskDone, title: "First", refs: ["run": "a"]))
        #expect(try cursor.read().events.map(\.title) == ["First"])
        #expect(try cursor.read().events.isEmpty)

        // An older writer timestamp and unchanged file modification date cannot hide an append.
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
        try log.append(LoggedEvent(time: earlier, kind: EventKind.taskDone, title: "Earlier", refs: ["run": "b"]))
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file.path)
        #expect(try cursor.read().events.map(\.title) == ["Earlier"])

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"kind\":\"task.done\"".utf8))
        try handle.close()
        #expect(try cursor.read().events.isEmpty)
        // An atomic replacement discards the partial line and starts from the replacement inode.
        let replacement = home.appendingPathComponent("replacement")
        let replacementLog = EventLog(file: replacement)
        try replacementLog.append(LoggedEvent(time: earlier, kind: EventKind.taskFailed, title: "Replaced", refs: ["run": "c"]))
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
        let replaced = try cursor.read()
        #expect(replaced.reset)
        #expect(replaced.events.map(\.title) == ["Replaced"])
        try FileManager.default.removeItem(at: file)
        #expect(try cursor.read().reset)
        #expect(try cursor.read().events.isEmpty)
        try log.append(LoggedEvent(time: earlier, kind: EventKind.taskDone, title: "Recreated", refs: ["run": "d"]))
        #expect(try cursor.read().events.map(\.title) == ["Recreated"])
    }

    @Test func emptyReplacementCannotKeepAnOldByteOffset() throws {
        let home = try makeTempHome()
        let file = home.appendingPathComponent("events.jsonl")
        let log = EventLog(file: file)
        var cursor = EventLogCursor(file: file)
        for index in 0..<3 {
            try log.append(LoggedEvent(kind: EventKind.taskDone, title: "Old \(index)", refs: ["run": "old-\(index)"]))
        }
        #expect(try cursor.read().events.count == 3)
        try FileManager.default.removeItem(at: file)
        try Data().write(to: file)
        #expect(try cursor.read().reset)
        for index in 0..<4 {
            try log.append(LoggedEvent(kind: EventKind.taskDone, title: "New \(index)", refs: ["run": "new-\(index)"]))
        }
        #expect(try cursor.read().events.map(\.title) == (0..<4).map { "New \($0)" })
    }

    @Test func rotationKeepsDeliveryByRunIdentityNotTimestamp() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String) -> LoggedEvent {
            LoggedEvent(time: date, kind: EventKind.taskDone, title: "Task done: Sample", refs: ["task": "sample", "run": id])
        }
        var ledger = EventDeliveryLedger(capacity: 3)
        #expect(ledger.receive([event("a")], baseline: true).isEmpty)
        #expect(ledger.receive([event("a"), event("b")]).map { $0.refs["run"] } == ["b"])
        #expect(ledger.receive([event("a"), event("b"), event("c")]).map { $0.refs["run"] } == ["c"])
        #expect(ledger.receive([event("b"), event("c")]).isEmpty)
    }

    @Test func activityUsesProvidedHistoryAndDistinctRunRowIdentities() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        try EventLog(paths: paths).append(LoggedEvent(time: time, kind: EventKind.taskDone, title: "Disk"))
        let runs = ["a", "b"].map { id in
            LoggedEvent(time: time, kind: EventKind.taskDone, title: "Task done: Sample", refs: ["task": "sample", "run": id])
        }
        let sources = ActivitySources.load(paths: paths, crashLimit: 0, log: runs)
        #expect(sources.log == runs)
        #expect(Set(sources.events.map(\.id)).count == 2)
    }

    @Test func replayOfTerminalRunDoesNotDuplicateActivityRow() {
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let done = LoggedEvent(time: time, kind: EventKind.taskDone, title: "Task done: Sample", refs: ["task": "sample", "run": "a"])
        let replay = LoggedEvent(time: time, kind: EventKind.taskFailed, title: "Task failed: Sample", refs: ["task": "sample", "run": "a"])
        let events = ActivityFeed.build(log: [done, replay], snapshots: [], checkpoints: [], crashes: [])
        #expect(events.count == 1)
        #expect(events.first?.kind == EventKind.taskDone)
    }
}
