import AppKit
import Observation
import os
import SummonCore
import SwiftUI

// The menu bar container: NSStatusItem + a nonactivating NSPanel, replacing MenuBarExtra.
// Spec: docs/menubar-panel.md (interaction spec v1.5, IDs A1–G3). Every open/close decision is made by
// `PanelDismissal` in SummonCore, which is unit-tested on Linux; this file only wires AppKit events to it.

/// Shared by every Summon panel.
public enum PanelConfig {
    /// Every Summon panel (this one and the crash alert) uses `.statusBar`, which sits above fullscreen apps (F1, F2).
    public static let level: NSWindow.Level = .statusBar
    /// Panel width in points.
    public static let width: CGFloat = 360
}

/// B1 timing and the D-rules monitor count, visible in Instruments (os_signpost) and Console / `log stream`:
/// `log stream --predicate 'subsystem == "local.macplugins.summon" AND category == "panel"'` (notice level, so no
/// `--level` flag is needed).
enum PanelTrace {
    static let log = Logger(subsystem: "local.macplugins.summon", category: "panel")
    static let signposter = OSSignposter(subsystem: "local.macplugins.summon", category: "panel")
}

/// Observable state the SwiftUI content reads. Only `PanelController` writes it.
@MainActor
@Observable
public final class PanelState {
    /// True from `open()` until `close(_:)`. Drives the live refresh loop (E1) so it never runs while hidden.
    public internal(set) var isOpen = false
    /// Bumped on every open. The view shows a running agent only once this open's first refresh is done (E5).
    public internal(set) var session = 0
    /// Height cap for the visible frame of the screen the panel is on (E4).
    public internal(set) var maxHeight: CGFloat = 600
    /// E4 fixture rows (`PanelFixture`), 0 normally.
    public internal(set) var fixtureRows = 0
    /// Bumped once the panel is actually key, so the view focuses its search field then (A1, A2, G1); focus set
    /// before the window is key is dropped.
    public internal(set) var focusRequest = 0

    public init() {}

    static func preview() -> PanelState {
        let state = PanelState()
        state.isOpen = true
        return state
    }
}

/// What the panel content can ask the controller to do. Every path closes through the controller.
public struct PanelActions {
    /// D3: an action ran; close and return focus.
    public var finish: () -> Void
    /// D1: Esc.
    public var escape: () -> Void
    /// Close, then open Activity.
    public var openActivity: () -> Void
    /// D6/B5: close, then open Settings.
    public var openSettings: () -> Void
    /// D6/B6: close, then quit.
    public var quit: () -> Void
    /// E3/E4: the content's displayed height changed; the controller sets the panel frame once, top edge pinned.
    public var resize: (CGFloat) -> Void
    /// False for ~300 ms after a hotkey or URL/CLI open, so a stray Return can't run an entry (`PanelOpenGuard`).
    public var acceptsReturn: () -> Bool

    public init(finish: @escaping () -> Void, escape: @escaping () -> Void,
                openActivity: @escaping () -> Void = {},
                openSettings: @escaping () -> Void, quit: @escaping () -> Void,
                resize: @escaping (CGFloat) -> Void = { _ in }, acceptsReturn: @escaping () -> Bool = { true }) {
        self.finish = finish
        self.escape = escape
        self.openActivity = openActivity
        self.openSettings = openSettings
        self.quit = quit
        self.resize = resize
        self.acceptsReturn = acceptsReturn
    }

    static var preview: PanelActions { PanelActions(finish: {}, escape: {}, openActivity: {}, openSettings: {}, quit: {}) }
}

/// A borderless, nonactivating panel that can take keystrokes without activating Summon (A1, A2, A5, A6).
@MainActor
final class StatusPanel: NSPanel {
    var onEscape: (() -> Void)?

    /// Built through the inherited initializer so the style mask is set at creation: changing
    /// `.nonactivatingPanel` later is unreliable.
    static func make() -> StatusPanel {
        let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: PanelConfig.width, height: 200),
                                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = PanelConfig.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.setAccessibilityLabel("Summon")
        return panel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc anywhere in the panel (D1). The text field also handles it with onKeyPress; close is idempotent.
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

}

