import AppKit
import Carbon

final class ShortcutManager {
    static let shared = ShortcutManager(settings: .shared, registration: GlobalHotKey(), toggle: {
        InputSource.toggle(beforeLeavingSunarae: InputController.commitActiveComposition)
    })
    private let settings: InputSettings
    private let registration: HotKeyRegistering
    private(set) var errorMessage: String?
    var registeredShortcut: KeyboardShortcut? { registration.shortcut }
    var savedShortcut: KeyboardShortcut? { settings.toggleShortcut }

    init(settings: InputSettings, registration: HotKeyRegistering, toggle: @escaping () -> Bool) {
        self.settings = settings
        self.registration = registration
        registration.onPress = { [weak self] in
            if toggle() { self?.errorMessage = nil }
            else {
                self?.errorMessage = "전환하지 못했어요. 입력 소스에 ABC와 두벌식 순아래가 있는지 확인해 주세요."
                NSSound.beep()
            }
        }
    }

    func restore() {
        errorMessage = register(settings.toggleShortcut)
    }

    func suspend() -> String? {
        let error = register(nil)
        errorMessage = error
        return error
    }

    @discardableResult func apply(_ shortcut: KeyboardShortcut?) -> String? {
        let error = register(shortcut)
        errorMessage = error
        if error == nil { settings.toggleShortcut = shortcut }
        return error
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
