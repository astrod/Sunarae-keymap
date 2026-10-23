import AppKit
import Carbon

final class ShortcutManager {
    static let shared = ShortcutManager(settings: .shared, registration: GlobalHotKey(), mapping: SwitchKeyConfiguration.live(),
    focusRefreshChanged: { InputSourceFocusRefresh.shared.cancel() }, toggle: {
        InputSource.toggle(beforeLeavingSunarae: InputController.commitActiveComposition)
    })
    private let settings: InputSettings
    private let registration: HotKeyRegistering
    private let mapping: SwitchKeyConfiguring?
    private var suspendedForRecording = false
    var recordingIsSuspended: Bool { suspendedForRecording }
    private let focusRefreshChanged: () -> Void
    private(set) var errorMessage: String?
    var registeredShortcut: KeyboardShortcut? { registration.shortcut }
    var savedShortcut: KeyboardShortcut? { settings.toggleShortcut }
    var mappedKey: SwitchKey? { settings.mappedSwitchKey }
    var focusRefreshEnabled: Bool { settings.refreshFocusOnInputSwitch }
    var loginNeedsApproval: Bool { mappedKey != nil && mapping?.loginNeedsApproval == true }

    init(settings: InputSettings, registration: HotKeyRegistering, mapping: SwitchKeyConfiguring? = nil,
         focusRefreshChanged: @escaping () -> Void = {},
         toggle: @escaping () -> Bool) {
        self.settings = settings
        self.registration = registration
        self.mapping = mapping
        self.focusRefreshChanged = focusRefreshChanged
        registration.onPress = { [weak self] in
            if toggle() { self?.errorMessage = nil }
            else {
                self?.errorMessage = "전환하지 못했어요. 입력 소스에 ABC와 두벌식 순아래가 있는지 확인해 주세요."
                NSSound.beep()
            }
        }
    }

    func restore() {
        let wasSuspended = suspendedForRecording
        errorMessage = register(mappedKey != nil ? .mappedF18 : settings.toggleShortcut)
        if errorMessage == nil {
            suspendedForRecording = false
            restoreMapping()
            if errorMessage != nil { suspendedForRecording = wasSuspended }
        }
    }

    func restoreMapping() {
        guard !suspendedForRecording, let key = mappedKey, registeredShortcut == .mappedF18 else { return }
        do {
            guard let mapping else { throw SwitchKeyError("전환 키 매핑을 사용할 수 없어요.") }
            try mapping.restore(key); errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func suspend() -> String? {
        guard !suspendedForRecording else { return nil }
        let previous = registration.shortcut
        if let error = register(nil) { errorMessage = error; return error }
        suspendedForRecording = true
        do {
            if let key = mappedKey {
                guard let mapping else { throw SwitchKeyError("전환 키 매핑을 사용할 수 없어요.") }
                try mapping.suspend(key)
            }
        } catch {
            suspendedForRecording = false
            let rollback = register(previous)
            errorMessage = error.localizedDescription + (rollback.map { "\n이전 전환 키 복원: \($0)" } ?? "")
            return errorMessage
        }
        errorMessage = nil
        return nil
    }

    @discardableResult func apply(_ shortcut: KeyboardShortcut?, mappedKey key: SwitchKey? = nil,
                                 focusRefreshEnabled: Bool? = nil) -> String? {
        if suspendedForRecording {
            restore()
            if let errorMessage { return errorMessage }
        }
        let target: KeyboardShortcut? = key != nil ? .mappedF18 : shortcut
        let previous = registration.shortcut
        if let error = register(target) { errorMessage = error; return error }
        var ownsLogin = settings.switchKeyOwnsLoginItem
        do {
            if key != nil || mappedKey != nil {
                guard let mapping else { throw SwitchKeyError("전환 키 설정을 사용할 수 없어요.") }
                ownsLogin = try mapping.change(from: mappedKey, to: key, ownsLoginItem: ownsLogin)
            }
        } catch {
            let rollbackError = register(previous)
            errorMessage = error.localizedDescription + (rollbackError.map { "\n이전 전환 키 복원: \($0)" } ?? "")
            return errorMessage
        }
        settings.switchKeyOwnsLoginItem = key != nil && ownsLogin
        settings.toggleShortcut = target
        settings.mappedSwitchKey = key
        if let focusRefreshEnabled, settings.refreshFocusOnInputSwitch != focusRefreshEnabled {
            settings.refreshFocusOnInputSwitch = focusRefreshEnabled
            focusRefreshChanged()
        }
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
