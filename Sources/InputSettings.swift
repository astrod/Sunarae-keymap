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
}
