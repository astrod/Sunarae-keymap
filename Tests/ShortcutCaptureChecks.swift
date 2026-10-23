import AppKit
import Carbon

func runShortcutCaptureChecks() {
    func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ type: NSEvent.EventType = .flagsChanged,
               repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: repeatKey, keyCode: code)!
    }
    for key in SwitchKey.allCases where key != .capsLock {
        var capture = ShortcutCapture()
        precondition(capture.receive(event(key.keyCode, key.modifier)) == nil)
        precondition(capture.receive(event(key.keyCode)) == .mapped(key))
        capture = ShortcutCapture()
        _ = capture.receive(event(key.keyCode, key.modifier))
        precondition(capture.receive(event(40, key.modifier, .keyDown)) ==
            .shortcut(KeyboardShortcut(event: event(40, key.modifier, .keyDown))))
        precondition(capture.receive(event(key.keyCode)) == nil) // Not a second standalone choice.
    }
    for capsState: NSEvent.ModifierFlags in [[], .capsLock] {
        var capture = ShortcutCapture()
        precondition(capture.receive(event(57, capsState)) == .mapped(.capsLock))
    }
    do {
        var capture = ShortcutCapture()
        _ = capture.receive(event(61, .option))
        _ = capture.receive(event(58, .option)) // Both Options must not become Right Option.
        _ = capture.receive(event(61, .option))
        precondition(capture.receive(event(58)) == nil)
        _ = capture.receive(event(61, .option))
        precondition(capture.receive(event(61)) == .mapped(.rightOption))
    }
    do {
        var capture = ShortcutCapture(initialFlags: .command)
        precondition(capture.receive(event(54)) == nil) // Held before recording began.
        _ = capture.receive(event(54, .command))
        _ = capture.receive(event(61, [.option, .command]))
        _ = capture.receive(event(61, .command))
        precondition(capture.receive(event(54)) == nil)
        precondition(capture.receive(event(53, [], .keyDown)) == .cancel)
    }
    do {
        var capture = ShortcutCapture()
        _ = capture.receive(event(59, .control)) // Left modifiers still work in chords.
        precondition(capture.receive(event(49, [.control, .option], .keyDown)) ==
            .shortcut(KeyboardShortcut(keyCode: 49, modifiers: UInt32(controlKey | optionKey))))
        precondition(capture.receive(event(59)) == nil)
        for code: UInt16 in [54, 57, 61, 62] { // keyDown alone cannot declare a modifier press.
            if case .mapped = capture.receive(event(code, [], .keyDown)) { preconditionFailure("wrong event type") }
        }
        precondition(capture.receive(event(80, [], .keyDown)) == .shortcut(KeyboardShortcut(keyCode: 80, modifiers: 0)))
        precondition(capture.receive(event(80, [], .keyDown, repeatKey: true)) == nil)
        for (code, flags): (UInt16, NSEvent.ModifierFlags) in [(0, []), (0, .shift), (49, .shift), (0, .function)] {
            guard case .rejected = capture.receive(event(code, flags, .keyDown)) else {
                preconditionFailure("unsupported capture accepted")
            }
        }
    }
    print("Local shortcut capture: standalone modifiers, chords, cancellation and rejected keys passed")
}
