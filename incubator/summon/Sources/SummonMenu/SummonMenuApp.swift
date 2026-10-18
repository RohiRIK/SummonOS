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
                .modifier(ActivityOpener(activity: delegate.activity))
        }
        .menuBarExtraStyle(.window)

        Window("Summon Activity", id: ActivityOpener.windowID) {
            ActivityView(model: delegate.activity)
        }
        .defaultSize(width: 980, height: 640)

        Settings {
            SettingsView(model: delegate.model)
        }
    }
}
