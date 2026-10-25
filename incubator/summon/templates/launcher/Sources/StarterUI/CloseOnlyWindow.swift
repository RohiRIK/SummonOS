import AppKit
import SwiftUI

extension View {
    /// For the root of a Settings or setup window: close only. Minimize and zoom are dimmed and full screen is off
    /// (HIG Settings: ⌘, reopens it in a moment, so it never needs the Dock).
    public func closeOnlyWindow() -> some View {
        background(CloseOnlyWindowChrome())
    }
}

struct CloseOnlyWindowChrome: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            if window.styleMask.contains(.miniaturizable) { window.styleMask.remove(.miniaturizable) }
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    // SwiftUI can restore the buttons when it updates the window, so apply again on every update.
    func updateNSView(_ nsView: Probe, context: Context) { nsView.apply() }
}
