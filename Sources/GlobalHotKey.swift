import Carbon

protocol HotKeyRegistering: AnyObject {
    var onPress: (() -> Void)? { get set }
    var shortcut: KeyboardShortcut? { get }
    func replace(with shortcut: KeyboardShortcut?) -> OSStatus
}

struct HotKeyPressState {
    private var pressed = false
    mutating func receive(down: Bool) -> Bool {
        if !down { pressed = false; return false }
        guard !pressed else { return false }
        pressed = true
        return true
    }
}

/// Registers one specific chord. No event tap or global key monitor is used.
final class GlobalHotKey: HotKeyRegistering {
    var onPress: (() -> Void)?
    private(set) var shortcut: KeyboardShortcut?
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 0
    private var activeID: UInt32 = 0
    private var pressState = HotKeyPressState()
    private static let signature: OSType = 0x53554E41 // SUNA

    func replace(with candidate: KeyboardShortcut?) -> OSStatus {
        guard candidate != shortcut else { return noErr }
        guard let candidate else {
            if let reference {
                let status = UnregisterEventHotKey(reference)
                guard status == noErr else { return status }
            }
            reference = nil; shortcut = nil; activeID = 0
            pressState = HotKeyPressState()
            return noErr
        }
        if Self.systemUses(candidate) { return OSStatus(eventHotKeyExistsErr) }
        if handler == nil {
            var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                         EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                return Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().receive(event)
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        // Claim the new chord first. A conflict must leave the old one intact.
        nextID &+= 1
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(candidate.keyCode, candidate.modifiers,
            EventHotKeyID(signature: Self.signature, id: nextID), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &newReference)
        guard status == noErr, let newReference else { return status == noErr ? OSStatus(paramErr) : status }
        if let reference {
            let removed = UnregisterEventHotKey(reference)
            if removed != noErr { UnregisterEventHotKey(newReference); return removed }
        }
        reference = newReference; shortcut = candidate; activeID = nextID
        pressState = HotKeyPressState()
        return noErr
    }

    private static func systemUses(_ shortcut: KeyboardShortcut) -> Bool {
        var result: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&result) == noErr,
              let rows = result?.takeRetainedValue() as? [[String: Any]] else { return false }
        return rows.contains { row in
            (row[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (row[kHISymbolicHotKeyCode as String] as? UInt32) == shortcut.keyCode
                && (row[kHISymbolicHotKeyModifiers as String] as? UInt32) == shortcut.modifiers
        }
    }

    private func receive(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr, reference != nil, id.signature == Self.signature, id.id == activeID else {
            return OSStatus(eventNotHandledErr)
        }
        if pressState.receive(down: GetEventKind(event) == UInt32(kEventHotKeyPressed)) { onPress?() }
        return noErr
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
