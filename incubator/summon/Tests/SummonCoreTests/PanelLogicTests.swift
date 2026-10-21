import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import SummonCore

@Suite("Menu bar panel: dismissal, focus, hotkey repeat, geometry (spec v1.5 A–F)")
struct PanelLogicTests {
    let textEdit: Int32 = 501
    let summon: Int32 = 900
    var session: PanelSession { PanelSession(previousAppPID: textEdit, ownPID: summon) }

    // MARK: Opening and toggling (B1, B2, C1, C2, C5, C6)

    @Test func iconAndHotKeyToggle() {
        for event in [PanelEvent.statusItemLeftClick, .hotKey] {
            #expect(PanelDismissal.decide(event, isOpen: false, session: nil) == .open)
            #expect(PanelDismissal.decide(event, isOpen: true, session: session) == .close(.toggle))
        }
    }

    @Test func codeOpenAndCloseAreIdempotent() {
        #expect(PanelDismissal.decide(.openFromCode, isOpen: false, session: nil) == .open)
        #expect(PanelDismissal.decide(.openFromCode, isOpen: true, session: session) == .ignore)
        #expect(PanelDismissal.decide(.closeFromCode, isOpen: true, session: session) == .close(.programmatic))
        #expect(PanelDismissal.decide(.closeFromCode, isOpen: false, session: nil) == .ignore)
    }

    // MARK: Right-click menu (B3, B4, B5, B6)

    @Test func rightClickShowsMenuAndClosesPanelFirst() {
        #expect(PanelDismissal.decide(.statusItemRightClick, isOpen: false, session: nil) == .showMenu)
        #expect(PanelDismissal.decide(.statusItemRightClick, isOpen: true, session: session) == .closeThenShowMenu)
    }

    @Test func settingsAndQuitClose() {
        #expect(PanelDismissal.decide(.settingsChosen, isOpen: true, session: session) == .close(.settings))
        #expect(PanelDismissal.decide(.quitChosen, isOpen: true, session: session) == .close(.quit))
        #expect(PanelDismissal.decide(.settingsChosen, isOpen: false, session: nil) == .close(.settings))
    }

    // MARK: Section D: the only close triggers

