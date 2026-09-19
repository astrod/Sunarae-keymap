import AppKit
import InputMethodKit
import Carbon

private final class IMKClient: TextClient {
    let client: IMKTextInput
    init(_ client: IMKTextInput) { self.client = client }
    var identity: ObjectIdentifier { ObjectIdentifier(client) }
    var supportsDocumentAccess: Bool {
        client.supportsProperty(TSMDocumentPropertyTag(kTSMDocumentSupportDocumentAccessPropertyTag))
    }
    var selectedRange: NSRange { client.selectedRange() }
    var markedRange: NSRange { client.markedRange() }
    func text(in range: NSRange) -> String? { client.attributedSubstring(from: range)?.string }
    func insert(_ text: String, replacing range: NSRange) {
        client.insertText(text, replacementRange: range)
    }
    func mark(_ text: String) {
        client.setMarkedText(text, selectionRange: NSRange(location: text.utf16.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func remove(in range: NSRange) {
        // Web clients may ignore an empty insertText during a key event.
        // An empty marked replacement deletes this exact range immediately,
        // without leaving marked text or queueing a native Backspace behind
        // the next insertText. Do not add a second commit/insert operation.
        client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                             replacementRange: range)
    }
}

@objc(SunaraeInputController)
final class InputController: IMKInputController {
    private let session = InputSession()

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]).rawValue)
    }

    override func handle(_ event: NSEvent, client sender: Any) -> Bool {
        guard let client = sender as? IMKTextInput else { return false }
        if event.type == .keyDown {
            return session.input(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                 client: IMKClient(client))
        }
        // With direct output there may be no marked text for InputMethodKit's
        // default mouse handling to commit. End our local state on clicks too.
        commitComposition(sender)
        return false
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // Preserve familiar QWERTY Command shortcuts while Korean is active.
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
    }

    override func commitComposition(_ sender: Any!) {
        if let client = (sender as? IMKTextInput) ?? self.client() {
            session.commit(to: IMKClient(client))
        }
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        super.deactivateServer(sender)
    }

    override func composedString(_ sender: Any!) -> Any! { session.markedText }
}
