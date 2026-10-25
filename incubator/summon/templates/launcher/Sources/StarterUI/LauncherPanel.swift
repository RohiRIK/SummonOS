import AppKit
import SwiftUI

/// A borderless, nonactivating panel: it takes keystrokes over any app, even a full-screen one, without
/// activating this app, so the frontmost app keeps its menu bar.
@MainActor
final class LauncherPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// While set, the top edge stays here whatever height SwiftUI asks for: results grow the panel downward and
    /// the search field never moves.
    var pinnedTop: CGFloat?

    /// The style mask is set at creation: changing `.nonactivatingPanel` later is unreliable.
    static func make() -> LauncherPanel {
        let panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
                                  styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar // above other floating panels and full-screen apps
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false // the app is never active; the controller closes the panel
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none // appears at once
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }

    // A borderless panel refuses key status by default, so the search field would never get keys.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        if let pinnedTop { frame.origin.y = pinnedTop - frame.height }
        super.setFrame(frame, display: flag)
    }
}

/// Owns the launcher panel. It is made once at launch and kept hidden, so showing it is one `orderFront`
/// (pre-warmed). Opens from the hotkey, the menu bar menu or code; closes on Esc, on losing key (a click
/// elsewhere, another app activating), on a Space change, and after running an item.
@MainActor
public final class LauncherController: NSObject {
    private let panel = LauncherPanel.make()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let model: StarterModel

    public var isOpen: Bool { panel.isVisible }

    public init<Content: View>(model: StarterModel, @ViewBuilder content: () -> Content) {
        self.model = model
        super.init()
        let host = NSHostingView(rootView: content())
        host.sizingOptions = [.preferredContentSize] // the panel follows SwiftUI's ideal size
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        panel.onEscape = { [weak self] in self?.close() }
        model.close = { [weak self] in self?.close() }
    }

    public func toggle() { isOpen ? close() : open() }

    /// Idempotent. Centered on the screen with the pointer, its top a fifth of the way down, like Spotlight.
    public func open() {
        guard !isOpen else { return }
        model.prepareForOpen()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            let top = (visible.maxY - visible.height * 0.2).rounded()
            panel.pinnedTop = top
            panel.setFrame(NSRect(x: (visible.midX - size.width / 2).rounded(), y: top - size.height,
                                  width: size.width, height: size.height), display: false)
        }
        panel.makeKeyAndOrderFront(nil) // nonactivating: key without activating the app
        observe(NotificationCenter.default, NSWindow.didResignKeyNotification, object: panel)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
    }

    /// Idempotent. Every close removes its observers.
    public func close() {
        guard isOpen else { return }
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        panel.orderOut(nil)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: AnyObject? = nil) {
        let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        observers.append((center, token))
    }
}
