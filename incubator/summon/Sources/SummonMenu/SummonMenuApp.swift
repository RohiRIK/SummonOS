import SummonMenuUI
import SwiftUI

@main
struct SummonMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item is an NSStatusItem + nonactivating panel owned by `AppDelegate.panel` (PanelController),
    // not MenuBarExtra: it takes typing without activating Summon and we own dismissal (docs/menubar-panel.md).
    var body: some Scene {
        Window("Summon Activity", id: ActivityOpener.windowID) {
            ActivityView(model: delegate.activity)
        }
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.suppressed)

        // Invisible and always open: it hosts the openers for summon://activity and summon://settings.
        Window("Summon", id: "summon-opener") {
            OpenerHost(activity: delegate.activity)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
