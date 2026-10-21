import Foundation
import Testing
@testable import SummonCore

@Suite("Activity timeline and status")
struct ActivityTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func eventLogAppendsAndSkipsBadLines() throws {
        let home = try makeTempHome()
        let log = EventLog(paths: SummonPaths(home: home))
        #expect(log.read().isEmpty)
        try log.append(LoggedEvent(time: t0, kind: EventKind.themeSet, title: "Theme: Summon Night", refs: ["theme": "summon-night"]))
        let handle = try FileHandle(forWritingTo: log.file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        try log.append(LoggedEvent(time: t0.addingTimeInterval(5), kind: EventKind.agentLaunch, title: "Started Claude Code"))
        let events = log.read()
        #expect(events.map(\.kind) == [EventKind.themeSet, EventKind.agentLaunch])
        #expect(events[0].refs["theme"] == "summon-night")
        #expect(events[0].time == t0)
    }

    @Test func eventLogTrimsToKeep() throws {
        let home = try makeTempHome()
        let log = EventLog(file: home.appendingPathComponent("events.jsonl"), keep: 3, maxBytes: 200)
        for index in 0..<10 {
            try log.append(LoggedEvent(time: t0.addingTimeInterval(Double(index)), kind: "test", title: "event \(index)"))
        }
        let titles = log.read().map(\.title)
        #expect(titles.count <= 4)
        #expect(titles.last == "event 9")
    }

    @Test func readsMacctlSnapshotFiles() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        try writeFile("""
        {"changes":[{"from":false,"id":"dock.autohide","to":true},{"id":"dock.tilesize","to":52}],"createdAt":"2026-10-18T07:00:00Z","id":"20261018-100000"}
        """, to: paths.macctlSnapshots.appendingPathComponent("20261018-100000.json"))
        try writeFile("""
        {"changes":[{"from":true,"id":"dock.autohide","to":false}],"createdAt":"2026-10-18T07:05:00Z","id":"20261018-100500","undoes":"20261018-100000"}
        """, to: paths.macctlSnapshots.appendingPathComponent("20261018-100500.json"))
        try writeFile("{broken", to: paths.macctlSnapshots.appendingPathComponent("bad.json"))

