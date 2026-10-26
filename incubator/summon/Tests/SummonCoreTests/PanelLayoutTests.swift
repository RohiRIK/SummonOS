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

    @Test func recentIsNewestFirstWithoutSessionNoise() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, _ minutes: Double, _ kind: String) -> ActivityEvent {
            ActivityEvent(id: id, date: t0.addingTimeInterval(minutes * 60), category: .agent, kind: kind, title: id)
        }
        let events = [event("theme", 1, "theme"), event("start", 9, EventKind.sessionStart), event("crash", 5, "crash"),
                      event("end", 8, EventKind.sessionEnd), event("undo", 3, "setting.undo"), event("old", 0, "checkpoint")]
        #expect(PanelLayout.recent(events).map(\.id) == ["crash", "undo", "theme"])
        #expect(PanelLayout.recent([event("start", 1, EventKind.sessionStart)]).isEmpty)
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
