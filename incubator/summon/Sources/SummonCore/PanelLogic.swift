import Foundation
#if canImport(CoreGraphics)
// On Darwin, Foundation exposes CGRect but not its geometry accessors (minX, height, ==); CoreGraphics does.
import CoreGraphics
#endif

// Pure decisions behind the menu bar panel (`PanelController` in SummonMenuUI). No AppKit here, so every rule
// below is unit-tested on Linux and macOS. IDs (A1…G3) refer to the panel interaction spec v1.5.

/// Why the panel closed. Every close goes through `PanelController.close(_:)` with one of these.
public enum PanelCloseReason: String, Sendable, CaseIterable {
    /// D1: Esc in the panel.
    case escape
    /// D2, B2, C2: the status item or ⌃⌥Space while open.
    case toggle
    /// D3, A4: an action ran (Return, or a row's primary action).
    case action
    /// D4: another app became frontmost.
    case appSwitch
    /// D5, F3: the active Space changed.
    case spaceChange
    /// D6, B5: Settings… was chosen.
    case settings
    /// D6, B6: Quit was chosen.
    case quit
    /// D7: screen locked, display slept, or the Mac is going to sleep.
    case lockOrSleep
    /// B4: right-click while open; the panel closes, then the menu shows.
    case contextMenu
    /// C6: `PanelController.close()` called from code.
    case programmatic
    /// D12: the crash alert is about to take key; it, not the previous app, gets focus.
    case crashAlert
}

/// Everything the controller can observe. Only some of these close the panel (spec section D).
public enum PanelEvent: Equatable, Sendable {
    case statusItemLeftClick
    /// Right-click or ⌃-click on the status item (B3).
    case statusItemRightClick
    case hotKey
    case openFromCode
    case closeFromCode
    case escapePressed
    case actionFinished
    case settingsChosen
    case quitChosen
    /// `NSWorkspace.didActivateApplicationNotification` with the new frontmost app's pid.
    case frontmostAppChanged(pid: Int32)
    case activeSpaceChanged
    case screenLocked
    case displaySlept
    case systemWillSleep
    /// D12: Summon's crash alert is about to order front.
    case crashAlertPresenting
    // Observed but never close the panel (D8–D11, decision 2).
    case clickInsidePanel
    case pointerLeftPanel
    case idle
    case contentUpdated
    case notificationBanner
    /// The panel lost key status, e.g. the user clicked back into the previous app. Not a close trigger.
    case panelResignedKey
}

/// What the controller should do with an event.
public enum PanelDecision: Equatable, Sendable {
    case ignore
    case open
    case close(PanelCloseReason)
    /// B3: right-click while closed.
    case showMenu
    /// B4: right-click while open.
    case closeThenShowMenu
}

/// The app that was frontmost when the panel opened, and our own pid.
public struct PanelSession: Equatable, Sendable {
    public var previousAppPID: Int32?
    public var ownPID: Int32

    public init(previousAppPID: Int32?, ownPID: Int32) {
        self.previousAppPID = previousAppPID
        self.ownPID = ownPID
    }
}

/// After a close, whether to hand focus back to the app that was frontmost before the panel opened.
public enum PanelFocusAction: Equatable, Sendable {
    /// The previous app is still frontmost (the panel never activated us), so ordering out is enough.
    case none
    /// Something activated Summon while the panel was open; activate the previous app again (A3).
    case activatePrevious
}

public enum PanelDismissal {
    /// The only place that decides open/close. `isOpen` is the controller's state; `session` is nil when closed.
    public static func decide(_ event: PanelEvent, isOpen: Bool, session: PanelSession?) -> PanelDecision {
        switch event {
        case .statusItemLeftClick, .hotKey:
            return isOpen ? .close(.toggle) : .open
        case .statusItemRightClick:
            return isOpen ? .closeThenShowMenu : .showMenu
        case .openFromCode:
            return isOpen ? .ignore : .open
        case .closeFromCode:
            return isOpen ? .close(.programmatic) : .ignore
        case .settingsChosen:
            // The menu can be chosen while the panel is already closed (B4 closed it); Settings still opens.
            return .close(.settings)
        case .quitChosen:
            return .close(.quit)
        default:
            break
        }
        guard isOpen else { return .ignore }
        switch event {
        case .escapePressed:
            return .close(.escape)
        case .actionFinished:
            return .close(.action)
        case .frontmostAppChanged(let pid):
            // Decision 2: clicking back into the same previous app keeps the panel open.
            if let previous = session?.previousAppPID, pid == previous { return .ignore }
            // Summon itself activating (Settings, Activity) is handled by those paths, not as an app switch.
            if let own = session?.ownPID, pid == own { return .ignore }
            return .close(.appSwitch)
        case .activeSpaceChanged:
            return .close(.spaceChange)
        case .screenLocked, .displaySlept, .systemWillSleep:
            return .close(.lockOrSleep)
        case .crashAlertPresenting:
            return .close(.crashAlert)
        default:
            // D8–D11 and resign-key: no generic click-elsewhere dismissal.
            return .ignore
        }
    }

