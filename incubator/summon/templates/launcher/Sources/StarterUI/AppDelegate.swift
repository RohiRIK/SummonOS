import AppKit
import StarterCore
import SwiftUI

/// Owns what outlives a view: the pre-warmed launcher panel, the global hotkey and the menu bar menu.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let model = StarterModel()
    public private(set) var launcher: LauncherController?
    private var hotKey: HotKey?
    private var registeredCombo: KeyCombo?
    private var statusMenu: StatusMenu?
    private var defaultsObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            StarterSettings.hotKeyKey: KeyCombo.optionSpace.encoded,
            StarterSettings.showInMenuBarKey: true,
        ])
        let model = self.model
        launcher = LauncherController(model: model) {
            LauncherView(model: model).themed()
        }
        statusMenu = StatusMenu(symbol: "magnifyingglass", accessibilityLabel: "Starter") { [weak self] in
            let shortcut = self?.registeredCombo.map { "  \($0.display)" } ?? ""
            return [
                ActionMenu.Item("Open Starter\(shortcut)") { self?.launcher?.open() },
                nil,
                ActionMenu.Item("Settings…", key: ",") { model.requestSettings() },
                ActionMenu.Item("Quit Starter", key: "q") { NSApp.terminate(nil) },
            ]
        }
        applySettings()
        // The Settings window writes the shortcut and the menu bar toggle through @AppStorage.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    /// Opening the app again from the Finder or Spotlight shows Settings: the way back when the menu bar item
    /// is hidden and the shortcut forgotten.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.requestSettings()
        return false
    }

    private func applySettings() {
        let defaults = UserDefaults.standard
        statusMenu?.isVisible = defaults.bool(forKey: StarterSettings.showInMenuBarKey)
        let combo = KeyCombo(encoded: defaults.string(forKey: StarterSettings.hotKeyKey) ?? "")
        guard combo != registeredCombo else { return }
        hotKey?.unregister()
        hotKey = nil
        registeredCombo = nil
        guard let combo, combo.problem == nil else { return }
        hotKey = HotKey(combo) { [weak self] in self?.launcher?.toggle() }
        registeredCombo = hotKey == nil ? nil : combo
    }
}
