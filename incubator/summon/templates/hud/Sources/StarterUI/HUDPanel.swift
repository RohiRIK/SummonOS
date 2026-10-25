import AppKit
import StarterCore
import SwiftUI

/// A small floating panel that stays above other apps' windows and never takes the keyboard from the app people
/// are typing in. It follows them across Spaces and over full-screen apps, and stays out of Mission Control and ⌘`.
@MainActor
final class HUDPanel: NSPanel {
    static func make() -> HUDPanel {
        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 48),
                             styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false // NSPanel's default is true: the HUD would vanish when you click elsewhere
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isMovable = false // HUDDragArea moves it, so it can snap when released
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }

    // Never key: clicks on its buttons work, keystrokes stay with the frontmost app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the HUD panel: shows and hides it, keeps it in its corner, and snaps it there after a drag or a throw.
@MainActor
public final class HUDController: NSObject {
    private let panel = HUDPanel.make()
    private let model: StarterModel
    private var observers: [NSObjectProtocol] = []

    public var isVisible: Bool { panel.isVisible }

    public init<Content: View>(model: StarterModel, menu: NSMenu, @ViewBuilder content: () -> Content) {
        self.model = model
        super.init()
        let host = NSHostingView(rootView: content())
        host.sizingOptions = [.preferredContentSize]
        host.menu = menu // right-click anywhere on the HUD
        panel.contentView = host
        model.dragEnded = { [weak self] velocity in self?.snap(velocity: velocity) }
        // A new display arrangement or a resized Dock: put it back in its corner.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(animated: false) }
        })
        // SwiftUI resizes the panel when the content changes (size setting, longer time): keep the corner.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                                object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(animated: false) }
        })
    }

    public func show() {
        place(animated: false)
        panel.orderFrontRegardless() // shows without activating the app
        model.isHUDVisible = true
    }

    public func hide() {
        panel.orderOut(nil)
        model.isHUDVisible = false
    }

    public func toggle() { isVisible ? hide() : show() }

    public func setOpacity(_ value: Double) {
        panel.alphaValue = CGFloat(min(1, max(0.25, value)))
    }

    /// Moves to `corner`, from the right-click menu or Settings.
    public func move(to corner: Corner) {
        model.corner = corner
        place(animated: true)
    }

    private var screen: NSScreen? { panel.screen ?? NSScreen.main }

    private func place(animated: Bool) {
        guard let visible = screen?.visibleFrame else { return }
        let target = CornerSnap.frame(of: panel.frame.size, in: model.corner, of: visible)
        guard target != panel.frame else { return }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1) // quick, soft landing
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    /// After a drag: the nearest corner where the throw would land (Reduce Motion: no throw, no glide).
    private func snap(velocity: CGVector) {
        guard let visible = screen?.visibleFrame else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.corner = CornerSnap.corner(for: panel.frame, velocity: reduceMotion ? .zero : velocity, in: visible)
        place(animated: true)
    }
}

/// The HUD's background: drag it from anywhere. Moves the window under the pointer, then reports the release
/// velocity so the controller can snap it to a corner. Clicks go through to it even though the panel is never key.
struct HUDDragArea: NSViewRepresentable {
    let ended: @MainActor (CGVector) -> Void

    final class DragView: NSView {
        var ended: @MainActor (CGVector) -> Void = { _ in }
        private var grab = NSPoint.zero
        private var origin = NSPoint.zero
        private var samples: [(point: NSPoint, time: TimeInterval)] = []

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            grab = NSEvent.mouseLocation
            origin = window?.frame.origin ?? .zero
            samples = [(grab, event.timestamp)]
        }

        override func mouseDragged(with event: NSEvent) {
            let point = NSEvent.mouseLocation
            window?.setFrameOrigin(NSPoint(x: origin.x + point.x - grab.x, y: origin.y + point.y - grab.y))
            samples.append((point, event.timestamp))
            if samples.count > 6 { samples.removeFirst() }
        }

        override func mouseUp(with event: NSEvent) {
            guard samples.count > 1, let first = samples.first, let last = samples.last else { return } // a click
            let time = max(last.time - first.time, 0.001)
            let resting = event.timestamp - last.time > 0.08 // held still before letting go: no throw
            ended(resting ? .zero : CGVector(dx: (last.point.x - first.point.x) / time, dy: (last.point.y - first.point.y) / time))
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.ended = ended
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.ended = ended
    }
}
