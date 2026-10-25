import AppKit
import SwiftUI

/// Turns the model's Settings request into SwiftUI's openSettings(), which needs a scene. Lives in an
/// invisible, always-open window (see `StarterApp`).
public struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(InvisibleWindow())
            .onChange(of: model.settingsRequest) {
                // An LSUIElement app is never active: activate first, or Settings opens behind other windows.
                NSApp.activate()
                openSettings()
            }
    }
}

/// Makes its window invisible, click-through, and out of ⌘` and the Window menu.
struct InvisibleWindow: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.styleMask = [.borderless]
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isExcludedFromWindowsMenu = true
            window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
            window.setFrame(NSRect(x: 0, y: 0, width: 1, height: 1), display: false)
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