        let snapshots = MacctlSnapshot.load(from: paths.macctlSnapshots)
        #expect(snapshots.map(\.id) == ["20261018-100500", "20261018-100000"])
        #expect(snapshots[1].changes == [
            SettingChange(id: "dock.autohide", from: "false", to: "true"),
            SettingChange(id: "dock.tilesize", from: nil, to: "52"),
        ])
        #expect(snapshots[0].undoes == "20261018-100000")
    }

    /// macctl's journaled sessions keep a write-once header with `status: "pending"`; the status comes
    /// from `../journal/<id>.jsonl` (QA R-b), so a finished session never warns.
    @Test func journaledMacctlHeaderTakesStatusFromJournal() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        let journal = paths.macctlSnapshots.deletingLastPathComponent().appendingPathComponent("journal")
        for id in ["20261020-100000", "20261020-110000", "20261020-120000"] {
            try writeFile("""
            {"changes":[{"id":"dock.autohide","to":true}],"createdAt":"2026-10-20T07:00:00Z","id":"\(id)","status":"pending"}
            """, to: paths.macctlSnapshots.appendingPathComponent("\(id).json"))
        }
        try writeFile("""
        {"v":1,"seq":1,"op":"session_start"}
        {"v":1,"seq":2,"op":"session_end","outcome":"completed"}

        """, to: journal.appendingPathComponent("20261020-100000.jsonl"))
        // Crashed after the intent, with a torn last line: still pending.
        try writeFile("""
        {"v":1,"seq":1,"op":"session_start"}
        {"v":1,"seq":2,"op":"intent"}
        {"v":1,"seq":3,"op":"sess
        """, to: journal.appendingPathComponent("20261020-110000.jsonl"))

        let byID = Dictionary(uniqueKeysWithValues: MacctlSnapshot.load(from: paths.macctlSnapshots).map { ($0.id, $0.status) })
        #expect(byID["20261020-100000"] == "completed")
        #expect(byID["20261020-110000"] == "pending")
        // A header with no journal (crash at H1, or an older macctl) keeps its own status.
        #expect(byID["20261020-120000"] == "pending")
    }

    /// R-b through the path the panel refreshes every second (ActivityModel.refresh →
    /// ActivitySources.load → StatusProbe): every header says `pending`, the journal decides.
    /// Only the session whose journal ends mid-way (last line `applied`) warns.
    @Test func activityStatusComesFromTheJournalNotTheHeader() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        let journal = paths.macctlSnapshots.deletingLastPathComponent().appendingPathComponent("journal")
        let journals: [String: String] = [
            "20261020-090000": """
            {"v":1,"seq":1,"op":"session_start"}
            {"v":1,"seq":2,"op":"intent"}
            {"v":1,"seq":3,"op":"applied","ref":2}

            """,
            "20261020-091000": """
            {"v":1,"seq":1,"op":"session_start"}
            {"v":1,"seq":2,"op":"intent"}
            {"v":1,"seq":3,"op":"applied","ref":2}
            {"v":1,"seq":4,"op":"session_end","outcome":"completed"}

            """,
            "20261020-092000": """
            {"v":1,"seq":1,"op":"session_start"}
            {"v":1,"seq":2,"op":"intent"}
            {"v":1,"seq":3,"op":"applied","ref":2}
            {"v":1,"seq":4,"op":"session_end","outcome":"completed"}
            {"v":1,"seq":5,"op":"revert_intent","ref":2}
            {"v":1,"seq":6,"op":"reverted","ref":2}
            {"v":1,"seq":7,"op":"session_end","outcome":"undone"}

            """,
            "20261020-093000": """
            {"v":1,"seq":1,"op":"session_start"}
            {"v":1,"seq":2,"op":"intent"}
            {"v":1,"seq":3,"op":"failed","ref":2}
            {"v":1,"seq":4,"op":"session_end","outcome":"rolled_back"}

            """,
            "20261020-094000": """
            {"v":1,"seq":1,"op":"session_start"}
            {"v":1,"seq":2,"op":"intent"}
            {"v":1,"seq":3,"op":"reverted","ref":2}
            {"v":1,"seq":4,"op":"session_end","outcome":"recovered"}

            """,
        ]
        for (id, text) in journals {
            try writeFile("""
            {"changes":[{"id":"dock.autohide","to":true}],"createdAt":"2026-10-20T07:00:00Z","id":"\(id)","status":"pending"}
            """, to: paths.macctlSnapshots.appendingPathComponent("\(id).json"))
            try writeFile(text, to: journal.appendingPathComponent("\(id).jsonl"))
        }
        let snapshots = ActivitySources.load(paths: paths, crashLimit: 0).snapshots
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0.status) })
        #expect(byID["20261020-090000"] == "pending")      // applied, no session_end: unfinished
        #expect(byID["20261020-091000"] == "completed")
        #expect(byID["20261020-092000"] == "undone")       // reverted by undo
        #expect(byID["20261020-093000"] == "rolled_back")
        #expect(byID["20261020-094000"] == "recovered")

        let status = StatusProbe.build(
            agent: nil, agentInstalled: false, log: [], macctlInstalled: true, macctlProblems: [],
            snapshots: snapshots, checkpoints: [], configIsRepo: true, crashes: []
        )
        let macctlWarnings = status.warnings.filter { $0.hasPrefix("macctl ") }
        #expect(macctlWarnings.count == 1)
        #expect(macctlWarnings.first?.contains("20261020-090000") == true)

        // Event categories per status (decision for #62): finished and recovered are not Problems.
        let events = Dictionary(uniqueKeysWithValues: ActivityFeed.build(log: [], snapshots: snapshots, checkpoints: [], crashes: [])
            .map { ($0.refs["snapshot"] ?? "", $0) })
        #expect(events["20261020-090000"]?.category == .problem)        // pending
        #expect(events["20261020-091000"]?.category == .settings)       // completed
        #expect(events["20261020-091000"]?.kind == "setting.change")
        #expect(events["20261020-092000"]?.category == .settings)       // undone
        #expect(events["20261020-092000"]?.kind == "setting.undone")
        #expect(events["20261020-093000"]?.category == .settings)       // rolled_back
        #expect(events["20261020-093000"]?.title.contains("recovered after interruption") == true)
        #expect(events["20261020-094000"]?.category == .settings)       // recovered
        #expect(events["20261020-094000"]?.kind == "setting.recovered")
    }

    /// The rest of the decision: abandoned, flagged hand edits and unknown statuses are Problems.
    @Test func macctlProblemStatusesAreProblems() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        let journal = paths.macctlSnapshots.deletingLastPathComponent().appendingPathComponent("journal")
        for id in ["20261020-100000", "20261020-101000", "20261020-102000", "20261020-103000"] {
            try writeFile("""
            {"changes":[{"id":"dock.autohide","to":true}],"createdAt":"2026-10-20T07:00:00Z","id":"\(id)","status":"pending"}
            """, to: paths.macctlSnapshots.appendingPathComponent("\(id).json"))
        }
        // Hand edit left as it is by recover.
        try writeFile("""
        {"v":1,"seq":1,"op":"session_start"}
        {"v":1,"seq":2,"op":"intent"}
        {"v":1,"seq":3,"op":"applied","ref":2}
        {"v":1,"seq":4,"op":"revert_flagged","ref":2}
        {"v":1,"seq":5,"op":"session_end","outcome":"recovered"}

        """, to: journal.appendingPathComponent("20261020-100000.jsonl"))
        // Flagged, then `undo --force` restored it: no longer a problem.
        try writeFile("""
        {"v":1,"seq":1,"op":"session_start"}
        {"v":1,"seq":2,"op":"intent"}
        {"v":1,"seq":3,"op":"applied","ref":2}
        {"v":1,"seq":4,"op":"session_end","outcome":"completed"}
        {"v":1,"seq":5,"op":"revert_flagged","ref":2}
        {"v":1,"seq":6,"op":"session_end","outcome":"undone"}
        {"v":1,"seq":7,"op":"revert_intent","ref":2}
        {"v":1,"seq":8,"op":"reverted","ref":2}
        {"v":1,"seq":9,"op":"session_end","outcome":"undone"}

        """, to: journal.appendingPathComponent("20261020-101000.jsonl"))
        // recover --abandon kept the journal as .corrupt.
        try writeFile("garbage\n", to: journal.appendingPathComponent("20261020-102000.jsonl.corrupt"))
        // A status this Summon does not know.
        try writeFile("""
        {"v":1,"seq":1,"op":"session_end","outcome":"something_new"}

        """, to: journal.appendingPathComponent("20261020-103000.jsonl"))

        let snapshots = MacctlSnapshot.load(from: paths.macctlSnapshots)
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        #expect(byID["20261020-100000"]?.status == "flagged")
        #expect(byID["20261020-101000"]?.status == "undone")
        #expect(byID["20261020-102000"]?.status == "abandoned")
        #expect(byID["20261020-103000"]?.status == "something_new")
        let events = Dictionary(uniqueKeysWithValues: ActivityFeed.build(log: [], snapshots: snapshots, checkpoints: [], crashes: [])
            .map { ($0.refs["snapshot"] ?? "", $0.category) })
        #expect(events["20261020-100000"] == .problem)
        #expect(events["20261020-101000"] == .settings)
        #expect(events["20261020-102000"] == .problem)
        #expect(events["20261020-103000"] == .problem)
    }

    @Test func feedMergesSourcesNewestFirstByDate() throws {
        let change = MacctlSnapshot(id: "20261018-100000", createdAt: t0.addingTimeInterval(60),
                                    changes: [SettingChange(id: "dock.autohide", from: "false", to: "true")])
        let undo = MacctlSnapshot(id: "20261018-100500", createdAt: t0.addingTimeInterval(120),
                                  changes: [SettingChange(id: "dock.autohide", from: "true", to: "false")], undoes: "20261018-100000")
        let profile = MacctlSnapshot(id: "20261018-090000", createdAt: t0.addingTimeInterval(-60), changes: [
            SettingChange(id: "a.b", from: nil, to: "1"), SettingChange(id: "c.d", from: nil, to: "2"),
        ])
        let empty = MacctlSnapshot(id: "20261018-080000", createdAt: t0.addingTimeInterval(-120), changes: [])
        // A UTC checkpoint id that sorts after the local-time snapshot ids, but happened first.
        let checkpoint = Checkpoint(id: "20261018-230000", label: "agent session", createdAt: t0, configCommit: nil, macctlSnapshot: "none")
        let launch = LoggedEvent(time: t0.addingTimeInterval(1), kind: EventKind.agentLaunch, title: "Started Claude Code")

        let events = ActivityFeed.build(log: [launch], snapshots: [undo, change, profile, empty], checkpoints: [checkpoint], crashes: [])
        #expect(events.map(\.title) == [
            "Undid dock.autohide", "Changed dock.autohide", "Started Claude Code",
            "Checkpoint: agent session", "Applied 2 settings",
        ])
        #expect(events[0].kind == "setting.undo")
        #expect(events[0].refs["undoes"] == "20261018-100000")
        #expect(events[1].detail == "false → true")
        #expect(events[1].category == .settings)
        #expect(events[2].category == .agent)
        #expect(events[3].category == .checkpoint)
        #expect(Set(events.map(\.id)).count == events.count)
    }

    @Test func crashesUseTheirTimestamp() throws {
        let report = CrashReport(
            file: "/tmp/Example.ips", kind: .hang, bugType: "298", appName: "Example", appVersion: nil,
            timestamp: "2026-10-17 10:15:00.00 +0000", incidentID: nil, osVersion: nil, process: "Example",
            pid: nil, exceptionType: nil, signal: nil, topFrames: []
        )
        let date = try #require(ActivityFeed.crashDate(report))
        #expect(date == Date(timeIntervalSince1970: 1_792_232_100))
        let events = ActivityFeed.build(log: [], snapshots: [], checkpoints: [], crashes: [report])
        #expect(events.first?.title == "Example hung")
        #expect(events.first?.category == .problem)
    }

    @Test func openSessionMatchesStartAndEnd() {
        let start = LoggedEvent(time: t0, kind: EventKind.sessionStart, title: "s", refs: ["session": "a", "folder": "/w"])
        let otherEnd = LoggedEvent(time: t0.addingTimeInterval(10), kind: EventKind.sessionEnd, title: "e", refs: ["session": "b"])
        let end = LoggedEvent(time: t0.addingTimeInterval(20), kind: EventKind.sessionEnd, title: "e", refs: ["session": "a"])
        let now = t0.addingTimeInterval(30)
        #expect(StatusProbe.openSession(in: [start, otherEnd], now: now) == start)
        #expect(StatusProbe.openSession(in: [start, otherEnd, end], now: now) == nil)
        #expect(StatusProbe.openSession(in: [start], now: t0.addingTimeInterval(StatusProbe.staleSession + 1)) == nil)
        #expect(StatusProbe.openSession(in: [], now: now) == nil)
    }

    @Test func statusWarnsAboutWhatUndoCannotCover() throws {
        let claude = try #require(AgentRegistry.find("claude"))
        let start = LoggedEvent(time: t0, kind: EventKind.sessionStart, title: "s", refs: ["folder": "/w"])
        let change = MacctlSnapshot(id: "1", createdAt: t0, changes: [SettingChange(id: "dock.autohide", from: "false", to: "true")])
        let status = StatusProbe.build(
            agent: claude, agentInstalled: true, log: [start], macctlInstalled: true,
            macctlProblems: ["Automation (System Events): not granted"], snapshots: [change],
            checkpoints: [], configIsRepo: false, crashes: [], now: t0.addingTimeInterval(60)
        )
        #expect(status.agent.running)
        #expect(status.agent.folder == "/w")
        #expect(status.lastChange?.title == "Changed dock.autohide")
        #expect(status.warnings.contains { $0.contains("~/.config is not a git repo") })
        #expect(status.warnings.contains { $0.hasPrefix("macctl: Automation") })
    }

    @Test func doctorProblemsParsesFailedChecks() {
        let json = """
        {"ok": true, "command": "doctor", "result": {"macOSVersion": "26.6.2", "checks": [
          {"name": "Automation (System Events)", "ok": false, "detail": "not granted", "fixURL": "x-apple.systempreferences:"},
          {"name": "Snapshots writable", "ok": true, "detail": "/tmp"}
        ]}}
        """
        #expect(StatusProbe.doctorProblems(fromJSON: json) == ["Automation (System Events): not granted"])
        #expect(StatusProbe.doctorProblems(fromJSON: "nope") == ["doctor output could not be read"])
    }
}

