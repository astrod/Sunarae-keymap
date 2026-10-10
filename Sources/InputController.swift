import AppKit
import InputMethodKit

private final class IMKClient: TextClient {
    let client: IMKTextInput
    init(_ client: IMKTextInput) { self.client = client }
    var identity: ObjectIdentifier { ObjectIdentifier(client) }
    var markedRange: NSRange { client.markedRange() }
    func insert(_ text: String) {
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func mark(_ text: NSAttributedString) {
        client.setMarkedText(text, selectionRange: NSRange(location: text.length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

@objc(SunaraeInputController)
final class InputController: IMKInputController {
    private let session = InputSession()
    private static weak var active: InputController?

    static func commitActiveComposition() { active?.commitComposition(nil) }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "Esc / Ctrl+[ 누르면 ABC로 전환",
                              action: #selector(toggleEscapeSwitch(_:)), keyEquivalent: "")
        item.state = InputSettings.shared.switchToABCOnEscape ? .on : .off
        menu.addItem(item)
        menu.addItem(.separator())
        let shortcut = ShortcutManager.shared.registeredShortcut?.displayName ?? "사용 안 함"
        menu.addItem(NSMenuItem(title: "한영 전환 키 설정… (\(shortcut))",
                               action: #selector(showShortcutSettings(_:)), keyEquivalent: ""))
        if let error = ShortcutManager.shared.errorMessage {
            let status = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        return menu
    }

    // IMK routes menu actions to the controller with a command dictionary.
    @objc func toggleEscapeSwitch(_ sender: Any?) {
        InputSettings.shared.switchToABCOnEscape.toggle()
    }

    @objc func showShortcutSettings(_ sender: Any?) {
        Self.commitActiveComposition()
        ShortcutSettingsController.shared.show()
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]).rawValue)
    }

    override func handle(_ event: NSEvent, client sender: Any) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }
        if event.type == .keyDown {
            return session.input(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                 client: IMKClient(client), selectABC: InputSource.selectABC)
        }
        // Finish before the click moves the caret or changes the input field.
        commitComposition(sender)
        return false
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Self.active = self
        // Preserve familiar QWERTY Command shortcuts while Korean is active.
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: InputSource.abcID)
    }

    override func commitComposition(_ sender: Any!) {
        if let client = (sender as? IMKTextInput) ?? self.client() {
            session.commit(to: IMKClient(client))
        }
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        if Self.active === self { Self.active = nil }
        super.deactivateServer(sender)
    }

    override func composedString(_ sender: Any!) -> Any! { session.markedText }
}
