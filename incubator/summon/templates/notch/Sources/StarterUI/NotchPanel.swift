import AppKit
import Observation
import StarterCore
import SwiftUI

/// A borderless panel over the camera housing, above the menu bar. It never takes the keyboard and never
/// activates the app; it stays on every Space and out of Mission Control and ⌘`.
@MainActor
final class NotchPanel: NSPanel {
    static func make() -> NotchPanel {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 32),
                               styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                               backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar // above the menu bar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        return panel
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // AppKit keeps ordinary windows out of the menu bar; this one belongs there.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A hosting view that tells the model when the pointer enters or leaves, whether or not the app is active
/// (SwiftUI's hover only follows the pointer in an active app's windows).
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var hoverChanged: @MainActor (Bool) -> Void = { _ in }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }
}

/// Places the panel on the screen with the camera housing (or the main screen, as a pill under the menu bar,
/// when Settings allow it), and grows it out of the housing while `model.isOpen`.
@MainActor
public final class NotchController: NSObject {
    private let panel = NotchPanel.make()
    private let model: StarterModel
    private var geometry: NotchGeometry?
    private var observer: NSObjectProtocol?

    public static let openSize = CGSize(width: 480, height: 128)

    public init<Content: View>(model: StarterModel, @ViewBuilder content: () -> Content) {
        self.model = model
        super.init()
        let host = NotchHostingView(rootView: content())
        host.sizingOptions = [] // the controller sets the frame; the content fills it
        host.hoverChanged = { [weak model] inside in model?.setHovering(inside) }
        panel.contentView = host
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        track()
    }

    /// Picks the screen and shows the panel closed, or hides it when no screen qualifies.
    public func place() {
        let withHousing = NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
        let fallback = UserDefaults.standard.bool(forKey: StarterSettings.showWithoutNotchKey) ? NSScreen.main : nil
        guard let screen = withHousing ?? fallback else {
            geometry = nil
            panel.orderOut(nil)
            return
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let geometry = NotchGeometry(screen: screen.frame, topLeftArea: screen.auxiliaryTopLeftArea,
                                     topRightArea: screen.auxiliaryTopRightArea,
                                     menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness)
        self.geometry = geometry
        model.topInset = geometry.hasNotch ? geometry.closed.height : 0
        resize(animated: false)
        panel.orderFrontRegardless()
    }

    /// Resizes whenever `model.isOpen` changes.
    private func track() {
        withObservationTracking {
            _ = model.isOpen
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resize(animated: true)
                self?.track()
            }
        }
    }

    private func resize(animated: Bool) {
        guard let geometry else { return }
        let target = model.isOpen ? geometry.open(NotchController.openSize) : geometry.closed
        guard target != panel.frame else { return }
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = model.isOpen ? 0.32 : 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.4, 1) // a slight overshoot
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }
}
