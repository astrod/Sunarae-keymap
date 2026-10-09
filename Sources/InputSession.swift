import AppKit

/// Coordinates key handling, composition, and document delivery. A synchronous
/// client query or write can reenter InputMethodKit, so guard the whole operation.
final class InputSession {
    let composer = Composer()
    private let delivery = TextDelivery()
    private var processing = false
    private var switchingInputSource = false
    private struct PendingKey {
        let code: UInt16
        let modifiers: NSEvent.ModifierFlags
        let client: TextClient
    }
    private var pendingKeys: [PendingKey] = []
    private var deferredKeys: [PendingKey] = []
    private var recoveryGeneration = 0
    private var recoveryScheduled = false
    private var recoveryAttempts = 0
    private let scheduleRecovery: (@escaping () -> Void) -> Void
    private let settings: InputSettings

    init(settings: InputSettings = .shared,
         scheduleRecovery: @escaping (@escaping () -> Void) -> Void = { action in
             DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(8), execute: action)
         }) {
        self.settings = settings
        self.scheduleRecovery = scheduleRecovery
    }

    var markedText: String { delivery.isMarked ? composer.preedit : "" }

    private func reset() {
        composer.reset()
        delivery.reset()
    }

    func commit(to client: TextClient) {
        guard !processing else { return }
        processing = true
        defer { finishProcessing() }
        recoverDeferred(force: true)
        finish(to: client)
    }

    private func finishProcessing() {
        // Client calls can deliver later key events before the current write
        // returns. Drain them only after that write and its local state update.
        // Keep the guard raised while draining; new arrivals join the same FIFO.
        var index = 0
        while index < pendingKeys.count {
            let key = pendingKeys[index]
            index += 1
            if let first = deferredKeys.first {
                if first.client.identity == key.client.identity {
                    deferredKeys.append(key)
                    continue
                }
                recoverDeferred(force: true)
            }
            let handled = processKey(keyCode: key.code, modifiers: key.modifiers,
                                     client: key.client, selectABC: { false })
            // This plain Space was consumed while a text operation was active.
            // If no direct composition remains (e.g. marked text or a second
            // space), insert it here instead of losing its original event.
            if !handled, key.code == 49 { key.client.insert(" ") }
        }
        pendingKeys.removeAll(keepingCapacity: true)
        processing = false
    }

    private func scheduleRetry() {
        guard !recoveryScheduled else { return }
        recoveryScheduled = true
        let generation = recoveryGeneration
        scheduleRecovery { [weak self] in
            guard let self, self.recoveryGeneration == generation else { return }
            self.recoveryScheduled = false
            // A synchronous IMK call can run the main loop before it returns.
            guard !self.processing else { self.scheduleRetry(); return }
            self.processing = true
            defer { self.finishProcessing() }
            self.recoveryAttempts += 1
            self.recoverDeferred(force: self.recoveryAttempts >= 3)
        }
    }

    private func recoverDeferred(force: Bool) {
        guard let first = deferredKeys.first else { return }
        let result = delivery.reconcileForInput(first.client, verifyCaretAfterRead: true)
        if result == .unavailable, !force {
            scheduleRetry()
            return
        }
        let keys = deferredKeys
        deferredKeys.removeAll(keepingCapacity: true)
        recoveryGeneration += 1
        recoveryScheduled = false
        recoveryAttempts = 0
        // A boundary or the third retry ends the wait. Never replace an
        // unreadable old range; cancel if the app changed the input context.
        for (index, key) in keys.enumerated() {
            let state = index == 0 ? result : delivery.reconcileForInput(key.client, verifyCaretAfterRead: true)
            if state == .changed {
                // These keys arrived before the document/caret changed. Do not
                // insert them into a new selection or a cleared input field.
                reset()
                return
            }
            if state == .unavailable {
                if !force {
                    deferredKeys.append(contentsOf: keys[index...])
                    scheduleRetry()
                    return
                }
                reset()
            }
            let handled = processKey(keyCode: key.code, modifiers: key.modifiers,
                                     client: key.client, selectABC: { false },
                                     mayDefer: false, alreadyReconciled: true)
            if !handled, key.code == 49 { key.client.insert(" ") }
        }
    }

    private func canQueue(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard !switchingInputSource,
              modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        let letter = KeyMap.ascii(keyCode: keyCode, shifted: modifiers.contains(.shift))?.isASCIIHangulKey == true
        let space = keyCode == 49 && modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty
        return letter || space
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
               client: TextClient, selectABC: () -> Bool = { false }) -> Bool {
        if processing {
            // Returning false would let the app insert a later letter or plain
            // Space ahead of the text operation still in progress. Other keys
            // keep their original events, including modified Space and Return.
            guard canQueue(keyCode: keyCode, modifiers: modifiers) else { return false }
            pendingKeys.append(PendingKey(code: keyCode, modifiers: modifiers, client: client))
            return true
        }
        processing = true
        let switchesSource = KeyMap.isEscapeShortcut(keyCode: keyCode, modifiers: modifiers)
            && settings.switchToABCOnEscape
        if switchesSource { switchingInputSource = true }
        defer {
            if switchesSource { switchingInputSource = false }
            finishProcessing()
        }
        if let first = deferredKeys.first {
            if first.client.identity == client.identity, canQueue(keyCode: keyCode, modifiers: modifiers) {
                recoverDeferred(force: false)
                if !deferredKeys.isEmpty {
                    deferredKeys.append(PendingKey(code: keyCode, modifiers: modifiers, client: client))
                    return true
                }
            } else {
                recoverDeferred(force: true)
            }
        }
        return processKey(keyCode: keyCode, modifiers: modifiers, client: client, selectABC: selectABC)
    }

    private func processKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                            client: TextClient, selectABC: () -> Bool, mayDefer: Bool = true,
                            alreadyReconciled: Bool = false) -> Bool {
        if KeyMap.isEscapeShortcut(keyCode: keyCode, modifiers: modifiers),
           settings.switchToABCOnEscape {
            // Keys delivered during the switch belong to the new input source
            // (for example a Vim command), not this Hangul queue.
            // Finish before TIS can reenter deactivateServer. The original
            // Escape still reaches the editor. Do not keep an English mode:
            // every later key delivered to this session can compose Korean,
            // even if IMK reuses it without an activation callback.
            finish(to: client)
            _ = selectABC()
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
        if keyCode == 49,
           modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock).isEmpty,
           delivery.isDirect, (alreadyReconciled || delivery.reconcile(client)) {
            // A web editor may queue an unhandled Space behind the next IMK
            // insertion. Keep this boundary on the same path as Hangul.
            finish(to: client)
            client.insert(" ")
            return true
        }
        guard let key = KeyMap.ascii(keyCode: keyCode, shifted: modifiers.contains(.shift)),
              key.isASCIIHangulKey else {
            finish(to: client)
            return false
        }
        switch alreadyReconciled ? .valid : delivery.reconcileForInput(client) {
        case .valid: break
        case .changed: composer.reset()
        case .unavailable:
            if mayDefer {
                deferredKeys.append(PendingKey(code: keyCode, modifiers: modifiers, client: client))
                scheduleRetry()
                return true
            }
            reset()
        }
        let result = composer.input(key)
        delivery.update(committed: result.committed, preedit: result.preedit, client: client)
        return result.handled
    }
}
