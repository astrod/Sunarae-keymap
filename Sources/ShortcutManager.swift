import AppKit
import Carbon

final class ShortcutManager {
    static let shared = ShortcutManager(settings: .shared, registration: GlobalHotKey(), capsLock: CapsLockConfiguration.live(), toggle: {
        InputSource.toggle(beforeLeavingSunarae: InputController.commitActiveComposition)
    })
    private let settings: InputSettings
    private let registration: HotKeyRegistering
    private let capsLock: CapsLockConfiguring?
    private(set) var errorMessage: String?
    var registeredShortcut: KeyboardShortcut? { registration.shortcut }
    var savedShortcut: KeyboardShortcut? { settings.toggleShortcut }
    var capsLockEnabled: Bool { settings.capsLockToF18Enabled }
    var shortcutBeforeCapsLock: KeyboardShortcut? { settings.shortcutBeforeCapsLock }
    var loginNeedsApproval: Bool { capsLockEnabled && capsLock?.loginNeedsApproval == true }

    init(settings: InputSettings, registration: HotKeyRegistering, capsLock: CapsLockConfiguring? = nil,
         toggle: @escaping () -> Bool) {
        self.settings = settings
        self.registration = registration
        self.capsLock = capsLock
        registration.onPress = { [weak self] in
            if toggle() { self?.errorMessage = nil }
            else {
                self?.errorMessage = "전환하지 못했어요. 입력 소스에 ABC와 두벌식 순아래가 있는지 확인해 주세요."
                NSSound.beep()
            }
        }
    }

    func restore() {
        errorMessage = register(capsLockEnabled ? .capsLockF18 : settings.toggleShortcut)
        if errorMessage == nil { restoreCapsLockMapping() }
    }

    func restoreCapsLockMapping() {
        guard capsLockEnabled, registeredShortcut == .capsLockF18 else { return }
        do { try capsLock?.restore(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func suspend() -> String? {
        let error = register(nil)
        errorMessage = error
        return error
    }

    @discardableResult func apply(_ shortcut: KeyboardShortcut?, capsLockEnabled enabled: Bool = false) -> String? {
        let target: KeyboardShortcut? = enabled ? .capsLockF18 : shortcut
        let previous = registration.shortcut
        if let error = register(target) { errorMessage = error; return error }
        var ownsLogin = settings.capsLockOwnsLoginItem
        do {
            if enabled || capsLockEnabled {
                guard let capsLock else { throw CapsLockError("Caps Lock 설정을 사용할 수 없어요.") }
                if enabled { ownsLogin = try capsLock.enable() || ownsLogin }
                else { try capsLock.disable(removeLoginItem: ownsLogin) }
            }
        } catch {
            let rollbackError = register(previous)
            errorMessage = error.localizedDescription + (rollbackError.map { "\n이전 전환 키 복원: \($0)" } ?? "")
            return errorMessage
        }
        if enabled && !capsLockEnabled { settings.shortcutBeforeCapsLock = settings.toggleShortcut }
        if !enabled { settings.shortcutBeforeCapsLock = nil }
        settings.capsLockOwnsLoginItem = enabled && ownsLogin
        settings.toggleShortcut = target
        settings.capsLockToF18Enabled = enabled
        errorMessage = nil
        return nil
    }

    private func register(_ shortcut: KeyboardShortcut?) -> String? {
        if let error = shortcut?.validationError { return error }
        let status = registration.replace(with: shortcut)
        if status == noErr { return nil }
        if status == eventHotKeyExistsErr {
            return "다른 단축키가 이미 사용 중이에요. 다른 키를 고르거나 기존 설정을 해제해 주세요."
        }
        return "단축키를 등록하지 못했어요 (\(status)). 기존 설정은 바꾸지 않았어요."
    }
}
