import Foundation
import Testing
@testable import SummonCore

@Suite("Activity as log lines")
struct ActivityLogTests {
    let utc = TimeZone(identifier: "UTC")!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00:00 UTC

    @Test func settingChangeLine() {
        let event = ActivityEvent(id: "s:1", date: t0, category: .settings, kind: "setting.change", title: "Changed 1 setting",
                                  changes: [SettingChange(id: "dock.autohide", from: "false", to: "true")], refs: ["snapshot": "s-9"])
        #expect(ActivityLog.line(event, timeZone: utc)
            == "2027-01-15 08:00:00  INFO   settings    Changed 1 setting  dock.autohide false→true  snapshot=s-9")
    }

    @Test func levelsFollowSeverity() {
        let crash = ActivityEvent(id: "c", date: t0, category: .problem, kind: "crash", title: "Safari crashed")
        let hang = ActivityEvent(id: "h", date: t0, category: .problem, kind: "hang", title: "Finder hung")
        let agent = ActivityEvent(id: "a", date: t0, category: .agent, kind: EventKind.agentLaunch, title: "Started Claude Code")
        #expect(ActivityLog.level(crash) == .error)
        #expect(ActivityLog.level(hang) == .warn)
        #expect(ActivityLog.level(agent) == .info)
    }

    @Test func untrustedTextIsOneCleanLine() {
        let event = ActivityEvent(id: "c", date: t0, category: .problem, kind: "crash",
                                  title: "evil\u{202E}gpj.exe crashed", detail: "line one\nline two\u{0007}")
        let line = ActivityLog.line(event, timeZone: utc)
        #expect(!line.contains("\u{202E}"))
        #expect(!line.contains("\n"))
        #expect(!line.contains("\u{0007}"))
        #expect(line.hasSuffix("evilgpj.exe crashed  line one line two"))
    }

    @Test func askPromptKeepsTheLastLinesOldestFirst() {
        let events = (0..<60).map { index in
            ActivityEvent(id: "\(index)", date: t0.addingTimeInterval(Double(index)), category: .agent, kind: "x", title: "event \(index)")
        }
        let prompt = ActivityLog.askPrompt(question: "", events: events.reversed(), timeZone: utc)
        #expect(prompt.hasPrefix(ActivityLog.defaultQuestion))
        #expect(!prompt.contains("event 9 "))
        #expect(!prompt.hasSuffix("event 9"))
        #expect(prompt.contains("event 10"))
        #expect(prompt.hasSuffix("event 59"))
        let custom = ActivityLog.askPrompt(question: "  why did it crash? ", events: [events[0]], timeZone: utc)
        #expect(custom.hasPrefix("why did it crash?\n\nSummon activity log"))
    }
}

extension ActivityLogTests {
    @Test func homeFolderShowsAsTilde() {
        let event = ActivityEvent(id: "a", date: t0, category: .agent, kind: "x", title: "t", refs: ["folder": "/u/a/Work", "file": "/tmp/x"])
        #expect(ActivityLog.fields(event, home: "/u/a") == "file=/tmp/x folder=~/Work")
    }
}
