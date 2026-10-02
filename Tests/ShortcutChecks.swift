import AppKit
import Carbon

private final class FakeHotKey: HotKeyRegistering {
    var onPress: (() -> Void)?
    var shortcut: KeyboardShortcut?
    var status: OSStatus = noErr
    func replace(with candidate: KeyboardShortcut?) -> OSStatus {
        if status == noErr { shortcut = candidate }
        return status
    }
}

@main struct ShortcutChecks {
    static func main() {
        _ = NSApplication.shared
        let suite = "SunaraeTests.Shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InputSettings(defaults: defaults)
        precondition(settings.toggleShortcut == nil)
        let f19 = KeyboardShortcut(keyCode: 80, modifiers: 0)
        let chord = KeyboardShortcut(keyCode: 49, modifiers: UInt32(controlKey | optionKey))
        precondition(f19.validationError == nil && f19.displayName == "F19")
        precondition(chord.validationError == nil && chord.displayName == "⌃⌥Space")
        for code: UInt32 in [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 128, UInt32.max] {
            precondition(KeyboardShortcut(keyCode: code, modifiers: UInt32(cmdKey)).validationError != nil)
        }
        for modifiers: UInt32 in [0, UInt32(shiftKey), UInt32(alphaLock), UInt32.max] {
            precondition(KeyboardShortcut(keyCode: 0, modifiers: modifiers).validationError != nil)
        }
        precondition(KeyboardShortcut(keyCode: 53, modifiers: 0).validationError != nil)
        precondition(KeyboardShortcut(keyCode: 33, modifiers: UInt32(controlKey)).validationError != nil)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command, .shift, .capsLock, .numericPad], timestamp: 0, windowNumber: 0,
            context: nil, characters: "K", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
        precondition(KeyboardShortcut(event: event) == KeyboardShortcut(keyCode: 40, modifiers: UInt32(cmdKey | shiftKey)))

        let registration = FakeHotKey()
        var toggles = 0
        let manager = ShortcutManager(settings: settings, registration: registration, toggle: { toggles += 1; return true })
        manager.restore()
        precondition(registration.shortcut == nil)
        precondition(manager.apply(f19) == nil)
        precondition(manager.registeredShortcut == f19 && settings.toggleShortcut == f19)
        precondition(InputSettings(defaults: UserDefaults(suiteName: suite)!).toggleShortcut == f19)
        registration.onPress?()
        precondition(toggles == 1)
        registration.status = OSStatus(eventHotKeyExistsErr)
        precondition(manager.apply(chord) != nil)
        precondition(settings.toggleShortcut == f19 && registration.shortcut == f19)
        registration.status = noErr
        precondition(manager.suspend() == nil)
        precondition(registration.shortcut == nil && settings.toggleShortcut == f19)
        manager.restore() // Closing without Apply restores the previous choice.
        precondition(registration.shortcut == f19)
        precondition(manager.apply(chord) == nil && settings.toggleShortcut == chord)
        registration.status = OSStatus(paramErr)
        precondition(manager.apply(nil) != nil && settings.toggleShortcut == chord)
        registration.status = noErr
        precondition(manager.apply(nil) == nil && settings.toggleShortcut == nil)
        manager.restore()
        precondition(registration.shortcut == nil)
        defaults.set(Data("broken".utf8), forKey: "toggleShortcut")
        precondition(settings.toggleShortcut == nil)
        defaults.set(try! JSONEncoder().encode(KeyboardShortcut(keyCode: UInt32.max, modifiers: 0)), forKey: "toggleShortcut")
        precondition(settings.toggleShortcut == nil)

        var presses = HotKeyPressState()
        precondition(presses.receive(down: true))
        precondition(!presses.receive(down: true)) // Holding cannot toggle repeatedly.
        precondition(!presses.receive(down: false))
        precondition(presses.receive(down: true))
        precondition(InputSource.destination(from: InputSource.sunaraeID) == InputSource.abcID)
        precondition(InputSource.destination(from: InputSource.abcID) == InputSource.sunaraeID)
        precondition(InputSource.destination(from: "com.apple.inputmethod.Korean.2SetKorean") == InputSource.sunaraeID)
        print("Shortcut validation, persistence, conflicts, repeat and toggle checks passed")
    }
}
