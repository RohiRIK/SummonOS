import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon's `RegisterEventHotKey`, which needs no Accessibility permission.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    /// 'SMNN'
    private static let signature: OSType = 0x534D_4E4E

    private init() {}

    /// Registers (or replaces) hotkey `id`. Returns false when another app already owns the combination.
    @discardableResult
    public func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = handler
        return true
    }

    public func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // A C callback cannot capture context; it reaches the shared center, on the main thread where Carbon calls it.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                let id = hotKeyID.id
                MainActor.assumeIsolated {
                    HotKeyCenter.shared.fire(id)
                }
            }
            return OSStatus(noErr)
        }, 1, &spec, nil, nil)
    }
}

/// The two Summon hotkeys. Fixed for now; Settings shows them.
public enum SummonHotKey {
    public static let menuID: UInt32 = 1
    public static let agentID: UInt32 = 2

    /// ⌥Space opens the Summon Menu (Omarchy's Super+Space).
    public static let menuKey = UInt32(kVK_Space)
    public static let menuModifiers = UInt32(optionKey)

    /// ⌃⌥⌘A starts the default agent (Omarchy's Super+Shift+Ctrl+A).
    public static let agentKey = UInt32(kVK_ANSI_A)
    public static let agentModifiers = UInt32(controlKey | optionKey | cmdKey)
}
