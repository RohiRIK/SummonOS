import AppKit
import SwiftUI

/// The menu bar panel, laid out like a system menu: the app's job on top (one control per row), then the footer
/// with only `Settings…` and `Quit`. App preferences never go here; they live in SettingsView.
/// Keys: Return adds one, ⌘, Settings, ⌘Q quit, Esc closes.
public struct PanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @FocusState private var focused: Bool
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleTile(symbol: "plus.circle", title: "Starter", value: model.counter.label)
            MenuDivider()
            CommandRow(title: "Add One", key: "↩", action: model.increment)
            CommandRow(title: "Reset", action: model.reset)
                .disabled(model.counter.value == 0)
            PanelFooter(openSettings: { showSettings() })
        }
        .padding(6)
        .frame(width: 300)
        // Report the full height as the ideal size, so the MenuBarExtra window grows with its content.
        .fixedSize(horizontal: false, vertical: true)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.return) {
            model.increment()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(keys: ["q", ","]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.key == "q" { NSApp.terminate(nil) } else { showSettings() }
            return .handled
        }
    }

    /// A menu bar app is never active: close the panel and activate first, or Settings opens behind other windows.
    private func showSettings() {
        dismiss()
        NSApp.activate()
        openSettings()
    }
}

/// App commands only, as menu rows on the control layer.
struct PanelFooter: View {
    let openSettings: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuDivider()
            VStack(spacing: 0) {
                CommandRow(title: "Settings…", key: "⌘,", action: openSettings)
                CommandRow(title: "Quit Starter", key: "⌘Q") { NSApp.terminate(nil) }
            }
            .glassControl()
        }
    }
}

#Preview("Panel") {
    PanelView(model: StarterModel())
}
