import StarterUI
import SwiftUI

@main
struct StarterApp: App {
    @State private var model = StarterModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .commands {
            StarterCommands(model: model)
        }

        Settings {
            SettingsView()
        }
    }
}
