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
        if failNextWrite { failNextWrite = false; throw SwitchKeyError("write failed") }
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
        if failRegister { throw SwitchKeyError("register failed") }
        state = requireApproval ? .needsApproval : .enabled
    }
    func unregister() throws {
        removals += 1
        if failUnregister { throw SwitchKeyError("unregister failed") }
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

func runSwitchKeyChecks() {
    let caps = KeyRemapping(source: SwitchKey.capsLock.usage, destination: KeyRemapping.f18)
    let other = KeyRemapping(source: 0x7000000e6, destination: 0x7000000e7)
    let foreignCaps = KeyRemapping(source: SwitchKey.capsLock.usage, destination: 0x700000029)
    let letter = KeyRemapping(source: 0x700000004, destination: 0x700000005)
    precondition(try! KeyRemapping.updating([other], from: nil, to: .capsLock) == [other, caps])
    precondition(try! KeyRemapping.updating([other, caps], from: .capsLock, to: nil) == [other])
    precondition(try! KeyRemapping.updating([foreignCaps], from: .capsLock, to: nil) == [foreignCaps])
    precondition((try? KeyRemapping.updating([foreignCaps], from: nil, to: .capsLock)) == nil)
    precondition((try? KeyRemapping.updating([letter], from: nil, to: .capsLock)) == nil)
    precondition((try? KeyRemapping.updating([letter, caps], from: .capsLock, to: nil)) == nil)
    precondition(try! KeyRemapping.updating([letter, caps], from: nil, to: .capsLock) == [letter, caps])
    precondition(!caps.needsInputMonitoring && !other.needsInputMonitoring && letter.needsInputMonitoring)

    // Successful enable/disable preserves other mappings and a preexisting login item.
    do {
        let device = MappingDeviceStub([other]); let login = LoginLaunchStub()
        let configuration = SwitchKeyConfiguration(devices: { [device] }, login: login)
        let owns = try! configuration.change(from: nil, to: .capsLock, ownsLoginItem: false)
        precondition(owns && device.entries == [other, caps] && login.state == .enabled)
        try! configuration.restore(.capsLock)
        precondition(device.writes == 1) // Already applied: no property rewrite.
        _ = try! configuration.change(from: .capsLock, to: nil, ownsLoginItem: owns)
        precondition(device.entries == [other] && login.state == .off)
        login.state = .enabled
        precondition(try! !configuration.change(from: nil, to: .capsLock, ownsLoginItem: false))
        _ = try! configuration.change(from: .capsLock, to: nil, ownsLoginItem: false)
        precondition(login.state == .enabled && login.removals == 1)
    }
    // Check all keyboards before touching one; roll back earlier writes on a later failure.
    do {
        let a = MappingDeviceStub([other]); let b = MappingDeviceStub([foreignCaps])
        let login = LoginLaunchStub()
        let configuration = SwitchKeyConfiguration(devices: { [a, b] }, login: login)
        precondition((try? configuration.change(from: nil, to: .capsLock, ownsLoginItem: false)) == nil)
        precondition(a.writes == 0 && login.registrations == 0)
        b.entries = []; b.failNextWrite = true
        precondition((try? configuration.change(from: nil, to: .capsLock, ownsLoginItem: false)) == nil)
        precondition(a.entries == [other] && b.entries.isEmpty && login.state == .off)
        precondition(a.writes == 2 && login.removals == 1)
        precondition(try! configuration.change(from: nil, to: .capsLock, ownsLoginItem: false))
        b.failNextWrite = true
        precondition((try? configuration.change(from: .capsLock, to: nil, ownsLoginItem: true)) == nil)
        precondition(a.entries == [other, caps] && b.entries == [caps] && login.state == .enabled)
    }
    // A mapping change between read and write belongs to the other tool.
    do {
        let device = MappingDeviceStub(); device.changeOnSecondRead = [foreignCaps]
        let login = LoginLaunchStub()
        let configuration = SwitchKeyConfiguration(devices: { [device] }, login: login)
        precondition((try? configuration.change(from: nil, to: .capsLock, ownsLoginItem: false)) == nil)
        precondition(device.entries == [foreignCaps] && device.writes == 0 && login.state == .off)
    }
    // Login failures must not change mappings; approval pending is shown, never called enabled.
    do {
        let device = MappingDeviceStub(); let login = LoginLaunchStub()
        let configuration = SwitchKeyConfiguration(devices: { [device] }, login: login)
        login.failRegister = true
        precondition((try? configuration.change(from: nil, to: .capsLock, ownsLoginItem: false)) == nil && device.entries.isEmpty)
        login.failRegister = false; login.requireApproval = true
        precondition(try! configuration.change(from: nil, to: .capsLock, ownsLoginItem: false))
        precondition(configuration.loginNeedsApproval && device.entries == [caps])
        login.failUnregister = true
        precondition((try? configuration.change(from: .capsLock, to: nil, ownsLoginItem: true)) == nil)
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
        let configuration = SwitchKeyConfiguration(devices: { [device] }, login: login)
        let manager = ShortcutManager(settings: settings, registration: hotKey, mapping: configuration, toggle: { true })
        precondition(manager.apply(old) == nil)
        hotKey.fail = true
        precondition(manager.apply(nil, mappedKey: .capsLock) != nil)
        precondition(login.registrations == 0 && device.entries == [other] && settings.toggleShortcut == old)
        hotKey.fail = false; login.failRegister = true
        precondition(manager.apply(nil, mappedKey: .capsLock) != nil)
        precondition(!(settings.mappedSwitchKey == .capsLock) && settings.toggleShortcut == old && hotKey.shortcut == old)
        login.failRegister = false
        precondition(manager.apply(nil, mappedKey: .capsLock) == nil)
        precondition((settings.mappedSwitchKey == .capsLock) && settings.switchKeyOwnsLoginItem)
        precondition(settings.toggleShortcut == .mappedF18 && manager.mappedKey == .capsLock)
        precondition((InputSettings(defaults: UserDefaults(suiteName: suite)!).mappedSwitchKey == .capsLock))
        precondition(manager.suspend() == nil)
        manager.restore()
        precondition(hotKey.shortcut == .mappedF18 && login.registrations == 2)
        // Another keyboard after login/reconnect receives the mapping on restore.
        device.entries = [other]
        manager.restoreMapping()
        precondition(device.entries == [other, caps])
        login.failUnregister = true
        precondition(manager.apply(old, mappedKey: nil) != nil)
        precondition(hotKey.shortcut == .mappedF18 && (settings.mappedSwitchKey == .capsLock))
        login.failUnregister = false
        precondition(manager.apply(old, mappedKey: nil) == nil)
        precondition(hotKey.shortcut == old && settings.toggleShortcut == old && !(settings.mappedSwitchKey == .capsLock))
        precondition(settings.mappedSwitchKey == nil && !settings.switchKeyOwnsLoginItem)
        precondition(device.entries == [other] && login.state == .off)
        let count = device.writes
        manager.restoreMapping()
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
        let configuration = SwitchKeyConfiguration(devices: { [device] }, login: login)
        let manager = ShortcutManager(settings: settings, registration: CapsHotKeyStub(), mapping: configuration, toggle: { true })
        precondition(manager.apply(old) == nil)
        precondition(manager.apply(nil, mappedKey: .capsLock) == nil)
        precondition(manager.apply(nil, mappedKey: .capsLock) == nil)
        precondition(login.registrations == 1 && settings.switchKeyOwnsLoginItem)
        login.state = .off
        manager.restore()
        precondition(login.registrations == 1 && manager.loginNeedsApproval)
        precondition(manager.apply(nil, mappedKey: .capsLock) == nil)
        precondition(login.registrations == 2 && !manager.loginNeedsApproval)
        precondition(manager.mappedKey == .capsLock && settings.switchKeyOwnsLoginItem)
        let failedHotKey = CapsHotKeyStub(); failedHotKey.fail = true
        let afterRestart = ShortcutManager(settings: settings, registration: failedHotKey, mapping: configuration, toggle: { true })
        device.entries = []
        afterRestart.restore()
        afterRestart.restoreMapping() // A device arrival must not bypass a hotkey conflict.
        precondition(device.entries.isEmpty && afterRestart.errorMessage != nil)
    }
    // All four keys can replace one another without touching unrelated mappings.
    for oldKey in SwitchKey.allCases {
        for newKey in SwitchKey.allCases {
            let oldMapping = KeyRemapping(source: oldKey.usage, destination: KeyRemapping.f18)
            let newMapping = KeyRemapping(source: newKey.usage, destination: KeyRemapping.f18)
            precondition(!oldMapping.needsInputMonitoring && !newMapping.needsInputMonitoring)
            let unrelated = KeyRemapping(source: 0x7000000e1, destination: 0x7000000e5)
            let a = MappingDeviceStub([unrelated, oldMapping]); let b = MappingDeviceStub([oldMapping])
            let login = LoginLaunchStub(); login.state = .enabled
            let config = SwitchKeyConfiguration(devices: { [a, b] }, login: login)
            precondition(try! config.change(from: oldKey, to: newKey, ownsLoginItem: true))
            precondition(a.entries == [unrelated, newMapping] && b.entries == [newMapping])
            precondition(login.registrations == 0 && login.removals == 0)
            try! config.suspend(newKey)
            precondition(a.entries == [unrelated] && b.entries.isEmpty && login.state == .enabled)
            try! config.restore(newKey)
            precondition(a.entries == [unrelated, newMapping] && b.entries == [newMapping])
            _ = try! config.change(from: newKey, to: nil, ownsLoginItem: true)
            precondition(a.entries == [unrelated] && b.entries.isEmpty && login.state == .off)
        }
    }
    do {
        let a = MappingDeviceStub([caps]); let b = MappingDeviceStub([caps])
        let login = LoginLaunchStub(); login.state = .enabled
        let config = SwitchKeyConfiguration(devices: { [a, b] }, login: login)
        b.failNextWrite = true
        precondition((try? config.change(from: .capsLock, to: .rightCommand, ownsLoginItem: true)) == nil)
        precondition(a.entries == [caps] && b.entries == [caps] && login.removals == 0)
        b.entries.append(other) // Right Option already belongs to another tool.
        let writes = a.writes
        precondition((try? config.change(from: .capsLock, to: .rightOption, ownsLoginItem: true)) == nil)
        precondition(a.entries == [caps] && a.writes == writes && b.entries == [caps, other])
    }
    // Upgrade keeps Caps Lock and login ownership; successful Apply clears legacy settings.
    do {
        let suite = "SunaraeTests.SwitchUpgrade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "capsLockToF18Enabled")
        defaults.set(true, forKey: "capsLockOwnsLoginItem")
        let settings = InputSettings(defaults: defaults)
        settings.toggleShortcut = .mappedF18
        let device = MappingDeviceStub([caps]); let login = LoginLaunchStub(); login.state = .enabled
        let hotkey = CapsHotKeyStub()
        let config = SwitchKeyConfiguration(devices: { [device] }, login: login)
        let manager = ShortcutManager(settings: settings, registration: hotkey, mapping: config, toggle: { true })
        manager.restore()
        precondition(manager.mappedKey == .capsLock && settings.switchKeyOwnsLoginItem)
        precondition(device.writes == 0 && hotkey.shortcut == .mappedF18)
        device.failNextWrite = true
        precondition(manager.suspend() != nil && device.entries == [caps] && hotkey.shortcut == .mappedF18)
        precondition(!manager.recordingIsSuspended)
        precondition(manager.suspend() == nil && device.entries.isEmpty && hotkey.shortcut == nil)
        manager.restoreMapping() // Device notifications cannot remap a key during recording.
        precondition(device.entries.isEmpty)
        device.failNextWrite = true
        manager.restore()
        precondition(manager.recordingIsSuspended && manager.errorMessage != nil)
        device.failNextWrite = true
        precondition(manager.apply(nil, mappedKey: .rightControl) != nil)
        precondition(manager.mappedKey == .capsLock && manager.recordingIsSuspended)
        manager.restore() // A failed recording cleanup can be retried.
        precondition(!manager.recordingIsSuspended && device.entries == [caps])
        precondition(defaults.bool(forKey: "capsLockToF18Enabled")) // Recording never saves choices.
        device.failNextWrite = true
        precondition(manager.apply(nil, mappedKey: .rightOption) != nil)
        precondition(manager.mappedKey == .capsLock && device.entries == [caps])
        precondition(manager.apply(nil, mappedKey: .rightOption) == nil)
        precondition(manager.mappedKey == .rightOption && settings.switchKeyOwnsLoginItem)
        precondition(defaults.object(forKey: "capsLockToF18Enabled") == nil)
        precondition(defaults.object(forKey: "capsLockOwnsLoginItem") == nil)
        precondition(InputSettings(defaults: defaults).mappedSwitchKey == .rightOption)
        precondition(manager.apply(KeyboardShortcut(keyCode: 80, modifiers: 0)) == nil)
        precondition(device.entries.isEmpty && login.state == .off && manager.mappedKey == nil)
        precondition(!settings.switchKeyOwnsLoginItem)
        defaults.set(true, forKey: "capsLockToF18Enabled")
        precondition(settings.mappedSwitchKey == nil) // Explicit new 'none' wins over old preferences.
    }
    print("Switch key mapping, login registration, preservation and rollback checks passed")
}
