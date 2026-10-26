import StarterCore
import StarterUI
import SwiftUI
import WidgetKit

/// The app that carries the widget extension (`Contents/PlugIns/StarterWidget.appex`). One window, so closing it
/// quits the app; the widget keeps running on its own.
@main
struct StarterApp: App {
    @AppStorage(StarterSettings.reloadOnLaunchKey) private var reloadOnLaunch = true

    init() {
        // `--screenshot <folder>` draws the window to PNGs and exits (summon project shots uses it).
        Screenshots.runIfAsked()
    }

    var body: some Scene {
        Window("Starter", id: "main") {
            ContentView()
                .task {
                    // Picks up a new widget build after an update; WidgetKit budgets reloads, so only here.
                    if reloadOnLaunch { WidgetCenter.shared.reloadTimelines(ofKind: StarterWidgetKind.countdown) }
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