    /// Whether a close for `reason` hands focus back (A3, A4, C2, rules under D). App switch, Space change,
    /// Settings and Quit leave focus where the user or macOS put it; lock/sleep has nothing to return to.
    public static func restoresFocus(after reason: PanelCloseReason) -> Bool {
        switch reason {
        case .escape, .toggle, .action, .programmatic, .contextMenu:
            return true
        case .appSwitch, .spaceChange, .settings, .quit, .lockOrSleep, .crashAlert:
            return false
        }
    }

    /// The concrete focus step after a close. `frontmostPID` is the frontmost app at close time.
    public static func focusAction(after reason: PanelCloseReason, frontmostPID: Int32?,
                                   session: PanelSession?) -> PanelFocusAction {
        guard restoresFocus(after: reason), let session, let previous = session.previousAppPID,
              previous != session.ownPID else { return .none }
        // The nonactivating panel leaves the previous app frontmost; ordering out returns its key window.
        // Only when Summon itself became frontmost do we activate the previous app again.
        return frontmostPID == session.ownPID ? .activatePrevious : .none
    }
}

/// C3: a held ⌃⌥Space must open the panel once, not flicker. `HotKeyCenter` reports presses and releases;
/// a press while the key is still held is swallowed. If a release is ever lost, a press `staleAfter` seconds after
/// the last one seen is treated as new, so the hotkey can never get stuck.
public struct HotKeyRepeatFilter: Sendable {
    public var staleAfter: TimeInterval
    private var held = false
    private var lastSeen: TimeInterval = -.infinity

    public init(staleAfter: TimeInterval = 1.0) {
        self.staleAfter = staleAfter
    }

    /// True when this press should toggle the panel.
    public mutating func press(at now: TimeInterval) -> Bool {
        defer { lastSeen = now }
        if held && now - lastSeen < staleAfter { return false }
        held = true
        return true
    }

    public mutating func release() {
        held = false
    }
}

/// How the panel was opened. A click is deliberate; a hotkey or a URL/CLI open can land while the user is typing
/// somewhere else (Sam's review of #61).
public enum PanelOpenSource: String, Sendable, CaseIterable {
    case click
    case hotKey
    /// `summon panel`, `summon://panel`, `summon://menu/<id>`, `PanelController.open()`.
    case code
}

/// Guards against stray typing after a non-click open: URL/CLI opens don't focus the search field, and Return is
/// ignored for `returnGrace` seconds after any non-click open, so a keystroke meant for another app can't run a
/// menu entry's shell action.
public enum PanelOpenGuard {
    public static let returnGrace: TimeInterval = 0.3

    /// Whether this open focuses the search field (A1 for click and hotkey; not for URL/CLI opens).
    public static func focusesSearch(_ source: PanelOpenSource) -> Bool {
        source != .code
    }

    /// Whether Return may run the selected entry `now`, for a panel opened from `source` at `openedAt`.
    public static func acceptsReturn(source: PanelOpenSource?, openedAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let source, source != .click else { return true }
        guard let openedAt else { return true }
        return now - openedAt >= returnGrace
    }
}

/// Holds `summon://` URLs that arrive before the panel exists (cold launch, Sam's review of #61), and hands them back
/// once `markReady()` is called. After that, URLs pass straight through.
public struct LaunchURLQueue: Sendable {
    public private(set) var pending: [URL] = []
    public private(set) var isReady = false

    public init() {}

    /// The URLs to handle now: all of them when ready, none (they are queued) before.
    public mutating func receive(_ urls: [URL]) -> [URL] {
        guard isReady else {
            pending += urls
            return []
        }
        return urls
    }

    /// Marks the panel ready and returns the queued URLs, oldest first. A second call returns nothing.
    public mutating func markReady() -> [URL] {
        isReady = true
        defer { pending = [] }
        return pending
    }
}

/// B1 proof: milliseconds from the status item's mouse-down to the panel ordered front, and whether that meets the
/// spec's warm budget (≤ 200 ms).
public enum PanelTiming {
    public static let budgetMilliseconds: Double = 200

