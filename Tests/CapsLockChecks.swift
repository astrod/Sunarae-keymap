import AppKit
import Carbon

private final class MappingDeviceStub: KeyboardMappingDevice {
    var entries: [KeyRemapping]
    var writes = 0
    var failNextWrite = false
    var changeOnSecondRead: [KeyRemapping]?
    var reads = 0
    init(_ entries: [KeyRemapping] = []) { self.entries = entries }
    func read() throws -> [KeyRemapping] {
        reads += 1
        if reads == 2, let changeOnSecondRead { entries = changeOnSecondRead }
        return entries
    }
    func write(_ value: [KeyRemapping]) throws {
        writes += 1
        if failNextWrite { failNextWrite = false; throw CapsLockError("write failed") }
        entries = value
    }
}

private final class LoginLaunchStub: LoginLaunching {
    var state = LoginLaunchState.off
    var failRegister = false
    var failUnregister = false
    var requireApproval = false
    var registrations = 0
    var removals = 0
    func register() throws {
        registrations += 1
        if failRegister { throw CapsLockError("register failed") }
        state = requireApproval ? .needsApproval : .enabled
    }
    func unregister() throws {
        removals += 1
        if failUnregister { throw CapsLockError("unregister failed") }
        state = .off
    }
}

private final class CapsHotKeyStub: HotKeyRegistering {
    var onPress: (() -> Void)?
    var shortcut: KeyboardShortcut?
    var fail = false
    func replace(with value: KeyboardShortcut?) -> OSStatus {
        if fail { return OSStatus(eventHotKeyExistsErr) }
        shortcut = value; return noErr
    }
}

