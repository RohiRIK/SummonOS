import SummonMenuUI
import SwiftUI

@main
struct SummonMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Summon", systemImage: "sparkles") {
            PanelView(model: delegate.model, openLauncher: { delegate.launcher.show(startAt: nil) })
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
