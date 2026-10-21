import Foundation
import Testing
@testable import SummonCore

@Suite("Panel Shortcuts")
struct PanelShortcutTests {
    @Test func defaultShortcutIsOptionReturn() {
        let def = PanelShortcut.defaultShortcut
        #expect(def.key == "return")
        #expect(def.displayString == "⌥↵")
        #expect(def.isOption == true)
        #expect(def.isCommand == false)
        #expect(def.isControl == false)
        #expect(def.isShift == false)
    }

    @Test func formatKeyCombinations() {
        #expect(PanelShortcut.format(key: "return", isCommand: false, isOption: true, isControl: false, isShift: false) == "⌥↵")
        #expect(PanelShortcut.format(key: "return", isCommand: true, isOption: false, isControl: false, isShift: false) == "⌘↵")
        #expect(PanelShortcut.format(key: "space", isCommand: true, isOption: true, isControl: false, isShift: false) == "⌥⌘␣")
        #expect(PanelShortcut.format(key: "k", isCommand: true, isOption: false, isControl: true, isShift: false) == "⌃⌘K")
        #expect(PanelShortcut.format(key: "tab", isCommand: false, isOption: false, isControl: true, isShift: true) == "⌃⇧⇥")
    }

    @Test func roundTripsJSON() throws {
        let custom = PanelShortcut(key: "j", displayString: "⌃⌥J", isCommand: false, isOption: true, isControl: true, isShift: false)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(PanelShortcut.self, from: data)
        #expect(decoded == custom)
        #expect(decoded.displayString == "⌃⌥J")
    }
}
