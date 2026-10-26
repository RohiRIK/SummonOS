import Foundation
import Testing
@testable import SummonCore

@Suite("Minimal panel: home items, Setup groups, relative times")
struct PanelLayoutTests {
    @Test func agoReadsLikeAMenu() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(PanelClock.ago(now.addingTimeInterval(-20), now: now) == "now")
        #expect(PanelClock.ago(now.addingTimeInterval(-300), now: now) == "5m")
        #expect(PanelClock.ago(now.addingTimeInterval(-3 * 3600), now: now) == "3h")
        #expect(PanelClock.ago(now.addingTimeInterval(-2 * 86_400), now: now) == "2d")
        #expect(PanelClock.ago(now.addingTimeInterval(60), now: now) == "now")
    }

    @Test func everyDefaultGroupIsOnTheHomeOrInSetup() throws {
        let tree = try MenuTree.parse(DefaultMenu.jsonc)
        let top = tree.children(of: nil).map(\.id)
        for id in top {
            #expect(PanelLayout.homeItems.contains(id) || PanelLayout.setupGroups.contains(id), "\(id) is reachable only by search")
        }
        #expect(PanelLayout.setupGroups.allSatisfy { top.contains($0) })
    }
}
