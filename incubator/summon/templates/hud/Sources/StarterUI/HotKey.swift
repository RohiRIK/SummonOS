import Carbon.HIToolbox
import StarterCore

/// A global shortcut through Carbon's `RegisterEventHotKey`: it fires while any app is frontmost, even a full-screen
/// one, and needs no Accessibility or Input Monitoring permission (a global `NSEvent` monitor needs both).
/// Call `unregister()` before dropping it.
@MainActor
public final class HotKey {
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// Nil when macOS refuses the combo, usually because another app already registered it.
    public init?(_ combo: KeyCombo, action: @escaping @MainActor () -> Void) {
        HotKey.installHandler()
        id = HotKey.nextID
        HotKey.nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x534D_4E48), id: id) // "SMNH"
        let status = RegisterEventHotKey(combo.keyCode, HotKey.carbonModifiers(combo.modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        self.ref = ref
        HotKey.actions[id] = action
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        HotKey.actions[id] = nil
    }

    static func fire(_ id: UInt32) {
        actions[id]?()
    }

    private static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, nil, nil)
    }
}

/// Carbon calls this on the main thread for every registered hotkey press.
private func hotKeyPressed(_ call: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated { HotKey.fire(id) }
    return noErr
}
