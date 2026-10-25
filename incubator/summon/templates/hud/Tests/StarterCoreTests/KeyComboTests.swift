import StarterCore
import Testing

@Suite struct KeyComboTests {
    @Test func displaysModifiersInMenuOrder() {
        let combo = KeyCombo(keyCode: 40, modifiers: [.command, .shift, .control, .option], key: "K")
        #expect(combo.display == "⌃⌥⇧⌘K")
        #expect(KeyCombo.optionSpace.display == "⌥Space")
    }

    @Test func spotlightAndSystemShortcutsAreRefused() {
        #expect(KeyCombo(keyCode: KeyCombo.spaceKeyCode, modifiers: .command, key: "Space").problem?.contains("Spotlight") == true)
        #expect(KeyCombo(keyCode: 48, modifiers: .command, key: "Tab").problem != nil)
        #expect(KeyCombo(keyCode: 21, modifiers: [.command, .shift], key: "4").problem != nil)
        #expect(KeyCombo.optionSpace.problem == nil)
    }

    @Test func needsARealModifier() {
        #expect(KeyCombo(keyCode: 40, modifiers: [], key: "K").problem != nil)
        #expect(KeyCombo(keyCode: 40, modifiers: .shift, key: "K").problem != nil)
        #expect(KeyCombo(keyCode: 40, modifiers: [.shift, .command], key: "K").problem == nil)
    }

    @Test func roundTripsThroughUserDefaultsText() {
        let combo = KeyCombo(keyCode: 40, modifiers: [.control, .option], key: "K")
        #expect(KeyCombo(encoded: combo.encoded) == combo)
        #expect(KeyCombo(encoded: "") == nil)
        #expect(KeyCombo(encoded: "nonsense") == nil)
    }
}
