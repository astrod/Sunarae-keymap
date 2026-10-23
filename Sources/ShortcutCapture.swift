import AppKit

/// Used only by the settings window's local event monitor.
struct ShortcutCapture {
    enum Result: Equatable {
        case mapped(SwitchKey), shortcut(KeyboardShortcut), cancel, rejected(String)
    }
    private static let heldMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]
    private var pending: SwitchKey?
    private var mixed: Bool

    init(initialFlags: NSEvent.ModifierFlags = []) {
        mixed = !initialFlags.intersection(Self.heldMask).isEmpty
    }

    mutating func receive(_ event: NSEvent) -> Result? {
        let held = event.modifierFlags.intersection(Self.heldMask)
        if event.type == .flagsChanged {
            let key = SwitchKey.allCases.first { $0.keyCode == event.keyCode }
            // Caps Lock reports a lock-state change rather than a held modifier.
            if key == .capsLock, held.isEmpty, !mixed, pending == nil { return .mapped(.capsLock) }
            if held.isEmpty {
                let selected = !mixed && pending?.keyCode == event.keyCode ? pending : nil
                pending = nil; mixed = false
                return selected.map(Result.mapped)
            }
            if !mixed, pending == nil, let key, key != .capsLock, held == key.modifier {
                pending = key
            } else {
                pending = nil; mixed = true
            }
            return nil
        }
        guard event.type == .keyDown else { return nil }
        pending = nil; mixed = !held.isEmpty
        guard !event.isARepeat else { return nil }
        let shortcut = KeyboardShortcut(event: event)
        if shortcut.keyCode == 53 && shortcut.modifiers == 0 { return .cancel }
        if event.modifierFlags.contains(.function),
           KeyboardShortcut.functionKeys[shortcut.keyCode] == nil,
           !(114...126).contains(shortcut.keyCode) {
            return .rejected("Fn 조합은 지원하지 않아요. Control·Option·Command 조합을 골라 주세요.")
        }
        if let error = shortcut.validationError { return .rejected(error) }
        return .shortcut(shortcut)
    }
}
