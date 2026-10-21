import Carbon.HIToolbox
import Foundation

/// Global hotkeys through Carbon's `RegisterEventHotKey`, which needs no Accessibility permission.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var releaseHandlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    /// 'SMNN'
    private static let signature: OSType = 0x534D_4E4E

    private init() {}

    /// Registers (or replaces) hotkey `id`. Returns false when another app already owns the combination.
    @discardableResult
    public func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, onRelease: (() -> Void)? = nil,
                         handler: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        refs[id] = ref
        handlers[id] = handler
        releaseHandlers[id] = onRelease
        return true
    }

    public func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        handlers[id] = nil
        releaseHandlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32, released: Bool) {
        if released {
            releaseHandlers[id]?()
        } else {
            handlers[id]?()
        }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        // Releases too, so a held key can be told apart from a second press (panel spec C3).
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
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
                let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                MainActor.assumeIsolated {
                    HotKeyCenter.shared.fire(id, released: released)
                }
            }
            return OSStatus(noErr)
        }, specs.count, &specs, nil, nil)
    }
}

/// The two Summon hotkeys. Fixed for now; Settings shows them and whether they registered.
public enum SummonHotKey {
    public static let menuID: UInt32 = 1
    public static let agentID: UInt32 = 2

    /// ⌃⌥Space toggles the menu bar panel, which holds the Summon Menu (Omarchy's Super+Space; panel spec v1.5 C1). Option alone is not allowed:
    /// macOS 15 rejects hot keys whose only modifiers are Option or Option+Shift.
    public static let menuKey = UInt32(kVK_Space)
    public static let menuModifiers = UInt32(controlKey | optionKey)

    /// ⌃⌥⌘A starts the default agent (Omarchy's Super+Shift+Ctrl+A).
    public static let agentKey = UInt32(kVK_ANSI_A)
    public static let agentModifiers = UInt32(controlKey | optionKey | cmdKey)
}
