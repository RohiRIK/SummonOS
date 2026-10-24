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

#Preview("Settings") {
    SettingsView()
}
