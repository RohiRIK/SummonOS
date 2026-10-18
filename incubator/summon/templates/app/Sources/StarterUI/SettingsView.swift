import SwiftUI

/// The Settings window (⌘,): every app preference lives here.
public struct SettingsView: View {
    @AppStorage(StarterSettings.showCountKey) private var showCount = true

    public init() {}

    public var body: some View {
        Form {
            Section("Sidebar") {
                Toggle("Show item count", isOn: $showCount)
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
