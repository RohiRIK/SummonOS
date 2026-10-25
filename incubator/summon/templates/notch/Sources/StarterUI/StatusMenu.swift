import AppKit

/// A plain `NSMenu` built from closures each time it opens, so titles and checkmarks follow the app's state.
/// Used for the menu bar item and for right-click menus.
@MainActor
public final class ActionMenu: NSObject, NSMenuDelegate {
    public struct Item {
        public var title: String
        public var key: String
        public var isChecked: Bool
        public var children: [Item?]
        public var action: @MainActor () -> Void

        public init(_ title: String, key: String = "", checked: Bool = false, action: @escaping @MainActor () -> Void) {
            self.title = title
            self.key = key
            self.isChecked = checked
            self.children = []
            self.action = action
        }

        /// A submenu.
        public init(_ title: String, children: [Item?]) {
            self.title = title
            self.key = ""
            self.isChecked = false
            self.children = children
            self.action = {}
        }
    }

    public let menu = NSMenu()
    private let items: () -> [Item?]

    /// `items` is read each time the menu opens; nil is a separator.
    public init(items: @escaping () -> [Item?]) {
        self.items = items
        super.init()
        menu.delegate = self
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(items(), to: menu)
    }

    private func add(_ items: [Item?], to menu: NSMenu) {
        for item in items {
            guard let item else {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: item.key)
            if item.children.isEmpty {
                menuItem.action = #selector(run(_:))
                menuItem.target = self
                menuItem.representedObject = ActionBox(item.action)
                menuItem.state = item.isChecked ? .on : .off
            } else {
                let submenu = NSMenu(title: item.title)
                add(item.children, to: submenu)
                menuItem.submenu = submenu
            }
            menu.addItem(menuItem)
        }
    }

    @objc private func run(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    private final class ActionBox {
        let action: @MainActor () -> Void
        init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    }
}

/// The menu bar item of an app whose main surface is not a menu bar panel: a template SF Symbol that opens a plain
/// menu (HIG: prefer a menu). People can hide it in Settings ("Show in menu bar"); the app then stays reachable
/// from its shortcut and from opening it again in the Finder, which shows Settings.
@MainActor
public final class StatusMenu {
    private var statusItem: NSStatusItem?
    private let symbol: String
    private let accessibilityLabel: String
    private let actions: ActionMenu

    public init(symbol: String, accessibilityLabel: String, items: @escaping () -> [ActionMenu.Item?]) {
        self.symbol = symbol
        self.accessibilityLabel = accessibilityLabel
        actions = ActionMenu(items: items)
    }

    public var isVisible: Bool {
        get { statusItem != nil }
        set {
            if newValue, statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)
                image?.isTemplate = true
                item.button?.image = image
                item.menu = actions.menu
                statusItem = item
            } else if !newValue, let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }
}
