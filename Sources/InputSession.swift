import AppKit

/// Coordinates key handling, composition, and document delivery. A synchronous
/// client query or write can reenter InputMethodKit, so guard the whole operation.
final class InputSession {
    let composer = Composer()
    private let delivery = TextDelivery()
    private var processing = false
    private var passingThroughToABC = false
    private let settings: InputSettings

    init(settings: InputSettings = .shared) {
        self.settings = settings
    }

    var markedText: String { delivery.isMarked ? composer.preedit : "" }

    func activate() { passingThroughToABC = false }

    private func reset() {
        composer.reset()
        delivery.reset()
    }

    func commit(to client: TextClient) {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        finish(to: client)
    }

    private func finish(to client: TextClient) {
        // Direct text is already final in the document. Enter must reach the
        // app with no extra query, insertText, or compositionend event.
        if delivery.isMarked, delivery.reconcile(client) {
            let text = composer.flush()
            if !text.isEmpty { client.insert(text) }
        }
        reset()
    }

    // Key repeats use the same composition rules as separate key presses.
    func input(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
               client: TextClient, selectABC: () -> Bool = { false },
               sunaraeIsSelected: () -> Bool = { true }) -> Bool {
        guard !processing else { return false }
        processing = true
        defer { processing = false }
        if passingThroughToABC {
            // Some clients reselect an existing IMK session without activating
            // it again. Resume when Sunarae is selected, even without that callback.
            guard sunaraeIsSelected() else { return false }
            passingThroughToABC = false
        }
        if KeyMap.isEscapeShortcut(keyCode: keyCode, modifiers: modifiers),
           settings.switchToABCOnEscape {
            // Finish before switching, since IMK can reenter deactivateServer.
            // Returning false delivers the original Escape/Ctrl-[ to the app.
            finish(to: client)
            // Web clients can queue another key before they finish switching.
            // Do not compose it as Korean while waiting for deactivation.
            // Set this before the call so a reentrant activation can clear it.
            passingThroughToABC = true
            if !selectABC() { passingThroughToABC = false }
            return false
        }
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            finish(to: client)
            return false
        }
        if keyCode == 51 {
            if !delivery.reconcile(client) { composer.reset() }
            guard composer.backspace() else { return delivery.removeLast(in: client) }
            if composer.preedit.isEmpty, delivery.removeLast(in: client) { return true }
            delivery.update(committed: "", preedit: composer.preedit, client: client)
            return true
        }
        guard let key = KeyMap.ascii(keyCode: keyCode, shifted: modifiers.contains(.shift)),
              key.isASCIIHangulKey else {
            finish(to: client)
            return false
        }
        if !delivery.reconcile(client) { composer.reset() }
        let result = composer.input(key)
        delivery.update(committed: result.committed, preedit: result.preedit, client: client)
        return result.handled
    }
}
