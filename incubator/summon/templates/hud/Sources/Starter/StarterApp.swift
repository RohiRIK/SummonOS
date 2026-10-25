import StarterUI
import SwiftUI

@main
struct StarterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // `--screenshot <folder>` draws the HUD to PNGs and exits (summon project shots uses it).
        Screenshots.runIfAsked()
    }

    // The HUD is a floating nonactivating NSPanel owned by `AppDelegate`: always on top, never key.
    var body: some Scene {
        // Invisible and always open: SwiftUI's openSettings only works from inside a scene, so this window
        // turns a Settings… request into an openSettings() call.
        Window("Starter", id: "settings-opener") {
            SettingsOpener(model: delegate.model)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)

        Settings {
            SettingsView().themed()
        }
    }
}
