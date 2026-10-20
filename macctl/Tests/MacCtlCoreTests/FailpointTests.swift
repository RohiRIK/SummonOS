import Testing
@testable import MacCtlCore

@Suite("Failpoint seam")
struct FailpointTests {
    @Test func offUnlessTestMode() {
        #expect(Failpoint.mode([:]) == .off)
        #expect(Failpoint.mode(["MACCTL_FAILPOINT": "plan.done"]) == .off)
        #expect(Failpoint.mode(["MACCTL_TEST_MODE": "0", "MACCTL_FAILPOINT": "plan.done"]) == .off)
    }

    @Test func parsesNameOccurrenceListAndTrace() {
        let on = ["MACCTL_TEST_MODE": "1"]
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "plan.done"]) { $1 }) == .kill(name: "plan.done", occurrence: 1))
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "change.written@3"]) { $1 })
            == .kill(name: "change.written", occurrence: 3))
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "list"]) { $1 }) == .list)
        #expect(Failpoint.mode(on.merging(["MACCTL_FAILPOINT": "trace"]) { $1 }) == .trace)
    }

    @Test func namesAreUniqueAndStable() {
        #expect(Set(Failpoint.all).count == Failpoint.all.count)
        #expect(Failpoint.all.first == "lock.acquired")
        // Hitting a point with the seam off is a no-op.
        Failpoint.hit("plan.done")
    }
}
