import SummonMenuUI
import SwiftUI

@main
struct SummonMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item is an NSStatusItem + nonactivating panel owned by `AppDelegate.panel` (PanelController),
    // not MenuBarExtra: it takes typing without activating Summon and we own dismissal (docs/menubar-panel.md).
    var body: some Scene {
        Window("Activity", id: ActivityOpener.windowID) {
            ActivityView(model: delegate.activity)
        }
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.suppressed)
        // AppDelegate handles every summon:// URL. Without this, SwiftUI also routes the URL's open event to the
        // first scene and shows this window (`summon panel`, `summon menu summon`).
        .handlesExternalEvents(matching: [])

        // Invisible and always open: it hosts the openers for summon://activity and summon://settings.
        Window("Summon", id: "summon-opener") {
            OpenerHost(activity: delegate.activity)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        // The invisible, always-open opener claims summon:// so SwiftUI reuses it instead of opening a window.
        .handlesExternalEvents(matching: ["summon"])

        // First-run setup: opened once at first launch (ActivityOpener), again from Settings or summon://welcome.
        Window(OnboardingView.title, id: OnboardingView.windowID) {
            OnboardingView(model: delegate.model) { delegate.panel?.open() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultWindowPlacement { _, _ in WindowPlacement(.center) }
        .handlesExternalEvents(matching: [])

        // The one Settings window (⌘, from the app menu, Settings… in the panel, summon://settings).
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
