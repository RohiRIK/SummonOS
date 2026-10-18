import SummonMenuUI
import SwiftUI

@main
struct SummonMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: delegate.model, activity: delegate.activity, openLauncher: { delegate.launcher.show(startAt: nil) })
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

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
