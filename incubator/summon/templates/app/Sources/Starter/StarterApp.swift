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

        // First-run setup: opened once by `showsOnboardingOnFirstLaunch()`, again from Settings.
        Window("Welcome to Starter", id: OnboardingView.windowID) {
            OnboardingView(readyTitle: "You're Set", readyText: "Press ⌘N for your first item.",
                           readySymbol: "checkmark.circle").themed()
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
