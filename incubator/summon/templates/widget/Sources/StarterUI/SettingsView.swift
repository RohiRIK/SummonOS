import StarterCore
import SwiftUI

/// The Settings window (⌘,): every app preference lives here; the widget's own options (its title and date) are
/// edited on the widget (right-click › Edit Widget). Changes apply at once. Close only (HIG Settings).
public struct SettingsView: View {
    @AppStorage(StarterSettings.reloadOnLaunchKey) private var reloadOnLaunch = true

    public init() {}

    public var body: some View {
        Form {
            Section("Widgets") {
                Toggle("Reload widgets when Starter opens", isOn: $reloadOnLaunch)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .closeOnlyWindow()
    }
}

#Preview("Settings") {
    SettingsView()
}
