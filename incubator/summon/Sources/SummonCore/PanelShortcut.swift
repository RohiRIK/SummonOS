import Foundation

/// Represents a configurable shortcut in Summon (global hotkeys or panel shortcuts).
public struct PanelShortcut: Codable, Equatable, Sendable {
    public var key: String
    public var keyCode: UInt32
    public var displayString: String
    public var isCommand: Bool
    public var isOption: Bool
    public var isControl: Bool
    public var isShift: Bool

    public init(
        key: String,
        keyCode: UInt32 = 0,
        displayString: String,
        isCommand: Bool,
        isOption: Bool,
        isControl: Bool,
        isShift: Bool
    ) {
        self.key = key
        self.keyCode = keyCode
        self.displayString = displayString
        self.isCommand = isCommand
        self.isOption = isOption
        self.isControl = isControl
        self.isShift = isShift
    }

    enum CodingKeys: String, CodingKey {
        case key, keyCode, displayString, isCommand, isOption, isControl, isShift
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try container.decode(String.self, forKey: .key)
        self.keyCode = (try? container.decodeIfPresent(UInt32.self, forKey: .keyCode)) ?? 0
        self.displayString = try container.decode(String.self, forKey: .displayString)
        self.isCommand = try container.decode(Bool.self, forKey: .isCommand)
        self.isOption = try container.decode(Bool.self, forKey: .isOption)
        self.isControl = try container.decode(Bool.self, forKey: .isControl)
        self.isShift = try container.decode(Bool.self, forKey: .isShift)
    }

    /// Carbon modifier flags for RegisterEventHotKey
    public var carbonModifiers: UInt32 {
        var mods: UInt32 = 0
        if isCommand { mods |= 256 }  // cmdKey
        if isShift   { mods |= 512 }  // shiftKey
        if isOption  { mods |= 2048 } // optionKey
        if isControl { mods |= 4096 } // controlKey
        return mods
    }

    /// Default panel quick-launch agent shortcut: ⌥↵ (kVK_Return = 36)
    public static let defaultPanelAgent = PanelShortcut(
        key: "return",
        keyCode: 36,
        displayString: "⌥↵",
        isCommand: false,
        isOption: true,
        isControl: false,
        isShift: false
    )

    /// Default global open panel shortcut: ⌃⌥Space (kVK_Space = 49)
    public static let defaultGlobalMenu = PanelShortcut(
        key: "space",
        keyCode: 49,
        displayString: "⌃⌥Space",
        isCommand: false,
        isOption: true,
        isControl: true,
        isShift: false
    )

    /// Default global ask agent shortcut: ⌃⌥⌘A (kVK_ANSI_A = 0)
    public static let defaultGlobalAgent = PanelShortcut(
        key: "a",
        keyCode: 0,
        displayString: "⌃⌥⌘A",
        isCommand: true,
        isOption: true,
        isControl: true,
        isShift: false
    )

    /// Legacy alias
    public static let defaultShortcut = defaultPanelAgent

    public static func format(
        key: String,
        keyCode: UInt32 = 0,
        isCommand: Bool,
        isOption: Bool,
        isControl: Bool,
        isShift: Bool
    ) -> String {
        var str = ""
        if isControl { str += "⌃" }
        if isOption { str += "⌥" }
        if isShift { str += "⇧" }
        if isCommand { str += "⌘" }

        let lower = key.lowercased()
        if keyCode == 36 || keyCode == 76 || lower == "return" || key == "\r" || key == "\n" {
            str += "↵"
        } else if keyCode == 49 || lower == "space" || key == " " {
            str += "Space"
        } else if keyCode == 48 || lower == "tab" || key == "\t" {
            str += "Tab"
        } else {
            str += key.uppercased()
        }
        return str
    }
}
