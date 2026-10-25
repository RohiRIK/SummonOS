import StarterUI
import SwiftUI

@main
struct StarterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // `--screenshot <folder>` draws the panel to PNGs and exits (summon project shots uses it).
        Screenshots.runIfAsked()
    }

    // The menu bar item is an NSStatusItem + nonactivating NSPanel owned by `AppDelegate`, not MenuBarExtra:
    // it opens from code, takes typing without activating the app, and keeps a live label.
    var body: some Scene {
        // Invisible and always open: SwiftUI's openSettings only works from inside a scene, so this window
        // turns the panel's Settings… request into an openSettings() call.
        Window("Starter", id: "settings-opener") {
            SettingsOpener(model: delegate.model)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)

        // First-run setup: opened once by `showsOnboardingOnFirstLaunch()`, again from Settings.
        Window("Welcome to Starter", id: OnboardingView.windowID) {
            OnboardingView(readyTitle: "Starter Lives in the Menu Bar",
                           readyText: "Click its icon at the top of the screen, or right-click it for Settings.",
                           readySymbol: "arrow.up").themed()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { _, _ in WindowPlacement(.center) }

        Settings {
            SettingsView().themed()
        }
    }
}
