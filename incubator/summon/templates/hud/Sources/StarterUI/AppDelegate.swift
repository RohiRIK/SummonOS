import AppKit
import StarterCore
import SwiftUI

/// Owns what outlives a view: the HUD panel, its right-click menu, the menu bar menu and the global shortcut.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let model = StarterModel()
    public private(set) var hud: HUDController?
    private var hotKey: HotKey?
    private var registeredCombo: KeyCombo?
    private var statusMenu: StatusMenu?
    private var contextMenu: ActionMenu?
    private var defaultsObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            StarterSettings.showInMenuBarKey: true,
            StarterSettings.opacityKey: 1.0,
            StarterSettings.sizeKey: HUDSize.medium.rawValue,
        ])
        let model = self.model
        let contextMenu = ActionMenu { [weak self] in self?.hudMenuItems() ?? [] }
        self.contextMenu = contextMenu
        let hud = HUDController(model: model, menu: contextMenu.menu) {
            HUDView(model: model) { [weak self] in self?.hud?.hide() }.themed()
        }
        self.hud = hud
        statusMenu = StatusMenu(symbol: "stopwatch", accessibilityLabel: "Starter") { [weak self] in
            guard let self else { return [] }
            let show: [ActionMenu.Item?] = [
                ActionMenu.Item(model.isHUDVisible ? "Hide Stopwatch" : "Show Stopwatch") { self.hud?.toggle() },
            ]
            return show + self.timerItems() + [nil] + self.appItems()
        }
        applySettings()
        hud.show()
        // The Settings window and the right-click menu write through UserDefaults.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
    }

    /// Opening the app again from the Finder brings the HUD back and shows Settings.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        hud?.show()
        model.requestSettings()
        return false
    }

    private func timerItems() -> [ActionMenu.Item?] {
        let shortcut = registeredCombo.map { "  \($0.display)" } ?? ""
        return [
            ActionMenu.Item((model.stopwatch.state == .running ? "Pause" : "Start") + shortcut) { [weak self] in self?.model.toggle() },
            ActionMenu.Item("Reset") { [weak self] in self?.model.reset() },
        ]
    }

    private func appItems() -> [ActionMenu.Item?] {
        [
            ActionMenu.Item("Settings…", key: ",") { [weak self] in self?.model.requestSettings() },
            ActionMenu.Item("Quit Starter", key: "q") { NSApp.terminate(nil) },
        ]
    }

    /// Right-click on the HUD: the timer, then how the HUD looks and where it sits (HIG: short, no shortcuts shown).
    private func hudMenuItems() -> [ActionMenu.Item?] {
        let defaults = UserDefaults.standard
        let opacity = defaults.double(forKey: StarterSettings.opacityKey)
        let size = HUDSize(rawValue: defaults.string(forKey: StarterSettings.sizeKey) ?? "") ?? .medium
        let opacities: [ActionMenu.Item?] = [0.25, 0.5, 0.75, 1].map { value in
            ActionMenu.Item("\(Int(value * 100))%", checked: abs(opacity - value) < 0.01) {
                defaults.set(value, forKey: StarterSettings.opacityKey)
            }
        }
        let sizes: [ActionMenu.Item?] = HUDSize.allCases.map { option in
            ActionMenu.Item(option.title, checked: option == size) { defaults.set(option.rawValue, forKey: StarterSettings.sizeKey) }
        }
        let corners: [ActionMenu.Item?] = Corner.allCases.map { corner in
            ActionMenu.Item(corner.title, checked: corner == model.corner) { [weak self] in self?.hud?.move(to: corner) }
        }
        return timerItems() + [
            nil,
            ActionMenu.Item("Opacity", children: opacities),
            ActionMenu.Item("Size", children: sizes),
            ActionMenu.Item("Move To", children: corners),
            nil,
            ActionMenu.Item("Hide Stopwatch") { [weak self] in self?.hud?.hide() },
        ] + appItems()
    }

    private func applySettings() {
        let defaults = UserDefaults.standard
        statusMenu?.isVisible = defaults.bool(forKey: StarterSettings.showInMenuBarKey)
        hud?.setOpacity(defaults.double(forKey: StarterSettings.opacityKey))
        let combo = KeyCombo(encoded: defaults.string(forKey: StarterSettings.hotKeyKey) ?? "")
        guard combo != registeredCombo else { return }
        hotKey?.unregister()
        hotKey = nil
        registeredCombo = nil
        guard let combo, combo.problem == nil else { return }
        hotKey = HotKey(combo) { [weak self] in self?.model.toggle() }
        registeredCombo = hotKey == nil ? nil : combo
    }
}
