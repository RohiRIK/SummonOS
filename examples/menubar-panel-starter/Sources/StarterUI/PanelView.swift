import SwiftUI

/// The menu bar panel: the app's job on top, Settings… and Quit in the footer.
/// App preferences never go here; they live in SettingsView.
public struct PanelView: View {
    private let model: StarterModel
    private let actions: PanelActions

    public init(model: StarterModel, actions: PanelActions) {
        self.model = model
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Starter")
                .font(.headline)
            Text(model.counter.label)
                .font(.title2.monospacedDigit())
            HStack {
                Button("Add One") { model.increment() }
                    .keyboardShortcut(.defaultAction)
                Button("Reset") { model.reset() }
                    .disabled(model.counter.value == 0)
            }
            Divider()
            HStack {
                Button("Settings…") { actions.openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { actions.quit() }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 260)
    }
}

#Preview("Panel") {
    PanelView(model: StarterModel(), actions: .preview)
}
