import SwiftUI

/// The Settings window (⌘,): every app preference lives here, never in the panel.
public struct SettingsView: View {
    @AppStorage(StarterSettings.showCountKey) private var showCount = false

    public init() {}

    public var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show count in the menu bar", isOn: $showCount)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The menu bar item: an icon, or the count when the setting is on.
public struct MenuBarLabel: View {
    @AppStorage(StarterSettings.showCountKey) private var showCount = false
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        if showCount {
            Text("\(model.counter.value)")
        } else {
            Image(systemName: "plus.circle")
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
