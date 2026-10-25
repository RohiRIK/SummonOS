import AppKit
import StarterCore
import SwiftUI

/// A Settings row that records a global shortcut (macOS has no system recorder control). Click, press the keys;
/// Esc cancels, Delete clears. Reserved combos (⌘Space is Spotlight's) are refused with the reason.
/// Stores `KeyCombo.encoded` under `key`; an empty string means no shortcut.
struct ShortcutRecorder: View {
    let title: String
    @AppStorage private var stored: String
    @State private var recording = false
    @State private var problem: String?
    @State private var monitor: Any?

    init(_ title: String, key: String, default combo: KeyCombo?) {
        self.title = title
        _stored = AppStorage(wrappedValue: combo?.encoded ?? "", key)
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Button(recording ? "Type Shortcut…" : (KeyCombo(encoded: stored)?.display ?? "Record Shortcut")) {
                    recording ? stop() : start()
                }
                .monospaced(!recording && KeyCombo(encoded: stored) != nil)
                if !stored.isEmpty && !recording {
                    Button("Clear", systemImage: "xmark.circle.fill") { stored = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let problem {
            Text(problem).font(.subheadline).foregroundStyle(.red)
        }
    }

    private func start() {
        problem = nil
        recording = true
        // A local monitor sees keys only while this window is key, so it needs no permission.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private func handle(_ event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // Esc
            stop()
            return
        case 51, 117: // Delete, Forward Delete
            stored = ""
            stop()
            return
        default:
            break
        }
        let combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers(event.modifierFlags), key: name(of: event))
        if let reason = combo.problem {
            problem = reason
            return
        }
        problem = nil
        stored = combo.encoded
        stop()
    }

    private func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }

    private func name(of event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}
