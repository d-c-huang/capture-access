import Carbon

/// A registered system shortcut works while another app is active, without
/// reading arbitrary keyboard events or requiring Accessibility permission.
@MainActor
final class GlobalCaptureShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private static let signature: OSType = 0x43415054 // CAPT
    private static var nextID: UInt32 = 1
    private let identifier: UInt32
    private var registeredShortcut: CaptureShortcut?

    init() {
        identifier = Self.nextID
        Self.nextID &+= 1
    }

    func register(action: @escaping @MainActor () -> Void) -> Bool {
        register(.specialDefault, action: action)
    }

    func register(_ shortcut: CaptureShortcut, action: @escaping @MainActor () -> Void) -> Bool {
        guard shortcut.isValid else { return false }
        if hotKey != nil, registeredShortcut == shortcut {
            self.action = action
            return true
        }
        if handler == nil, !installHandler() { return false }
        var newHotKey: EventHotKeyRef?
        let keyID = EventHotKeyID(signature: Self.signature, id: identifier)
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, keyID,
                                        GetApplicationEventTarget(), 0, &newHotKey)
        guard result == noErr, let newHotKey else {
            if hotKey == nil, let handler {
                RemoveEventHandler(handler)
                self.handler = nil
            }
            return false
        }
        // A conflicting change leaves the previous key active. Only release it
        // after the replacement has registered successfully.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = newHotKey
        registeredShortcut = shortcut
        self.action = action
        return true
    }

    private func installHandler() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let shortcut = Unmanaged<GlobalCaptureShortcut>.fromOpaque(context).takeUnretainedValue()
            guard status == noErr, identifier.signature == 0x43415054, identifier.id == shortcut.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor [weak shortcut] in shortcut?.action?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        return installed == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        action = nil
        registeredShortcut = nil
    }
}
