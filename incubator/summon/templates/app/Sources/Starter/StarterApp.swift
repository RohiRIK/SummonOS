import StarterUI
import SwiftUI

@main
struct StarterApp: App {
    @State private var model = StarterModel()

    init() {
        // `--screenshot <folder>` draws the window to PNGs and exits (summon project shots uses it).
        Screenshots.runIfAsked()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model).themed()
        }
        .commands {
            StarterCommands(model: model)
        }

        Settings {
            SettingsView().themed()
        }
    }
}