    /// nil when there is no mouse-down to measure from, or it came after `orderedFront` (clock or event mix-up).
    public static func milliseconds(mouseDown: TimeInterval?, orderedFront: TimeInterval) -> Double? {
        guard let mouseDown, orderedFront >= mouseDown else { return nil }
        return (orderedFront - mouseDown) * 1000
    }

    public static func withinBudget(_ milliseconds: Double) -> Bool {
        milliseconds <= budgetMilliseconds
    }
}

/// Where the panel goes: under the status item, top edge fixed, clamped 8 pt inside the visible frame (B1, C1, E3,
/// E4, F2, F4). AppKit coordinates: origin bottom-left, y grows up.
public enum PanelGeometry {
    public static let margin: CGFloat = 8
    public static let gap: CGFloat = 4

    /// Tallest the panel may get on a screen with this visible frame (E4); content scrolls past it.
    public static func maxHeight(visible: CGRect) -> CGFloat {
        max(visible.height - 2 * margin, 0)
    }

    /// C1: the pointer's display when every display has its own menu bar (Displays have separate Spaces), otherwise
    /// the display that shows the status item, then the main display.
    public static func chooseScreen<Screen: Equatable>(pointer: Screen?, item: Screen?, main: Screen?,
                                                       separateSpaces: Bool) -> Screen? {
        if separateSpaces, let pointer { return pointer }
        return item ?? main ?? pointer
    }

    /// The status item's rect moved to `target` when the pointer is on another display (C1, F4): same distance
    /// from the right edge and from the top as on the display the button reports.
    public static func anchor(_ button: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source != target else { return button }
        let fromRight = source.maxX - button.minX
        let fromTop = source.maxY - button.minY
        return CGRect(x: target.maxX - fromRight, y: target.maxY - fromTop, width: button.width, height: button.height)
    }

    /// The panel frame for content of `size` under `anchor` inside `visible`.
    public static func frame(size: CGSize, anchor: CGRect, visible: CGRect) -> CGRect {
        let height = min(size.height, maxHeight(visible: visible))
        let width = min(size.width, max(visible.width - 2 * margin, 0))
        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX + margin), visible.maxX - width - margin)
        // In fullscreen with the menu bar hidden the visible frame is the whole screen; stay inside it (F2).
        let top = min(anchor.minY - gap, visible.maxY)
        var y = top - height
        y = max(y, visible.minY + margin)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }

    /// E3: after a resize, keep the top edge where it was and re-clamp to the bottom margin.
    public static func reanchored(_ frame: CGRect, top: CGFloat, visible: CGRect) -> CGRect {
        let height = min(frame.height, maxHeight(visible: visible))
        let y = max(top - height, visible.minY + margin)
        return CGRect(x: frame.minX, y: y.rounded(), width: frame.width, height: height)
    }
}

/// `summon://panel` opens the menu bar panel, `summon://panel/close` closes it (checklist C5, C6, D7).
/// The CLI (`summon panel [--close]`) opens these with `open -g`, so Summon is never activated (A1).
public enum PanelRoute: Equatable, Sendable {
    case open
    case close

    public static let host = "panel"

    public var url: String {
        self == .open ? "summon://panel" : "summon://panel/close"
    }

    /// The route for a `summon://` URL's host and path components (`URL.pathComponents`), or nil if not a panel URL.
    public static func parse(host: String?, pathComponents: [String]) -> PanelRoute? {
        guard host == Self.host else { return nil }
        let parts = pathComponents.filter { $0 != "/" && !$0.isEmpty }
        switch parts.first {
        case nil, "open": return .open
        case "close": return .close
        default: return nil
        }
    }
}

/// E4 fixture (debug builds only; `PanelController` ignores it in release): `defaults write local.macplugins.summon
/// PanelFixture tall` adds enough placeholder rows to exceed any screen, so the height cap and inner scroll can be
/// checked on a real Mac. Any other value: no rows.
public enum PanelFixture {
    public static let defaultsKey = "PanelFixture"
    public static let tallRowCount = 80

    public static func rowCount(for value: String?) -> Int {
        value?.lowercased() == "tall" ? tallRowCount : 0
    }
}

/// E1: the agent row's elapsed time, `mm:ss` (minutes keep counting past 59, so an hour reads `60:00`).
public enum PanelClock {
    public static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start).rounded(.down)))
        let minutes = seconds / 60
        let rest = seconds % 60
        return (minutes < 10 ? "0" : "") + "\(minutes):" + (rest < 10 ? "0" : "") + "\(rest)"
    }
}
