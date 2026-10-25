import Foundation

/// A global keyboard shortcut: a virtual key code plus modifiers, as Carbon's `RegisterEventHotKey` takes it.
/// Stored in UserDefaults as JSON (`encoded` / `init(encoded:)`), recorded by the user in Settings.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// In the order macOS menus show them: ⌃⌥⇧⌘.
        public var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    /// The virtual key code (`kVK_*`, the same as `NSEvent.keyCode`).
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// What the key is called on screen: "Space", "K", "F5".
    public var key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public static let spaceKeyCode: UInt32 = 49

    /// ⌥Space, the launcher default. ⌘Space is Spotlight's and is never a default (HIG Keyboards).
    public static let optionSpace = KeyCombo(keyCode: spaceKeyCode, modifiers: .option, key: "Space")

    /// "⌥Space", "⇧⌘K".
    public var display: String { modifiers.symbols + key }

    /// Why this combo can't be a global shortcut, or nil when it can.
    public var problem: String? {
        if modifiers.isEmpty || modifiers == .shift {
            return "Add ⌘, ⌥ or ⌃: a shortcut without one would take the key from every app."
        }
        if let owner = KeyCombo.reserved[ReservedKey(keyCode: keyCode, modifiers: modifiers)] {
            return "\(display) belongs to \(owner)."
        }
        return nil
    }

    private struct ReservedKey: Hashable {
        let keyCode: UInt32
        let modifiers: Modifiers
    }

    /// System shortcuts from the HIG's standard list that a global hotkey must not take.
    private static let reserved: [ReservedKey: String] = [
        ReservedKey(keyCode: spaceKeyCode, modifiers: .command): "Spotlight",
        ReservedKey(keyCode: spaceKeyCode, modifiers: [.command, .option]): "Spotlight's Finder search",
        ReservedKey(keyCode: spaceKeyCode, modifiers: [.command, .control]): "Emoji & Symbols",
        ReservedKey(keyCode: spaceKeyCode, modifiers: .control): "the input source switcher",
        ReservedKey(keyCode: spaceKeyCode, modifiers: [.control, .option]): "the input source switcher",
        ReservedKey(keyCode: 48, modifiers: .command): "the app switcher", // Tab
        ReservedKey(keyCode: 12, modifiers: .command): "Quit in every app", // Q
        ReservedKey(keyCode: 13, modifiers: .command): "Close in every app", // W
        ReservedKey(keyCode: 4, modifiers: .command): "Hide in every app", // H
        ReservedKey(keyCode: 46, modifiers: .command): "Minimize in every app", // M
        ReservedKey(keyCode: 20, modifiers: [.command, .shift]): "screenshots", // 3
        ReservedKey(keyCode: 21, modifiers: [.command, .shift]): "screenshots", // 4
        ReservedKey(keyCode: 23, modifiers: [.command, .shift]): "screenshots", // 5
        ReservedKey(keyCode: 12, modifiers: [.command, .control]): "Lock Screen", // Q
    ]

    /// JSON for UserDefaults.
    public var encoded: String {
        (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }

    /// Nil for an empty or unreadable value, which means "no shortcut".
    public init?(encoded: String) {
        guard let combo = try? JSONDecoder().decode(KeyCombo.self, from: Data(encoded.utf8)) else { return nil }
        self = combo
    }
}
