import Foundation

/// Only preferences are persisted; typed text never goes into UserDefaults.
final class InputSettings {
    static let shared = InputSettings()
    private let defaults: UserDefaults
    private let escapeKey = "switchToABCOnEscape"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // Missing preferences default to false, preserving the existing behavior.
    var switchToABCOnEscape: Bool {
        get { defaults.bool(forKey: escapeKey) }
        set { defaults.set(newValue, forKey: escapeKey) }
    }

    var toggleShortcut: KeyboardShortcut? {
        get { shortcut(forKey: "toggleShortcut") }
        set { saveShortcut(newValue, forKey: "toggleShortcut") }
    }

    var capsLockToF18Enabled: Bool {
        get { defaults.bool(forKey: "capsLockToF18Enabled") }
        set { defaults.set(newValue, forKey: "capsLockToF18Enabled") }
    }
    var capsLockOwnsLoginItem: Bool {
        get { defaults.bool(forKey: "capsLockOwnsLoginItem") }
        set { defaults.set(newValue, forKey: "capsLockOwnsLoginItem") }
    }
    var shortcutBeforeCapsLock: KeyboardShortcut? {
        get { shortcut(forKey: "shortcutBeforeCapsLock") }
        set { saveShortcut(newValue, forKey: "shortcutBeforeCapsLock") }
    }

    private func shortcut(forKey key: String) -> KeyboardShortcut? {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
              value.validationError == nil else { return nil }
        return value
    }
    private func saveShortcut(_ shortcut: KeyboardShortcut?, forKey key: String) {
        guard let value = shortcut, value.validationError == nil,
              let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
