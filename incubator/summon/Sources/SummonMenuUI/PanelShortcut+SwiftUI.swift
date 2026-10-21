import SummonCore
import SwiftUI

extension PanelShortcut {
    public var keyEquivalent: KeyEquivalent {
        switch key.lowercased() {
        case "return", "\r", "\n":
            return .return
        case "space", " ":
            return .space
        case "tab", "\t":
            return .tab
        case "escape":
            return .escape
        default:
            if let first = key.first {
                return KeyEquivalent(first)
            }
            return .return
        }
    }

    public var eventModifiers: EventModifiers {
        var mods: EventModifiers = []
        if isCommand { mods.insert(.command) }
        if isOption { mods.insert(.option) }
        if isControl { mods.insert(.control) }
        if isShift { mods.insert(.shift) }
        return mods
    }

    public func matches(_ press: KeyPress) -> Bool {
        if press.modifiers.contains(.command) != isCommand { return false }
        if press.modifiers.contains(.option) != isOption { return false }
        if press.modifiers.contains(.control) != isControl { return false }
        if press.modifiers.contains(.shift) != isShift { return false }

        switch key.lowercased() {
        case "return", "\r", "\n":
            return press.key == .return
        case "space", " ":
            return press.key == .space
        case "tab", "\t":
            return press.key == .tab
        case "escape":
            return press.key == .escape
        default:
            if let char = key.lowercased().first {
                return press.key == KeyEquivalent(char) || press.characters.lowercased() == String(char)
            }
            return false
        }
    }
}
