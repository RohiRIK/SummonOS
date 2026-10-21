import Foundation
import Testing
@testable import SummonCore

@Suite("Panel Shortcuts")
struct PanelShortcutTests {
    @Test func defaultShortcuts() {
        let panel = PanelShortcut.defaultPanelAgent
        #expect(panel.key == "return")
        #expect(panel.keyCode == 36)
        #expect(panel.displayString == "⌥↵")
        #expect(panel.isOption == true)
        #expect(panel.isCommand == false)

        let menu = PanelShortcut.defaultGlobalMenu
        #expect(menu.key == "space")
        #expect(menu.keyCode == 49)
        #expect(menu.displayString == "⌃⌥Space")
        #expect(menu.isControl == true)
        #expect(menu.isOption == true)
        #expect(menu.carbonModifiers == (4096 | 2048))

        let agent = PanelShortcut.defaultGlobalAgent
        #expect(agent.key == "a")
        #expect(agent.keyCode == 0)
        #expect(agent.displayString == "⌃⌥⌘A")
        #expect(agent.isControl == true)
        #expect(agent.isOption == true)
        #expect(agent.isCommand == true)
        #expect(agent.carbonModifiers == (4096 | 2048 | 256))
    }

    @Test func formatKeyCombinations() {
        #expect(PanelShortcut.format(key: "return", keyCode: 36, isCommand: false, isOption: true, isControl: false, isShift: false) == "⌥↵")
        #expect(PanelShortcut.format(key: "return", keyCode: 36, isCommand: true, isOption: false, isControl: false, isShift: false) == "⌘↵")
        #expect(PanelShortcut.format(key: "space", keyCode: 49, isCommand: false, isOption: true, isControl: true, isShift: false) == "⌃⌥Space")
        #expect(PanelShortcut.format(key: "a", keyCode: 0, isCommand: true, isOption: true, isControl: true, isShift: false) == "⌃⌥⌘A")
        #expect(PanelShortcut.format(key: "tab", keyCode: 48, isCommand: false, isOption: false, isControl: true, isShift: true) == "⌃⇧Tab")
    }

    @Test func roundTripsJSON() throws {
        let custom = PanelShortcut(key: "j", keyCode: 38, displayString: "⌃⌥J", isCommand: false, isOption: true, isControl: true, isShift: false)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(PanelShortcut.self, from: data)
        #expect(decoded == custom)
        #expect(decoded.keyCode == 38)
        #expect(decoded.displayString == "⌃⌥J")
    }
}