/// The only code that shows or hides the panel. Opens from the status item, the hotkey and code (C5–C7);
/// closes only on the spec's section D triggers, and every close removes its observers.
@MainActor
public final class PanelController: NSObject {
    public let state: PanelState
    private let statusItem: NSStatusItem
    private let panel: StatusPanel
    private let openActivityHandler: () -> Void
    private let openSettingsHandler: () -> Void
    /// Loads the menu and sets its start level before every open (`summon://menu/<id>` passes an entry).
    private let prepare: (String?) -> Void
    private var session: PanelSession?
    private var previousApp: NSRunningApplication?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var anchorTop: CGFloat?
    private var visibleFrame: CGRect = .zero
    private var lastContentHeight: CGFloat?
    private var hotKeyFilter = HotKeyRepeatFilter()
    private var pendingEntry: String?
    private var mouseDownMonitor: Any?
    private var lastMouseDown: TimeInterval?
    private var openInterval: OSSignpostIntervalState?
    private var pendingSource: PanelOpenSource?
    private var openSource: PanelOpenSource?
    private var openedAt: TimeInterval?

    /// Live observers right now; 0 whenever the panel is closed (D rules). Logged on every close.
    public var activeObserverCount: Int { observers.count }
    public var isOpen: Bool { state.isOpen }