    @Test func closeTriggers() {
        #expect(PanelDismissal.decide(.escapePressed, isOpen: true, session: session) == .close(.escape))       // D1
        #expect(PanelDismissal.decide(.actionFinished, isOpen: true, session: session) == .close(.action))     // D3
        #expect(PanelDismissal.decide(.frontmostAppChanged(pid: 777), isOpen: true, session: session)
            == .close(.appSwitch))                                                                              // D4
        #expect(PanelDismissal.decide(.activeSpaceChanged, isOpen: true, session: session) == .close(.spaceChange)) // D5
        for event in [PanelEvent.screenLocked, .displaySlept, .systemWillSleep] {                               // D7
            #expect(PanelDismissal.decide(event, isOpen: true, session: session) == .close(.lockOrSleep))
        }
    }

    @Test func crashAlertClosesThePanelAndKeepsFocus() {
        // D12: the panel closes first; focus goes to the crash alert, never back to the previous app.
        #expect(PanelDismissal.decide(.crashAlertPresenting, isOpen: true, session: session) == .close(.crashAlert))
        #expect(PanelDismissal.decide(.crashAlertPresenting, isOpen: false, session: nil) == .ignore)
        #expect(!PanelDismissal.restoresFocus(after: .crashAlert))
        #expect(PanelDismissal.focusAction(after: .crashAlert, frontmostPID: summon, session: session) == .none)
    }

    @Test func sameAppOrSummonActivatingDoesNotClose() {
        // Decision 2: clicking back into the previous app keeps the panel open.
        #expect(PanelDismissal.decide(.frontmostAppChanged(pid: textEdit), isOpen: true, session: session) == .ignore)
        #expect(PanelDismissal.decide(.frontmostAppChanged(pid: summon), isOpen: true, session: session) == .ignore)
    }

    @Test func unknownPreviousAppClosesOnAnyOtherApp() {
        let unknown = PanelSession(previousAppPID: nil, ownPID: summon)
        #expect(PanelDismissal.decide(.frontmostAppChanged(pid: textEdit), isOpen: true, session: unknown) == .close(.appSwitch))
    }

    @Test(arguments: [PanelEvent.clickInsidePanel, .pointerLeftPanel, .idle, .contentUpdated, .notificationBanner, .panelResignedKey])
    func nonTriggersKeepThePanelOpen(event: PanelEvent) {
        // D8–D11, and no generic click-elsewhere / resign-key dismissal.
        #expect(PanelDismissal.decide(event, isOpen: true, session: session) == .ignore)
    }

    @Test func closedPanelIgnoresDismissalEvents() {
        let events: [PanelEvent] = [.escapePressed, .actionFinished, .frontmostAppChanged(pid: 777), .activeSpaceChanged,
                                    .screenLocked, .displaySlept, .systemWillSleep, .crashAlertPresenting]
        for event in events {
            #expect(PanelDismissal.decide(event, isOpen: false, session: nil) == .ignore)
        }
    }

    // MARK: Focus return (A3, A4, C2, D rules)

    @Test func whichClosesReturnFocus() {
        let returning: Set<PanelCloseReason> = [.escape, .toggle, .action, .programmatic, .contextMenu]
        for reason in PanelCloseReason.allCases {
            #expect(PanelDismissal.restoresFocus(after: reason) == returning.contains(reason), "\(reason)")
        }
    }

    @Test func focusActionActivatesPreviousOnlyWhenSummonTookOver() {
        #expect(PanelDismissal.focusAction(after: .escape, frontmostPID: textEdit, session: session) == .none)
        #expect(PanelDismissal.focusAction(after: .escape, frontmostPID: summon, session: session) == .activatePrevious)
        #expect(PanelDismissal.focusAction(after: .appSwitch, frontmostPID: summon, session: session) == .none)
        #expect(PanelDismissal.focusAction(after: .settings, frontmostPID: summon, session: session) == .none)
        #expect(PanelDismissal.focusAction(after: .escape, frontmostPID: summon, session: nil) == .none)
        let selfOpened = PanelSession(previousAppPID: summon, ownPID: summon)
        #expect(PanelDismissal.focusAction(after: .escape, frontmostPID: summon, session: selfOpened) == .none)
    }

    // MARK: Hotkey repeat (C3)

    @Test func heldHotKeyOpensOnce() {
        var filter = HotKeyRepeatFilter()
        var accepted = 0
        // First press, then key repeat every 30 ms for three seconds with no release.
        var t = 10.0
        while t < 13.0 {
            if filter.press(at: t) { accepted += 1 }
            t += 0.03
        }
        #expect(accepted == 1)
        filter.release()
        let next = filter.press(at: 13.1)
        #expect(next)
    }

    @Test func separatePressesToggle() {
        var filter = HotKeyRepeatFilter()
        let first = filter.press(at: 1.0)
        filter.release()
        let second = filter.press(at: 1.2)
        filter.release()
        #expect(first && second)
    }

    @Test func lostReleaseDoesNotStickTheHotKey() {
        var filter = HotKeyRepeatFilter()
        let first = filter.press(at: 1.0)
        let tooSoon = filter.press(at: 1.5)
        let later = filter.press(at: 3.0)
        #expect(first && !tooSoon && later)
    }

    // MARK: Geometry (B1, C1, E3, E4, F2, F4)

    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let button = CGRect(x: 1300, y: 949, width: 30, height: 33)

    @Test func panelSitsUnderTheIconCentered() {
        let frame = PanelGeometry.frame(size: CGSize(width: 320, height: 200), anchor: button, visible: visible)
        #expect(frame.maxY == 945)
        #expect(frame.midX == 1315)
        #expect(frame.height == 200)
    }

    @Test func panelClampsEightPointsFromTheRightEdge() {
        let edge = CGRect(x: 1490, y: 949, width: 20, height: 33)
        let frame = PanelGeometry.frame(size: CGSize(width: 320, height: 200), anchor: edge, visible: visible)
        #expect(frame.maxX == visible.maxX - 8)
    }

    @Test func tallContentCapsAtVisibleHeight() {
        let frame = PanelGeometry.frame(size: CGSize(width: 320, height: 5000), anchor: button, visible: visible)
        #expect(frame.height == visible.height - 16)
        #expect(frame.minY >= visible.minY + 8)
        #expect(PanelGeometry.maxHeight(visible: visible) == 933)
    }

    @Test func fullscreenWithHiddenMenuBarStaysOnScreen() {
        // Fullscreen: visible frame is the whole screen; the button may report a rect at or above the top.
        let hidden = CGRect(x: 1300, y: 990, width: 30, height: 24)
        let frame = PanelGeometry.frame(size: CGSize(width: 320, height: 200), anchor: hidden, visible: screen)
        #expect(frame.maxY <= screen.maxY)
    }

    @Test func anchorMovesToThePointerDisplay() {
        let second = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let moved = PanelGeometry.anchor(button, from: screen, to: second)
        #expect(second.maxX - moved.minX == screen.maxX - button.minX)
        #expect(second.maxY - moved.minY == screen.maxY - button.minY)
        #expect(PanelGeometry.anchor(button, from: screen, to: screen) == button)
    }

    @Test func screenChoiceFollowsSeparateSpaces() {
        #expect(PanelGeometry.chooseScreen(pointer: 2, item: 1, main: 1, separateSpaces: true) == 2)
        #expect(PanelGeometry.chooseScreen(pointer: 2, item: 1, main: 1, separateSpaces: false) == 1)
        #expect(PanelGeometry.chooseScreen(pointer: 2, item: nil, main: 3, separateSpaces: false) == 3)
        #expect(PanelGeometry.chooseScreen(pointer: nil, item: 1, main: 3, separateSpaces: true) == 1)
        #expect(PanelGeometry.chooseScreen(pointer: Int?.none, item: nil, main: nil, separateSpaces: true) == nil)
    }

    @Test func topEdgeIsFourPointsUnderTheItem() {
        let frame = PanelGeometry.frame(size: CGSize(width: 360, height: 300), anchor: button, visible: visible)
        #expect(button.minY - frame.maxY == 4)
    }

    @Test func resizeKeepsTheTopEdge() {
        let start = PanelGeometry.frame(size: CGSize(width: 320, height: 200), anchor: button, visible: visible)
        let grown = CGRect(x: start.minX, y: start.minY, width: 320, height: 260)
        let fixed = PanelGeometry.reanchored(grown, top: start.maxY, visible: visible)
        #expect(fixed.maxY == start.maxY)
        #expect(fixed.height == 260)
        let huge = CGRect(x: start.minX, y: start.minY, width: 320, height: 4000)
        let capped = PanelGeometry.reanchored(huge, top: start.maxY, visible: visible)
        #expect(capped.height == PanelGeometry.maxHeight(visible: visible))
        #expect(capped.minY >= visible.minY + 8)
    }
}

