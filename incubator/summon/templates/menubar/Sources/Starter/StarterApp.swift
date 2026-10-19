import StarterUI
import SwiftUI

@main
struct StarterApp: App {
    @State private var model = StarterModel()

    init() {
        // `--screenshot <folder>` draws the panel to PNGs and exits (summon project shots uses it).
        Screenshots.runIfAsked()
    }

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
