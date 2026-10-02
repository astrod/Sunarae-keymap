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
        get {
            guard let data = defaults.data(forKey: "toggleShortcut"),
                  let value = try? JSONDecoder().decode(KeyboardShortcut.self, from: data),
                  value.validationError == nil else { return nil }
            return value
        }
        set {
            guard let value = newValue, value.validationError == nil,
                  let data = try? JSONEncoder().encode(value) else {
                defaults.removeObject(forKey: "toggleShortcut")
                return
            }
            defaults.set(data, forKey: "toggleShortcut")
        }
    }
}
