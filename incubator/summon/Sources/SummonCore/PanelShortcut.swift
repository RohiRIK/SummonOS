import Foundation

/// Represents a configurable shortcut in the Summon panel (e.g. quick-launching default agent in ~/Summon).
public struct PanelShortcut: Codable, Equatable, Sendable {
    public var key: String
    public var displayString: String
    public var isCommand: Bool
    public var isOption: Bool
    public var isControl: Bool
    public var isShift: Bool

    public init(key: String, displayString: String, isCommand: Bool, isOption: Bool, isControl: Bool, isShift: Bool) {
        self.key = key
        self.displayString = displayString
        self.isCommand = isCommand
        self.isOption = isOption
        self.isControl = isControl
        self.isShift = isShift
    }

    /// Default shortcut: Option-Return (⌥↵)
    public static let defaultShortcut = PanelShortcut(
        key: "return",
        displayString: "⌥↵",
        isCommand: false,
        isOption: true,
        isControl: false,
        isShift: false
    )

    public static func format(key: String, isCommand: Bool, isOption: Bool, isControl: Bool, isShift: Bool) -> String {
        var str = ""
        if isControl { str += "⌃" }
        if isOption { str += "⌥" }
        if isShift { str += "⇧" }
        if isCommand { str += "⌘" }
        switch key.lowercased() {
        case "return", "\r", "\n":
            str += "↵"
        case "space", " ":
            str += "␣"
        case "tab", "\t":
            str += "⇥"
        default:
            str += key.uppercased()
        }
        return str
    }
}
