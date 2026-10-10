import AppKit

/// Composes only the client's marked text. Committed document text belongs to
/// the app: this session never reads or replaces a document range.
final class InputSession {
    let composer = Composer()
    private var clientID: ObjectIdentifier?
    private var markedRangeReported = false
    private var processing = false
    private var switchingInputSource = false
    private struct PendingKey {
        let code: UInt16
        let modifiers: NSEvent.ModifierFlags
        let client: TextClient
    }
    private var pendingKeys: [PendingKey] = []
    private let settings: InputSettings

    init(settings: InputSettings = .shared) { self.settings = settings }

    var markedText: String { composer.preedit }

    private func reset() {
        composer.reset()
        clientID = nil
        markedRangeReported = false
    }

    private func validateComposition(in client: TextClient) {
        if clientID != client.identity || (markedRangeReported && !client.hasMarkedText) {
            // The client changed or the app ended/cancelled its marked text.
            // Do not recreate the old syllable in a new input field.
            reset()
        }
    }

    private func update(committed: String = "", in client: TextClient) {
        let preedit = composer.preedit
        clientID = client.identity
        if !committed.isEmpty { client.insert(committed) }
        // An empty mark removes the final jamo during Backspace. It addresses
        // the existing marked text, never an explicit document range.
        let value = NSAttributedString(string: preedit, attributes: [
            .underlineStyle: 0, .backgroundColor: NSColor.clear
        ])
        client.mark(value)
        markedRangeReported = !preedit.isEmpty && client.hasMarkedText
        if preedit.isEmpty { clientID = nil }
    }

    private func finish(to client: TextClient) {
        validateComposition(in: client)
        let text = composer.flush()
        reset()
        if !text.isEmpty { client.insert(text) }
    }

    func commit(to client: TextClient) {
        guard !processing else { return }
        processing = true
        defer { finishProcessing() }
        finish(to: client)
    }

    private func canQueue(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard !switchingInputSource,
              modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        let letter = KeyMap.ascii(keyCode: keyCode, shifted: modifiers.contains(.shift))?.isASCIIHangulKey == true
        let space = keyCode == 49 && modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty
        return letter || space
    }

    private func finishProcessing() {
        // A synchronous IMK call can reenter this session. Keep later Hangul
        // and Space keys in order until the current call returns. No timers.
        var index = 0
        while index < pendingKeys.count {
            let key = pendingKeys[index]
            index += 1
            let handled = processKey(keyCode: key.code, modifiers: key.modifiers,
                                     client: key.client, selectABC: { false })
            // This Space was already consumed by the nested input call.
            if !handled, key.code == 49 { key.client.insert(" ") }
        }
        pendingKeys.removeAll(keepingCapacity: true)
        processing = false
    }

    func input(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
               client: TextClient, selectABC: () -> Bool = { false }) -> Bool {
        if processing {
            guard canQueue(keyCode: keyCode, modifiers: modifiers) else { return false }
            pendingKeys.append(PendingKey(code: keyCode, modifiers: modifiers, client: client))
            return true
        }
        processing = true
        switchingInputSource = KeyMap.isEscapeShortcut(keyCode: keyCode, modifiers: modifiers)
            && settings.switchToABCOnEscape
        defer {
            switchingInputSource = false
            finishProcessing()
        }
        return processKey(keyCode: keyCode, modifiers: modifiers, client: client, selectABC: selectABC)
    }

    private func processKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                            client: TextClient, selectABC: () -> Bool) -> Bool {
        if KeyMap.isEscapeShortcut(keyCode: keyCode, modifiers: modifiers), settings.switchToABCOnEscape {
            finish(to: client)
            _ = selectABC()
            return false
        }
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            finish(to: client)
            return false
        }
        if keyCode == 51 {
            validateComposition(in: client)
            guard composer.backspace() else { return false }
            update(in: client)
            return true
        }
        guard let key = KeyMap.ascii(keyCode: keyCode, shifted: modifiers.contains(.shift)), key.isASCIIHangulKey else {
            // Commit once, then leave Enter, Space, Tab, punctuation and
            // navigation to the app. Never insert or synthesize an Enter.
            finish(to: client)
            return false
        }
        validateComposition(in: client)
        let result = composer.input(key)
        update(committed: result.committed, in: client)
        return result.handled
    }
}
