import Foundation
import Testing
@testable import SummonCore

@Suite("BuildInfo: parsing and unknown boundaries")
struct BuildInfoTests {
    private func info(revision: String = "0123456789abcdef0123456789abcdef01234567",
                      timestamp: String = "2026-11-08T12:30:45Z") -> BuildInfo {
        BuildInfo(marketingVersion: "1.2.3", buildNumber: "42", sourceRevision: revision, sourceState: "clean",
                  channel: "edge", configuration: "release", buildTimestamp: timestamp)
    }

    @Test func unknownRevisionAndTimestampStayUnknown() {
        let build = info(revision: "unknown", timestamp: "unknown")
        #expect(build.shortRevision == nil)
        #expect(build.builtAt == nil)
        #expect(info(revision: "  ").shortRevision == nil)
    }

    @Test func shortRevisionKeepsAPrefixOfTheFullHash() {
        #expect(info().shortRevision == "0123456789ab")
        #expect(info(revision: "abc").shortRevision == "abc")
    }

    @Test func parsesPlainAndFractionalTimestampsToExactInstants() {
        #expect(info().builtAt == Date(timeIntervalSince1970: 1_794_141_045))
        #expect(info(timestamp: "2026-11-08T12:30:45.500Z").builtAt == Date(timeIntervalSince1970: 1_794_141_045.5))
        #expect(info(timestamp: "yesterday").builtAt == nil)
    }
}
