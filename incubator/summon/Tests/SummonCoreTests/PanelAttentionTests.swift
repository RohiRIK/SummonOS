import Foundation
import Testing
@testable import SummonCore

@Suite("Needs attention in the panel: shown only when something is wrong")
struct PanelAttentionTests {
    @Test func nothingWrongMeansNoBlock() {
        let attention = PanelAttention(doctor: DoctorReport(checks: [DoctorCheck("app", .pass, "ok")]))
        #expect(attention.isEmpty)
        #expect(attention.summary == nil)
        #expect(PanelAttention(doctor: nil).isEmpty)
    }

    @Test func setupProblemsCountFailuresAndWarnings() {
        let doctor = DoctorReport(checks: [DoctorCheck("a", .fail, "x"), DoctorCheck("b", .warn, "y"), DoctorCheck("c", .pass, "z")])
        let attention = PanelAttention(doctor: doctor)
        #expect(attention.setupProblems == 2)
        #expect(attention.summary == "2 setup problems · Fix…")
        #expect(!attention.isEmpty)
        #expect(PanelAttention(doctor: DoctorReport(checks: [DoctorCheck("a", .warn, "x")])).summary == "1 setup problem · Fix…")
    }
}
