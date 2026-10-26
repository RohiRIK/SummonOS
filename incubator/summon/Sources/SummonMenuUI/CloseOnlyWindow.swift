import AppKit
import SwiftUI

extension View {
    /// Close only: minimize and zoom dimmed, no full screen. HIG Settings: "Dim a settings window's minimize and
    /// maximize buttons"; the setup window is the same kind of one-task window (docs/ux-surfaces/03, 06).
    func closeOnlyWindow() -> some View {
        background(CloseOnlyWindowChrome())
    }
}

private struct CloseOnlyWindowChrome: NSViewRepresentable {
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
