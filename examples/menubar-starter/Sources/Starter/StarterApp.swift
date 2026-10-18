import StarterUI
import SwiftUI

@main
struct StarterApp: App {
    @State private var model = StarterModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
