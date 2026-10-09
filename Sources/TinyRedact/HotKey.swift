import Carbon.HIToolbox

/// Carbon callback: a plain C function, so it lives outside any actor.
private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let id = hotKeyID.id
    Task { @MainActor in HotKey.fire(id) }
    return noErr
}

/// Global hotkey via Carbon — works without Accessibility permission.
@MainActor
final class HotKey {
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let action: () -> Void
    /// Another app had already registered this shortcut. Both apps may get the key press, or, if the other
    /// app holds it exclusively, ours may never fire.
    private(set) var shared = false

    /// Fails if the shortcut can't be registered at all.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5452_4458), id: id) // 'TRDX'
        // Ordinary registrations never conflict, so probe with an exclusive one: that's the only way to find
        // out another app already has the shortcut. Then register normally either way, so TinyRedact never
        // silently takes the shortcut away from an app that registers it later.
        var status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &ref)
        if status == noErr, let probe = ref {
            UnregisterEventHotKey(probe)
            ref = nil
        } else if status == OSStatus(eventHotKeyExistsErr) {
            shared = true
        }
        if status == noErr || shared {
            status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        }
        guard status == noErr else {
            NSLog("TinyRedact: couldn't register the global shortcut (OSStatus %d)", status)
            return nil
        }
        HotKey.registry[id] = self
    }

    static func fire(_ id: UInt32) { registry[id]?.action() }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
    }
}