@Suite("Session hooks")
struct SessionHookTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func startAndEndCarryTheSessionAndFolder() throws {
        let start = try #require(SessionHook.event(phase: "start", payload: #"{"session_id":"abc","cwd":"/Users/x/Work","source":"startup","hook_event_name":"SessionStart"}"#, now: now))
        #expect(start.kind == EventKind.sessionStart)
        #expect(start.title == "Claude Code session started")
        #expect(start.refs == ["session": "abc", "folder": "/Users/x/Work"])
        let end = try #require(SessionHook.event(phase: "end", payload: #"{"session_id":"abc","reason":"prompt_input_exit"}"#, now: now))
        #expect(end.kind == EventKind.sessionEnd)
        #expect(end.detail == "Reason: prompt_input_exit")
        #expect(StatusProbe.openSession(in: [start, end], now: now) == nil)
        #expect(StatusProbe.openSession(in: [start], now: now) == start)
    }

    @Test func compactionAndUnknownPhasesRecordNothing() {
        #expect(SessionHook.event(phase: "start", payload: #"{"session_id":"abc","source":"compact"}"#) == nil)
        #expect(SessionHook.event(phase: "middle", payload: "{}") == nil)
    }

    @Test func badPayloadStillRecords() throws {
        let event = try #require(SessionHook.event(phase: "start", payload: "not json", now: now))
        #expect(event.refs.isEmpty)
        #expect(event.title == "Claude Code session started")
    }
}
