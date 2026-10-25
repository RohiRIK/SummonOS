import SwiftUI

/// The menu bar panel, laid out like a system menu: the app's job on top (one control per row), then the footer
/// with only `Settings…` and `Quit`. App preferences never go here; they live in SettingsView.
/// Keys: Return adds one, ⌘, Settings, ⌘Q quit, Esc closes (StatusPanel).
public struct PanelView: View {
    @FocusState private var focused: Bool
    private let model: StarterModel
    private let actions: PanelActions

    public init(model: StarterModel, actions: PanelActions) {
        self.model = model
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModuleTile(symbol: "plus.circle", title: "Starter", value: model.counter.label)
            MenuDivider()
            CommandRow(title: "Add One", key: "↩", action: model.increment)
            CommandRow(title: "Reset", action: model.reset)
                .disabled(model.counter.value == 0)
            PanelFooter(actions: actions)
        }
        .padding(6)
        .frame(width: 300)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.return) {
            model.increment()
            return .handled
        }
        .onKeyPress(keys: ["q", ","]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.key == "q" { actions.quit() } else { actions.openSettings() }
            return .handled
        }
    }
}

/// App commands only, as menu rows on the control layer. Settings… closes the panel first (PanelController).
struct PanelFooter: View {
    let actions: PanelActions

    var body: some View {
        VStack(spacing: 0) {
            MenuDivider()
            VStack(spacing: 0) {
                CommandRow(title: "Settings…", key: "⌘,", action: actions.openSettings)
                CommandRow(title: "Quit Starter", key: "⌘Q", action: actions.quit)
            }
            .glassControl()
        }
    }
}

#Preview("Panel") {
    PanelView(model: StarterModel(), actions: .preview)
}
