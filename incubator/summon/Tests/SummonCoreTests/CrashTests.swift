import Foundation
import Testing
@testable import SummonCore

@Suite("Crash reports")
struct CrashTests {
    @Test func parsesHeaderAndBody() throws {
        let report = try CrashReport.parse(sampleCrashIPS, file: "/tmp/Example.ips")
        #expect(report.kind == .crash)
        #expect(report.appName == "Example")
        #expect(report.appVersion == "1.2")
        #expect(report.process == "Example")
        #expect(report.pid == 4242)
        #expect(report.exceptionType == "EXC_BAD_ACCESS")
        #expect(report.signal == "SIGSEGV")
        #expect(report.osVersion == "macOS 26.0 (26A100)")
        #expect(report.topFrames == ["Example: Example.crash()", "libsystem_kernel.dylib: __pthread_kill", "???"])
    }

    @Test func textBodyKeepsHeaderFacts() throws {
        let text = """
        {"app_name":"Slow","bug_type":"288","timestamp":"2026-10-17 11:00:00.00 +0000"}
        Date/Time: 2026-10-17 11:00:00 +0000
        Duration: 5.00s
        """
        let report = try CrashReport.parse(text, file: "/tmp/Slow.ips")
        #expect(report.kind == .hang)
        #expect(report.program == "Slow")
        #expect(report.pid == nil)
        #expect(report.topFrames.isEmpty)
    }

    @Test func rejectsBadFiles() {
        #expect(throws: CrashReport.ParseError.emptyFile) { try CrashReport.parse("  \n", file: "x") }
        #expect(throws: CrashReport.ParseError.badHeader) { try CrashReport.parse("not json\n{}", file: "x") }
    }

    @Test func kindMapping() {
        #expect(CrashReport.kind(for: "309") == .crash)
        #expect(CrashReport.kind(for: "210") == .panic)
        #expect(CrashReport.kind(for: "123") == .other)
    }

    @Test func muteAndMarkerPersist() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let watcher = CrashWatcher(paths: paths)
        #expect(watcher.muted().isEmpty)
        try watcher.setMuted("/usr/bin/Example", muted: true)
        #expect(watcher.muted() == ["Example"])
        try watcher.setMuted("Example", muted: false)
        #expect(watcher.muted().isEmpty)

        #expect(watcher.marker() == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try watcher.saveMarker(date)
        #expect(watcher.marker() == date)
    }

    @Test func reportsSkipMutedAndOldFiles() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        let dir = home.appendingPathComponent("Library/Logs/DiagnosticReports")
        let old = dir.appendingPathComponent("Old.ips")
        let fresh = dir.appendingPathComponent("Example.ips")
        let muted = dir.appendingPathComponent("Noisy.ips")
        try writeFile(#"{"app_name":"Old","bug_type":"309"}"#, to: old)
        try writeFile(sampleCrashIPS, to: fresh)
        try writeFile(#"{"app_name":"Noisy","bug_type":"309"}"#, to: muted)
        try writeFile("not a report", to: dir.appendingPathComponent("notes.txt"))
        let marker = Date().addingTimeInterval(-60)
        try FileManager.default.setAttributes([.modificationDate: marker.addingTimeInterval(-3600)], ofItemAtPath: old.path)

        let watcher = CrashWatcher(paths: paths)
        try watcher.setMuted("Noisy", muted: true)

        let all = watcher.reports(since: nil)
        #expect(Set(all.map(\.appName)) == ["Old", "Example"])
        let recent = watcher.reports(since: marker)
        #expect(recent.map(\.appName) == ["Example"])
    }

    @Test func diagnosePromptCarriesTheFactsAndTheSkill() throws {
        let report = try CrashReport.parse(sampleCrashIPS, file: "/tmp/Example.ips")
        let prompt = DiagnosePrompt.make(for: report, skillPath: "/skills/diagnose-crash-mac/SKILL.md")
        #expect(prompt.hasPrefix("A program crashed on this Mac"))
        #expect(prompt.contains("PID:       4242"))
        #expect(prompt.contains("signal:    SIGSEGV"))
        #expect(prompt.contains("report:    /tmp/Example.ips"))
        #expect(prompt.contains("/skills/diagnose-crash-mac/SKILL.md"))
    }
}
