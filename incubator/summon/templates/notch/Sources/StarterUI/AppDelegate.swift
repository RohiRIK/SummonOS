import AppKit
import StarterCore
import SwiftUI

/// Owns what outlives a view: the notch panel and the menu bar menu.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let model = StarterModel()
    public private(set) var notch: NotchController?
    private var statusMenu: StatusMenu?
    private var defaultsObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            StarterSettings.showInMenuBarKey: true,
            StarterSettings.showWithoutNotchKey: true,
        ])
        let model = self.model
        let notch = NotchController(model: model) {
            NotchView(model: model).themed()
        }
        self.notch = notch
        statusMenu = StatusMenu(symbol: "tray", accessibilityLabel: "Starter") {
            [
                ActionMenu.Item("Show Shelf") { model.show() },
                ActionMenu.Item("Clear Shelf") { model.clear() },
                nil,
                ActionMenu.Item("Settings…", key: ",") { model.requestSettings() },
                ActionMenu.Item("Quit Starter", key: "q") { NSApp.terminate(nil) },
            ]
        }
        applySettings()
        // The Settings window writes through @AppStorage.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    /// Opening the app again from the Finder shows Settings: the way back when the menu bar item is hidden.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.requestSettings()
        return false
    }

    private var appliedFallback: Bool?

    private func applySettings() {
        let defaults = UserDefaults.standard
        statusMenu?.isVisible = defaults.bool(forKey: StarterSettings.showInMenuBarKey)
        let fallback = defaults.bool(forKey: StarterSettings.showWithoutNotchKey)
        guard fallback != appliedFallback else { return } // the shelf also writes defaults; only re-place on a change
        appliedFallback = fallback
        notch?.place()
    }
}
