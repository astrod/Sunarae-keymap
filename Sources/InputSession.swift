import AppKit

/// Coordinates key handling, composition, and document delivery. A synchronous
/// client query or write can reenter InputMethodKit, so guard the whole operation.
final class InputSession {
    let composer = Composer()
    private let delivery = TextDelivery()
    private var processing = false

    var markedText: String { delivery.isMarked ? composer.preedit : "" }

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

    func input(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isRepeat: Bool = false,
               client: TextClient) -> Bool {
        guard !processing else { return false }
        processing = true
        defer { processing = false }
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
