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
    /// Bumped on every open; the view resets its field and focus on change (A1, E5).
    public internal(set) var session = 0
    /// Height cap for the visible frame of the screen the panel is on (E4).
    public internal(set) var maxHeight: CGFloat = 600
    /// E4 fixture rows (`PanelFixture`), 0 normally.
    public internal(set) var fixtureRows = 0

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
    /// D6/B5: close, then open Settings.
    public var openSettings: () -> Void
    /// D6/B6: close, then quit.
    public var quit: () -> Void

    public init(finish: @escaping () -> Void, escape: @escaping () -> Void,
                openSettings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.finish = finish
        self.escape = escape
        self.openSettings = openSettings
        self.quit = quit
    }

    static var preview: PanelActions { PanelActions(finish: {}, escape: {}, openSettings: {}, quit: {}) }
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
    private let openSettingsHandler: () -> Void
    /// Loads the menu and sets its start level before every open (`summon://menu/<id>` passes an entry).
    private let prepare: (String?) -> Void
    private var session: PanelSession?
    private var previousApp: NSRunningApplication?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var anchorTop: CGFloat?
    private var visibleFrame: CGRect = .zero
    private var adjusting = false
    private var hotKeyFilter = HotKeyRepeatFilter()
    private var pendingEntry: String?
    private var mouseDownMonitor: Any?
    private var lastMouseDown: TimeInterval?

    /// Live observers right now; 0 whenever the panel is closed (D rules). Logged on every close.
    public var activeObserverCount: Int { observers.count }
    public var isOpen: Bool { state.isOpen }

    /// `content` is the panel's single SwiftUI view; it is hosted once and kept for the app's lifetime.
    public init<Content: View>(openSettings: @escaping () -> Void, prepare: @escaping (String?) -> Void,
                               @ViewBuilder content: (PanelState, PanelActions) -> Content) {
        state = PanelState()
        panel = StatusPanel.make()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
            openSettings: { [weak self] in self?.handle(.settingsChosen) },
            quit: { [weak self] in self?.handle(.quitChosen) }
        )
        let host = NSHostingController(rootView: content(state, actions))
        // The window follows SwiftUI's ideal size; `panelDidResize` keeps the top edge fixed (E3).
        host.sizingOptions = [.preferredContentSize]
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
        // B1: remember when the status item was pressed, so the open can be measured from mouse-down. A local
        // monitor sees only Summon's own events; it lives for the app's lifetime and never closes anything.
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, let window = self.statusItem.button?.window, event.window === window {
                    self.lastMouseDown = event.timestamp
                }
            }
            return event
        }
        // Resizes happen while open (E3); this observer lives as long as the panel, it is not a dismissal monitor.
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidResize(_:)),
                                               name: NSWindow.didResizeNotification, object: panel)
    }

    // MARK: Public entry points (C5–C7)

    public func toggle() { handle(isOpen ? .closeFromCode : .openFromCode) }

    /// Idempotent (C6): opening an open panel does nothing.
    public func open() { handle(.openFromCode) }

    /// `summon://menu/<id>`: open the panel at that Summon Menu entry, or move an open panel there.
    public func open(at entry: String?) {
        pendingEntry = entry
        if isOpen {
            prepare(entry)
            pendingEntry = nil
        } else {
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
        handle(.hotKey)
    }

    public func hotKeyReleased() {
        hotKeyFilter.release()
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
        guard !right else { return handle(.statusItemRightClick) }
        // B1 proof: the "PanelOpen" signpost interval covers click handling to ordered front, and the log line gives
        // the time from the status item's mouse-down (recorded by the local monitor) to ordered front.
        let interval = PanelTrace.signposter.beginInterval("PanelOpen", id: PanelTrace.signposter.makeSignpostID())
        let wasOpen = isOpen
        handle(.statusItemLeftClick)
        PanelTrace.signposter.endInterval("PanelOpen", interval)
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
        state.session += 1
        state.isOpen = true
        place()
        // The panel is nonactivating: this makes it key without activating Summon (A1, A5, A6).
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        installObservers()
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
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let fitting = panel.contentViewController?.view.fittingSize ?? panel.frame.size
        let size = CGSize(width: PanelConfig.width, height: max(fitting.height, 1))
        let frame = PanelGeometry.frame(size: size, anchor: anchor, visible: visibleFrame)
        adjusting = true
        panel.setFrame(frame, display: true)
        adjusting = false
        anchorTop = frame.maxY
    }

    @objc private func panelDidResize(_ note: Notification) {
        guard !adjusting, isOpen, let top = anchorTop else { return }
        let fixed = PanelGeometry.reanchored(panel.frame, top: top, visible: visibleFrame)
        guard fixed != panel.frame else { return }
        adjusting = true
        panel.setFrame(fixed, display: true, animate: false)
        adjusting = false
    }

    // MARK: Close

    private func hide(_ reason: PanelCloseReason) {
        guard isOpen else { return }
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
        // D rules proof: expect 0 on every close.
        PanelTrace.log.notice("panel closed (\(reason.rawValue, privacy: .public)); active monitors: \(self.observers.count, privacy: .public)")
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