@Suite("Menu bar panel: routes and fixture (checklist C5, C6, E4)")
struct PanelRouteTests {
    @Test func urls() {
        #expect(PanelRoute.open.url == "summon://panel")
        #expect(PanelRoute.close.url == "summon://panel/close")
    }

    @Test func parsesPanelURLs() {
        #expect(PanelRoute.parse(host: "panel", pathComponents: []) == .open)
        #expect(PanelRoute.parse(host: "panel", pathComponents: ["/"]) == .open)
        #expect(PanelRoute.parse(host: "panel", pathComponents: ["/", "open"]) == .open)
        #expect(PanelRoute.parse(host: "panel", pathComponents: ["/", "close"]) == .close)
        #expect(PanelRoute.parse(host: "panel", pathComponents: ["/", "explode"]) == nil)
        #expect(PanelRoute.parse(host: "menu", pathComponents: []) == nil)
        #expect(PanelRoute.parse(host: nil, pathComponents: []) == nil)
    }

    @Test func roundTripsThroughURL() throws {
        for route in [PanelRoute.open, .close] {
            let url = try #require(URL(string: route.url))
            #expect(PanelRoute.parse(host: url.host, pathComponents: url.pathComponents) == route)
        }
    }

    @Test func fixture() {
        #expect(PanelFixture.rowCount(for: "tall") == PanelFixture.tallRowCount)
        #expect(PanelFixture.rowCount(for: "TALL") == PanelFixture.tallRowCount)
        #expect(PanelFixture.rowCount(for: nil) == 0)
        #expect(PanelFixture.rowCount(for: "short") == 0)
    }
}

