import AppKit
import SwiftUI

/// Keeps a MenuBarExtra window pinned to the menu bar when its dynamic content resizes.
///
/// In AppKit, NSWindow origin is at the bottom-left. When dynamic content (such as alerts or banners)
/// shrinks or expands, AppKit resizes the window around origin.y, which causes the top edge of the window
/// to drop down (floating/detached) or expand upwards over the menu bar. This modifier observes resize events
/// and adjusts origin.y to keep the top edge anchored under the menu bar.
public struct WindowTopPinner: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> TopPinnerView {
        TopPinnerView()
    }

    public func updateNSView(_ nsView: TopPinnerView, context: Context) {}
}

@MainActor
public final class TopPinnerView: NSView {
    private var anchoredTop: CGFloat?
    private var isAdjusting = false
    private var observers: [NSObjectProtocol] = []

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cleanObservers()
        guard let window = self.window else {
            anchoredTop = nil
            return
        }

        if window.isVisible && window.frame.height > 0 {
            anchoredTop = window.frame.maxY
        }

        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, !self.isAdjusting else { return }
                self.anchoredTop = window.frame.maxY
            }
        })

        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, !self.isAdjusting else { return }
                self.anchoredTop = window.frame.maxY
            }
        })

        observers.append(center.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window, !self.isAdjusting else { return }
                let top = self.anchoredTop ?? (window.screen?.visibleFrame.maxY ?? window.frame.maxY)
                let current = window.frame
                if abs(current.maxY - top) > 0.5 {
                    self.isAdjusting = true
                    let newOriginY = top - current.height
                    window.setFrameOrigin(NSPoint(x: current.origin.x, y: newOriginY))
                    self.isAdjusting = false
                }
            }
        })
    }

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            cleanObservers()
        }
    }

    private func cleanObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
}

public extension View {
    /// Keeps the top edge of the enclosing MenuBarExtra window anchored to the menu bar on dynamic resize.
    func pinWindowTopToMenuBar() -> some View {
        background(WindowTopPinner())
    }
}
