import Foundation
import Testing
@testable import MacCtlCore

@Suite("Failpoint seam")
struct FailpointTests {
    @Test func offUnlessTestMode() {
        #expect(Failpoint.mode([:]) == .off)
        #expect(Failpoint.mode(["MACCTL_FAILPOINT": "K1"]) == .off)
        #expect(Failpoint.mode(["MACCTL_TEST_MODE": "0", "MACCTL_FAILPOINT": "K1"]) == .off)
    }

    @Test func parsesNameOccurrenceListAndTrace() {
        let on = ["MACCTL_TEST_MODE": "1"]
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "K1"]) { $1 }) == .kill(name: "K1", occurrence: 1))
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "W2.1@3"]) { $1 })
            == .kill(name: "W2.1", occurrence: 3))
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "list"]) { $1 }) == .list)
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "trace"]) { $1 }) == .trace)
    }

    @Test func namesAreUniqueAndStable() {
        #expect(Set(Failpoint.all).count == Failpoint.all.count)
        #expect(Failpoint.all == [
            "H1", "K1", "Ii.1", "Ii.2", "Ii.3", "Wi.1", "Wi.2", "Ai.1", "Ai.2", "Fi.1", "Fi.2",
            "K2", "E1", "K3", "RIj", "RVj", "R0", "RE",
        ])
        // Hitting a point with the seam off is a no-op.
        Failpoint.hit("K1")
    }

    @Test func concreteNamesMapToTemplates() {
        #expect(Failpoint.template(of: "I1.1") == "Ii.1")
        #expect(Failpoint.template(of: "I12.3") == "Ii.3")
        #expect(Failpoint.template(of: "W2.2") == "Wi.2")
        #expect(Failpoint.template(of: "A3.1") == "Ai.1")
        #expect(Failpoint.template(of: "F2.1") == "Fi.1")
        #expect(Failpoint.template(of: "F1.2") == "Fi.2")
        #expect(Failpoint.template(of: "RI2") == "RIj")
        #expect(Failpoint.template(of: "RV1") == "RVj")
        #expect(Failpoint.template(of: "H1") == "H1")
        #expect(Failpoint.template(of: "R0") == "R0")
        #expect(Failpoint.template(of: "RE") == "RE")
        #expect(Failpoint.template(of: "E1") == "E1")
        #expect(Failpoint.template(of: "K2") == "K2")
        for bad in ["I0.1", "I1.4", "W1.3", "F1.3", "A1", "RI0", "RVx", "Ii.1", "RIj", "E2", "S1", "U1.1", "C1", "plan.done", "snapshot.saved", "status.completed", ""] {
            #expect(Failpoint.template(of: bad) == nil, "\(bad)")
        }
    }
}

@Suite("Test mode seam")
struct TestModeTests {
    static func catalog(_ domain: String) throws -> String {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("macctl-catalog-\(UUID()).json")
        try Data("""
        [{"id":"t.a","type":"bool","backend":{"defaults":{"domain":"\(domain)","key":"A","type":"bool"}}}]
        """.utf8).write(to: file)
        return file.path
    }

    @Test func offWithoutVariables() throws {
        #expect(try TestMode.configuration([:]) == nil)
    }

    @Test func refusesVariablesWithoutTestMode() async {
        for name in ["MACCTL_SNAPSHOT_DIR", "MACCTL_TEST_CATALOG", "MACCTL_FAKE_DEFAULTS", "MACCTL_FAILPOINT"] {
            await expectMacCtlError("invalid_test_mode") { try TestMode.configuration([name: "/x"]) }
        }
        await expectMacCtlError("invalid_test_mode") { try TestMode.configuration(["MACCTL_TEST_MODE": "yes"]) }
    }

    @Test func refusesRealDomains() async throws {
        for domain in ["com.apple.dock", "NSGlobalDomain", "com.summonos.test.", "com.summonos.testing.x", "com.summonos.test.a/../b"] {
            let path = try Self.catalog(domain)
            await expectMacCtlError("invalid_test_mode") {
                try TestMode.configuration(["MACCTL_TEST_MODE": "1", "MACCTL_SNAPSHOT_DIR": "/tmp/s", "MACCTL_TEST_CATALOG": path])
            }
        }
    }

    @Test func acceptsTestDomainAndNeedsAbsoluteSnapshotDir() async throws {
        let path = try Self.catalog("com.summonos.test.\(UUID().uuidString.lowercased())")
        let config = try #require(try TestMode.configuration(
            ["MACCTL_TEST_MODE": "1", "MACCTL_SNAPSHOT_DIR": "/tmp/s", "MACCTL_TEST_CATALOG": path]))
        #expect(config.settings.map(\.id) == ["t.a"])
        await expectMacCtlError("invalid_test_mode") {
            try TestMode.configuration(["MACCTL_TEST_MODE": "1", "MACCTL_SNAPSHOT_DIR": "rel", "MACCTL_TEST_CATALOG": path])
        }
    }
}