    /// `content` is the panel's single SwiftUI view; it is hosted once and kept for the app's lifetime.
    public init<Content: View>(openActivity: @escaping () -> Void = {},
                               openSettings: @escaping () -> Void,
                               prepare: @escaping (String?) -> Void,
                               @ViewBuilder content: (PanelState, PanelActions) -> Content) {
        state = PanelState()
        panel = StatusPanel.make()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        openActivityHandler = openActivity
        openSettingsHandler = openSettings
        self.prepare = prepare
        super.init()
        #if DEBUG
        // E4 fixture: debug builds only.
        state.fixtureRows = PanelFixture.rowCount(for: UserDefaults.standard.string(forKey: PanelFixture.defaultsKey))
        #endif

        let actions = PanelActions(
            finish: { [weak self] in self?.handle(.actionFinished) },
            escape: { [weak self] in self?.handle(.escapePressed) },
            openActivity: { [weak self] in self?.handle(.activityChosen) },
            openSettings: { [weak self] in self?.handle(.settingsChosen) },
            quit: { [weak self] in self?.handle(.quitChosen) },
            resize: { [weak self] height in self?.contentHeightChanged(height) },
            acceptsReturn: { [weak self] in
                guard let self else { return true }
                return PanelOpenGuard.acceptsReturn(source: self.openSource, openedAt: self.openedAt,
                                                    now: ProcessInfo.processInfo.systemUptime)
            }
        )
        let host = NSHostingController(rootView: content(state, actions))
        // We size the window ourselves (`contentHeightChanged`), so the hosting controller must not: its own resize
        // keeps the bottom-left origin and would move the top edge for a frame before we put it back (E3).
        host.sizingOptions = []
        panel.contentViewController = host
        panel.onEscape = { [weak self] in self?.handle(.escapePressed) }

        if let button = statusItem.button {
            button.image = MenuBarLabel.statusImage
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Summon") // G3
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Left opens the panel, right (or ⌃-click) shows the menu (B1, B3).
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // B1: the "PanelOpen" signpost interval starts at the status item's mouse-down (this local monitor, which
        // sees only Summon's own events, lives for the app's lifetime and never closes anything) and ends right
        // after makeKeyAndOrderFront in show().
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, let window = self.statusItem.button?.window, event.window === window {
                    self.mouseDownReceived(at: event.timestamp)
                }
            }
            return event
        }
    }

    private func mouseDownReceived(at timestamp: TimeInterval) {
        endOpenInterval(opened: false) // a previous press that never opened
        lastMouseDown = timestamp
        guard !isOpen else { return }
        openInterval = PanelTrace.signposter.beginInterval("PanelOpen", id: PanelTrace.signposter.makeSignpostID())
    }

    private func endOpenInterval(opened: Bool) {
        guard let interval = openInterval else { return }
        openInterval = nil
        if opened {
            PanelTrace.signposter.endInterval("PanelOpen", interval, "ordered front")
        } else {
            PanelTrace.signposter.endInterval("PanelOpen", interval, "no open")
        }
    }

    // MARK: Public entry points (C5–C7)

    public func toggle() { isOpen ? close() : open() }

    /// Idempotent (C6): opening an open panel does nothing.
    public func open() {
        pendingSource = .code
        handle(.openFromCode)
    }

    /// `summon://menu/<id>`: open the panel at that Summon Menu entry, or move an open panel there.
    public func open(at entry: String?) {
        pendingEntry = entry
        if isOpen {
            prepare(entry)
            pendingEntry = nil
        } else {
            pendingSource = .code
            handle(.openFromCode)
        }
    }

    /// Idempotent (C6): closing a closed panel does nothing.
    public func close() { handle(.closeFromCode) }

    /// C7: safe from any thread or task; hops to the main actor.
    public nonisolated func requestOpen() {
        Task { @MainActor [weak self] in self?.open() }
    }

    public nonisolated func requestClose() {
        Task { @MainActor [weak self] in self?.close() }
    }

    /// The panel hotkey's press (C1–C3). A held key opens once.
    public func hotKeyPressed() {
        guard hotKeyFilter.press(at: ProcessInfo.processInfo.systemUptime) else { return }
        pendingSource = .hotKey
        handle(.hotKey)
    }

    public func hotKeyReleased() {
        hotKeyFilter.release()
    }

    /// The status item's live label (`MenuBarStatusWatcher`): icon only when `title` is nil, else icon and title.
    /// Monospaced digits keep the item's width steady while the clock ticks.
    /// `attention`: the panel has something in Needs attention; the icon turns orange, as macOS marks a status item
    /// that wants a look, and VoiceOver hears it.
    public func setStatusLabel(title: String?, accessibilityLabel: String, attention: Bool = false) {
        guard let button = statusItem.button else { return }
        let tint: NSColor? = attention ? .systemOrange : nil
        if button.contentTintColor != tint { button.contentTintColor = tint }
        let accessibilityLabel = attention ? accessibilityLabel + ", needs attention" : accessibilityLabel
        let text = title ?? ""
        if button.title != text {
            button.title = text
            button.imagePosition = title == nil ? .imageOnly : .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        if button.accessibilityLabel() != accessibilityLabel { button.setAccessibilityLabel(accessibilityLabel) }
    }

    /// D12: the crash alert is about to take key. Close without handing focus back; the alert gets it.
    public func yieldToCrashAlert() {
        handle(.crashAlertPresenting)
    }

    // MARK: Decisions

    private func handle(_ event: PanelEvent) {
        switch PanelDismissal.decide(event, isOpen: isOpen, session: session) {
        case .ignore:
            break
        case .open:
            show()
        case .close(let reason):
            hide(reason)
            switch reason {
            case .activity: openActivityHandler()
            case .settings: openSettingsHandler()
            case .quit: NSApp.terminate(nil)
            default: break
            }
        case .showMenu:
            showMenu()
        case .closeThenShowMenu:
            hide(.contextMenu)
            showMenu()
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let right = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        guard !right else {
            endOpenInterval(opened: false)
            return handle(.statusItemRightClick)
        }
        // B1 proof: the "PanelOpen" interval began at mouse-down and ends in show(); the log line gives the same span.
        let wasOpen = isOpen
        pendingSource = .click
        handle(.statusItemLeftClick)
        endOpenInterval(opened: false) // closed by this click: nothing to measure
        let down = lastMouseDown ?? event?.timestamp
        lastMouseDown = nil
        if !wasOpen, isOpen,
           let ms = PanelTiming.milliseconds(mouseDown: down, orderedFront: ProcessInfo.processInfo.systemUptime) {
            let verdict = PanelTiming.withinBudget(ms) ? "within" : "OVER"
            PanelTrace.log.notice("B1 panel ordered front \(ms, format: .fixed(precision: 1), privacy: .public) ms after mouse-down (\(verdict, privacy: .public) the 200 ms budget)")
        }
    }

    // MARK: Open

    private func show() {
        let own = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == own ? nil : front
        session = PanelSession(previousAppPID: previousApp?.processIdentifier, ownPID: own)
        prepare(pendingEntry)
        pendingEntry = nil
        let source = pendingSource ?? .code
        pendingSource = nil
        openSource = source
        openedAt = ProcessInfo.processInfo.systemUptime
        state.session += 1
        state.isOpen = true
        place()
        // The panel is nonactivating: this makes it key without activating Summon (A1, A5, A6).
        panel.makeKeyAndOrderFront(nil)
        endOpenInterval(opened: source == .click) // B1: mouse-down → ordered front
        statusItem.button?.highlight(true)
        installObservers()
        // After the current event (the status button's mouse-up tracking can reset its highlight) and once the
        // panel is key: re-assert the highlight (B1) and focus the search field (A1, A2, G1). URL/CLI opens don't
        // focus it, so typing meant for another app doesn't land in the search (Sam's review).
        let focus = PanelOpenGuard.focusesSearch(source)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOpen else { return }
            self.statusItem.button?.highlight(true)
            if focus { self.state.focusRequest += 1 }
            // VoiceOver: a nonactivating panel opened from the keyboard or a URL doesn't move the VoiceOver cursor.
            if let text = PanelOpenGuard.announcement(source, focusesSearch: focus) {
                NSAccessibility.post(element: self.panel, notification: .announcementRequested, userInfo: [
                    .announcement: text,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
            }
        }
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        guard let target = PanelGeometry.chooseScreen(pointer: pointerScreen, item: statusItem.button?.window?.screen,
                                                      main: NSScreen.main,
                                                      separateSpaces: NSScreen.screensHaveSeparateSpaces) else { return }
        visibleFrame = target.visibleFrame
        state.maxHeight = PanelGeometry.maxHeight(visible: visibleFrame)

        var anchor = CGRect(x: target.frame.maxX - 60, y: target.frame.maxY - 24, width: 24, height: 24)
        if let button = statusItem.button, let window = button.window, let buttonScreen = window.screen {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            anchor = PanelGeometry.anchor(rect, from: buttonScreen.frame, to: target.frame)
        }
        var height = lastContentHeight
        if height == nil {
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            height = panel.contentViewController?.view.fittingSize.height
        }
        let size = CGSize(width: PanelConfig.width, height: max(height ?? panel.frame.height, 1))
        let frame = PanelGeometry.frame(size: size, anchor: anchor, visible: visibleFrame)
        panel.setFrame(frame, display: true)
        anchorTop = frame.maxY
    }

    /// E3/E4: one `setFrame` with the final frame, top edge pinned and clamped, so the top never jumps.
    private func contentHeightChanged(_ height: CGFloat) {
        lastContentHeight = height
        guard isOpen, let top = anchorTop else { return }
        let target = CGRect(x: panel.frame.minX, y: panel.frame.minY, width: panel.frame.width, height: height)
        let frame = PanelGeometry.reanchored(target, top: top, visible: visibleFrame)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: Close

    private func hide(_ reason: PanelCloseReason) {
        guard isOpen else { return }
        let before = observers.count
        removeObservers()
        statusItem.button?.highlight(false)
        panel.orderOut(nil)
        state.isOpen = false
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if PanelDismissal.focusAction(after: reason, frontmostPID: frontmost, session: session) == .activatePrevious,
           let previous = previousApp, !previous.isTerminated {
            _ = previous.activate()
        }
        session = nil
        previousApp = nil
        anchorTop = nil
        // D rules proof: how many monitors this open installed, and that none are left (expect "after 0").
        PanelTrace.log.notice("panel closed (\(reason.rawValue, privacy: .public)); active monitors: before \(before, privacy: .public), after \(self.observers.count, privacy: .public)")
    }

    // MARK: Right-click menu (B3–B6)

    private func showMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: "Quit \(Self.appName)", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.items = [settings, quit]
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func menuSettings() { handle(.settingsChosen) }
    @objc private func menuQuit() { handle(.quitChosen) }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Summon"
    }

    // MARK: Section D observers (no global click monitor)

    private func installObservers() {
        removeObservers()
        let workspace = NSWorkspace.shared.notificationCenter
        // D4: another app became frontmost. The same previous app does not close (decision 2).
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            return app.map { .frontmostAppChanged(pid: $0.processIdentifier) }
        }
        // D5, F3: Space change (also fired by most Mission Control transitions; F5 is a Mac check).
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { _ in .activeSpaceChanged }
        // D7: display sleep, system sleep, fast user switch.
        observe(workspace, NSWorkspace.screensDidSleepNotification) { _ in .displaySlept }
        observe(workspace, NSWorkspace.willSleepNotification) { _ in .systemWillSleep }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { _ in .screenLocked }
        // D7: screen lock (⌃⌘Q) is only announced on the distributed center.
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { _ in .screenLocked }
        // Monitors and the panel follow screen changes (resolution, displays) without closing.
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
            return nil
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ map: @escaping @Sendable (Notification) -> PanelEvent?) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let event = map(note)
            MainActor.assumeIsolated {
                if let event { self?.handle(event) }
            }
        }
        observers.append((center, token))
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