func runCapsLockChecks() {
    let caps = KeyRemapping.capsToF18
    let other = KeyRemapping(source: 0x7000000e6, destination: 0x7000000e7)
    let foreignCaps = KeyRemapping(source: KeyRemapping.capsLock, destination: 0x700000029)
    let letter = KeyRemapping(source: 0x700000004, destination: 0x700000005)
    precondition(try! KeyRemapping.updating([other], enabled: true) == [other, caps])
    precondition(try! KeyRemapping.updating([other, caps], enabled: false) == [other])
    precondition(try! KeyRemapping.updating([foreignCaps], enabled: false) == [foreignCaps])
    precondition((try? KeyRemapping.updating([foreignCaps], enabled: true)) == nil)
    precondition((try? KeyRemapping.updating([letter], enabled: true)) == nil)
    precondition((try? KeyRemapping.updating([letter, caps], enabled: false)) == nil)
    precondition(try! KeyRemapping.updating([letter, caps], enabled: true) == [letter, caps])
    precondition(!caps.needsInputMonitoring && !other.needsInputMonitoring && letter.needsInputMonitoring)

    // Successful enable/disable preserves other mappings and a preexisting login item.
    do {
        let device = MappingDeviceStub([other]); let login = LoginLaunchStub()
        let configuration = CapsLockConfiguration(devices: { [device] }, login: login)
        let owns = try! configuration.enable()
        precondition(owns && device.entries == [other, caps] && login.state == .enabled)
        try! configuration.restore()
        precondition(device.writes == 1) // Already applied: no property rewrite.
        try! configuration.disable(removeLoginItem: owns)
        precondition(device.entries == [other] && login.state == .off)
        login.state = .enabled
        precondition(try! !configuration.enable())
        try! configuration.disable(removeLoginItem: false)
        precondition(login.state == .enabled && login.removals == 1)
    }
    // Check all keyboards before touching one; roll back earlier writes on a later failure.
    do {
        let a = MappingDeviceStub([other]); let b = MappingDeviceStub([foreignCaps])
        let login = LoginLaunchStub()
        let configuration = CapsLockConfiguration(devices: { [a, b] }, login: login)
        precondition((try? configuration.enable()) == nil)
        precondition(a.writes == 0 && login.registrations == 0)
        b.entries = []; b.failNextWrite = true
        precondition((try? configuration.enable()) == nil)
        precondition(a.entries == [other] && b.entries.isEmpty && login.state == .off)
        precondition(a.writes == 2 && login.removals == 1)
        precondition(try! configuration.enable())
        b.failNextWrite = true
        precondition((try? configuration.disable(removeLoginItem: true)) == nil)
        precondition(a.entries == [other, caps] && b.entries == [caps] && login.state == .enabled)
    }
    // A mapping change between read and write belongs to the other tool.
    do {
        let device = MappingDeviceStub(); device.changeOnSecondRead = [foreignCaps]
        let login = LoginLaunchStub()
        let configuration = CapsLockConfiguration(devices: { [device] }, login: login)
        precondition((try? configuration.enable()) == nil)
        precondition(device.entries == [foreignCaps] && device.writes == 0 && login.state == .off)
    }
    // Login failures must not change mappings; approval pending is shown, never called enabled.
    do {
        let device = MappingDeviceStub(); let login = LoginLaunchStub()
        let configuration = CapsLockConfiguration(devices: { [device] }, login: login)
        login.failRegister = true
        precondition((try? configuration.enable()) == nil && device.entries.isEmpty)
        login.failRegister = false; login.requireApproval = true
        precondition(try! configuration.enable())
        precondition(configuration.loginNeedsApproval && device.entries == [caps])
        login.failUnregister = true
        precondition((try? configuration.disable(removeLoginItem: true)) == nil)
        precondition(device.entries == [caps])
    }
    // Settings and hotkey changes commit together, including disable failures and cancel.
    do {
        let suite = "SunaraeTests.CapsLock.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InputSettings(defaults: defaults)
        let old = KeyboardShortcut(keyCode: 80, modifiers: 0)
        let device = MappingDeviceStub([other]); let login = LoginLaunchStub(); let hotKey = CapsHotKeyStub()
        let configuration = CapsLockConfiguration(devices: { [device] }, login: login)
        let manager = ShortcutManager(settings: settings, registration: hotKey, capsLock: configuration, toggle: { true })
        precondition(manager.apply(old) == nil)
        hotKey.fail = true
        precondition(manager.apply(nil, capsLockEnabled: true) != nil)
        precondition(login.registrations == 0 && device.entries == [other] && settings.toggleShortcut == old)
        hotKey.fail = false; login.failRegister = true
        precondition(manager.apply(nil, capsLockEnabled: true) != nil)
        precondition(!settings.capsLockToF18Enabled && settings.toggleShortcut == old && hotKey.shortcut == old)
        login.failRegister = false
        precondition(manager.apply(nil, capsLockEnabled: true) == nil)
        precondition(settings.capsLockToF18Enabled && settings.capsLockOwnsLoginItem)
        precondition(settings.toggleShortcut == .capsLockF18 && manager.shortcutBeforeCapsLock == old)
        precondition(InputSettings(defaults: UserDefaults(suiteName: suite)!).capsLockToF18Enabled)
        precondition(manager.suspend() == nil)
        manager.restore()
        precondition(hotKey.shortcut == .capsLockF18 && login.registrations == 2)
        // Another keyboard after login/reconnect receives the mapping on restore.
        device.entries = [other]
        manager.restoreCapsLockMapping()
        precondition(device.entries == [other, caps])
        login.failUnregister = true
        precondition(manager.apply(old, capsLockEnabled: false) != nil)
        precondition(hotKey.shortcut == .capsLockF18 && settings.capsLockToF18Enabled)
        login.failUnregister = false
        precondition(manager.apply(manager.shortcutBeforeCapsLock, capsLockEnabled: false) == nil)
        precondition(hotKey.shortcut == old && settings.toggleShortcut == old && !settings.capsLockToF18Enabled)
        precondition(settings.shortcutBeforeCapsLock == nil && !settings.capsLockOwnsLoginItem)
        precondition(device.entries == [other] && login.state == .off)
        let count = device.writes
        manager.restoreCapsLockMapping()
        precondition(device.writes == count)
    }
    // Apply repairs a removed login registration without losing the original shortcut.
    do {
        let suite = "SunaraeTests.CapsRepair.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InputSettings(defaults: defaults)
        let old = KeyboardShortcut(keyCode: 80, modifiers: 0)
        let login = LoginLaunchStub(); let device = MappingDeviceStub()
        let configuration = CapsLockConfiguration(devices: { [device] }, login: login)
        let manager = ShortcutManager(settings: settings, registration: CapsHotKeyStub(), capsLock: configuration, toggle: { true })
        precondition(manager.apply(old) == nil)
        precondition(manager.apply(nil, capsLockEnabled: true) == nil)
        precondition(manager.apply(nil, capsLockEnabled: true) == nil)
        precondition(login.registrations == 1 && settings.capsLockOwnsLoginItem)
        login.state = .off
        manager.restore()
        precondition(login.registrations == 1 && manager.loginNeedsApproval)
        precondition(manager.apply(nil, capsLockEnabled: true) == nil)
        precondition(login.registrations == 2 && !manager.loginNeedsApproval)
        precondition(manager.shortcutBeforeCapsLock == old && settings.capsLockOwnsLoginItem)
        let failedHotKey = CapsHotKeyStub(); failedHotKey.fail = true
        let afterRestart = ShortcutManager(settings: settings, registration: failedHotKey, capsLock: configuration, toggle: { true })
        device.entries = []
        afterRestart.restore()
        afterRestart.restoreCapsLockMapping() // A device arrival must not bypass a hotkey conflict.
        precondition(device.entries.isEmpty && afterRestart.errorMessage != nil)
    }
    print("Caps Lock mapping, login registration, preservation and rollback checks passed")
}