@Suite("Menu bar panel: agent elapsed time (E1)")
struct PanelClockTests {
    let start = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [(0.0, "00:00"), (9.9, "00:09"), (65, "01:05"), (600, "10:00"), (3599, "59:59"), (3600, "60:00"), (7322, "122:02")])
    func formatsMinutesAndSeconds(offset: TimeInterval, expected: String) {
        #expect(PanelClock.elapsed(from: start, to: start.addingTimeInterval(offset)) == expected)
    }

    @Test func clockSkewNeverGoesNegative() {
        #expect(PanelClock.elapsed(from: start, to: start.addingTimeInterval(-30)) == "00:00")
    }
}

@Suite("Menu bar panel: B1 timing (≤ 200 ms warm from mouse-down)")
struct PanelTimingTests {
    @Test func measuresFromMouseDown() {
        let ms = PanelTiming.milliseconds(mouseDown: 100.0, orderedFront: 100.12) ?? -1
        #expect(abs(ms - 120) < 0.001)
        #expect(PanelTiming.milliseconds(mouseDown: nil, orderedFront: 5) == nil)
        #expect(PanelTiming.milliseconds(mouseDown: 6, orderedFront: 5) == nil)
    }

    @Test func budgetIs200Milliseconds() {
        #expect(PanelTiming.budgetMilliseconds == 200)
        #expect(PanelTiming.withinBudget(200))
        #expect(!PanelTiming.withinBudget(200.1))
    }
}

@Suite("Menu bar panel: stray-typing guard for hotkey and URL/CLI opens")
struct PanelOpenGuardTests {
    @Test func onlyURLAndCLIOpensSkipSearchFocus() {
        #expect(PanelOpenGuard.focusesSearch(.click))
        #expect(PanelOpenGuard.focusesSearch(.hotKey))
        #expect(!PanelOpenGuard.focusesSearch(.code))
    }

    @Test(arguments: [PanelOpenSource.hotKey, .code])
    func returnIsIgnoredBrieflyAfterANonClickOpen(source: PanelOpenSource) {
        #expect(!PanelOpenGuard.acceptsReturn(source: source, openedAt: 10, now: 10.0))
        #expect(!PanelOpenGuard.acceptsReturn(source: source, openedAt: 10, now: 10.29))
        #expect(PanelOpenGuard.acceptsReturn(source: source, openedAt: 10, now: 10.3))
        #expect(PanelOpenGuard.acceptsReturn(source: source, openedAt: 10, now: 12))
    }

    @Test func clickOpensAcceptReturnAtOnce() {
        #expect(PanelOpenGuard.acceptsReturn(source: .click, openedAt: 10, now: 10))
        #expect(PanelOpenGuard.acceptsReturn(source: nil, openedAt: nil, now: 10))
        #expect(PanelOpenGuard.acceptsReturn(source: .code, openedAt: nil, now: 10))
    }
}

@Suite("Menu bar panel: summon:// URLs on cold launch")
struct LaunchURLQueueTests {
    let menu = URL(string: "summon://menu/style.theme")!
    let panel = URL(string: "summon://panel")!

    @Test func urlsBeforeThePanelExistsAreQueuedNotDropped() {
        var queue = LaunchURLQueue()
        #expect(queue.receive([menu]).isEmpty)
        #expect(queue.receive([panel]).isEmpty)
        #expect(queue.markReady() == [menu, panel])
        #expect(queue.pending.isEmpty)
    }

    @Test func urlsAfterReadyPassStraightThrough() {
        var queue = LaunchURLQueue()
        #expect(queue.markReady().isEmpty)
        #expect(queue.receive([menu]) == [menu])
        #expect(queue.pending.isEmpty)
        #expect(queue.markReady().isEmpty)
    }
}
