import Foundation
import Testing
@testable import SummonCore

@Suite("Recent problems: memory events and automatic archiving")
struct ProblemArchiveTests {
    @Test func jetsamNamesTheKilledProcessAndWhy() throws {
        let text = """
            {"bug_type":"298","timestamp":"2026-10-19 10:44:52.00 +0300","os_version":"macOS 26.6.2 (25G83)"}
            {"largestProcess":"Finder","processes":[{"name":"Finder","rpages":61837},
              {"name":"knowledgeconstructiond","pid":16781,"reason":"per-process-limit","rpages":1086}]}
            """
        let report = try CrashReport.parse(text, file: "/r/JetsamEvent-2026-10-19-104452.ips")
        #expect(report.kind == .memory)
        // The report's largest process (Finder) is a bystander; the killed one is the subject.
        #expect(report.program == "knowledgeconstructiond")
        #expect(report.pid == 16781)
        #expect(report.exceptionType == "over its own memory limit")
        #expect(report.isRoutine)
        #expect(CrashReport.memoryReason("vm-pageshortage") == "the Mac ran low on memory")
        #expect(try CrashReport.parse(#"{"bug_type":"288","name":"Safari"}"#, file: "/r/x.ips").kind == .hang)
    }

    @Test func aUserFaultIsNotACrashWorthANotification() throws {
        let header = #"{"app_name":"nsattributedstringagent","bundleID":"com.apple.textkit.nsattributedstringagent","bug_type":"309"}"#
        let fault = try CrashReport.parse(header, file: "/r/ExcUserFault_nsattributedstringagent-2026-10-28-094155.ips")
        #expect(fault.isRoutine)
        #expect(CrashAnnouncementPlan.make([fault], style: .banner, canPostBanners: true).banners.isEmpty)
        let crash = try CrashReport.parse(header, file: "/r/nsattributedstringagent-2026-10-28-094155.ips")
        #expect(!crash.isRoutine)
    }

    @Test func jetsamWithoutAKillIsLowMemory() throws {
        let report = try CrashReport.parse(#"{"bug_type":"298"}"# + "\n" + #"{"largestProcess":"Finder","processes":[]}"#, file: "/r/j.ips")
        #expect(report.program == "Low memory")
        #expect(!report.isRoutine)
    }

    func report(_ file: String, program: String, hoursAgo: Double, now: Date) -> CrashReport {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return CrashReport(file: file, kind: .crash, bugType: "309", appName: program, appVersion: nil,
                           timestamp: formatter.string(from: now.addingTimeInterval(-hoursAgo * 3600)), incidentID: nil,
                           osVersion: nil, process: program, pid: nil, exceptionType: nil, signal: nil, topFrames: [])
    }

    @Test func panelHidesOldAndArchivedProblems() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = report("/r/a.ips", program: "Safari", hoursAgo: 2, now: now)
        let old = report("/r/b.ips", program: "Mail", hoursAgo: 30, now: now)
        let done = report("/r/c.ips", program: "Notes", hoursAgo: 1, now: now)
        let archive = ProblemArchive(paths: SummonPaths(home: try makeTempHome()))
        try archive.archive(["/r/c.ips"])
        #expect(archive.visible([fresh, old, done], now: now).map(\.file) == ["/r/a.ips"])
    }

    @Test func archivingSurvivesAndIsIdempotent() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try ProblemArchive(paths: paths).archive(["/r/a.ips", "/r/a.ips"])
        try ProblemArchive(paths: paths).archive(["/r/b.ips"])
        #expect(ProblemArchive(paths: paths).archived() == ["/r/a.ips", "/r/b.ips"])
    }
}
