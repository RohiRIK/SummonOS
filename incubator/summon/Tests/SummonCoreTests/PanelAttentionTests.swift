import Foundation
import Testing
@testable import SummonCore

@Suite("Needs attention in the panel: shown only when something is wrong")
struct PanelAttentionTests {
    static func report(_ program: String, _ file: String) -> CrashReport {
        CrashReport(file: file, kind: .crash, bugType: "309", appName: program, appVersion: nil, timestamp: nil,
                    incidentID: nil, osVersion: nil, process: program, pid: nil, exceptionType: nil, signal: nil, topFrames: [])
    }

    @Test func nothingWrongMeansNoBlock() {
        let attention = PanelAttention(reports: [], doctor: DoctorReport(checks: [DoctorCheck("app", .pass, "ok")]))
        #expect(attention.isEmpty)
        #expect(PanelAttention(reports: [], doctor: nil).isEmpty)
    }

    @Test func crashesGroupByProgramNewestFileFirst() {
        let attention = PanelAttention(reports: [Self.report("Ghostty", "/r/g2.ips"), Self.report("Helium", "/r/h.ips"),
                                                  Self.report("Ghostty", "/r/g1.ips")], doctor: nil)
        #expect(attention.crashes.map(\.program) == ["Ghostty", "Helium"])
        #expect(attention.crashes[0].file == "/r/g2.ips")
        #expect(attention.crashes[0].title == "Ghostty crashed 2 times")
        #expect(attention.crashes[1].title == "Helium crashed")
    }

    @Test func setupProblemsCountFailuresAndWarnings() {
        let doctor = DoctorReport(checks: [DoctorCheck("a", .fail, "x"), DoctorCheck("b", .warn, "y"), DoctorCheck("c", .pass, "z")])
        let attention = PanelAttention(reports: [], doctor: doctor)
        #expect(attention.setupProblems == 2)
        #expect(attention.setupTitle == "2 setup problems · Fix…")
        #expect(!attention.isEmpty)
    }

    @Test func helpersDontFlagThePanelAndOneLineSummarizes() {
        let attention = PanelAttention(reports: [Self.report("Helium Helper", "/r/h.ips"), Self.report("swiftpm-testing-helper", "/r/s.ips"),
                                                  Self.report("Ghostty", "/r/g.ips")], doctor: nil)
        #expect(attention.crashes.map(\.program) == ["Ghostty"])
        #expect(attention.summary == "Ghostty crashed · Review…")
        let two = PanelAttention(reports: [Self.report("Ghostty", "/a"), Self.report("Helium", "/b")], doctor: nil)
        #expect(two.summary == "2 apps crashed · Review…")
        let setupOnly = PanelAttention(reports: [Self.report("Helium Helper", "/h")], doctor: DoctorReport(checks: [DoctorCheck("a", .warn, "x")]))
        #expect(setupOnly.summary == "1 setup problem · Fix…")
        #expect(PanelAttention(reports: [Self.report("xctest", "/x")], doctor: nil).summary == nil)
    }
}
