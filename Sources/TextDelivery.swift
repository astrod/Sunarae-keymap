import Foundation

/// Owns only text written by this session. Direct output stays in the document
/// without a marked range; clients without document access use marked text.
final class TextDelivery {
    enum Reconciliation {
        case valid, unavailable, changed, unconfirmedChange
    }
    private enum Output {
        case none
        case direct(NSRange, String, provisional: Bool)
        case marked(Bool)
    }
    private var output = Output.none
    private var clientID: ObjectIdentifier?
    private var recoveryCaret: NSRange?
    private var recoveryHasUnconfirmedChange = false
    // This uninterrupted session's own direct output. Keep deletion on
    // the same text-client path as insertion, including committed jamo.
    // Navigation, shortcuts, focus changes and document mismatches clear it.
    private var recentText = ""
    private var recentEnd: Int?

    var isMarked: Bool {
        if case .marked = output { return true }
        return false
    }

    var isDirect: Bool {
        if case .direct = output { return true }
        return false
    }

    func reset() {
        output = .none
        clientID = nil
        recoveryCaret = nil
        recoveryHasUnconfirmedChange = false
        recentText = ""
        recentEnd = nil
    }

    /// Replace only the text we last wrote, at the caret where we left it.
    /// Cursor movement, app edits, and client changes end the local composition.
    func reconcile(_ client: TextClient) -> Bool {
        let result = reconcileForInput(client)
        if result != .valid { reset() }
        return result == .valid
    }

    /// A missing reply alone does not establish that the document changed.
    /// Keep the anchor for a later check, without allowing a replacement yet.
    func reconcileForInput(_ client: TextClient) -> Reconciliation {
        let result = check(client, verifyCaretAfterRead: false)
        if result == .changed { reset() }
        return result
    }

    /// Deferred keys have already been consumed. A stale reply must not erase
    /// them along with the anchor needed to confirm the actual document state.
    func reconcileDeferred(_ client: TextClient) -> Reconciliation {
        if recoveryCaret == nil, case let .direct(range, _, _) = output {
            // Also pin each new range while replaying a queue. Confirmation
            // must not relocate an append to the same letter elsewhere.
            recoveryCaret = NSRange(location: NSMaxRange(range), length: 0)
        }
        var result = check(client, verifyCaretAfterRead: true)
        if result == .changed {
            recoveryHasUnconfirmedChange = true
            // Confirm once with the original anchor and composition intact.
            // This is bounded, including at Return/commit and the last retry.
            result = check(client, verifyCaretAfterRead: true)
        }
        if result == .changed { reset() }
        if result == .valid { recoveryHasUnconfirmedChange = false }
        if result == .unavailable, recoveryHasUnconfirmedChange {
            // Missing confirmation is not proof of a safe insertion point.
            // Retain this evidence across retries so timeout cannot insert
            // consumed keys into a possibly changed selection or document.
            return .unconfirmedChange
        }
        return result
    }

    private func check(_ client: TextClient, verifyCaretAfterRead: Bool) -> Reconciliation {
        if let clientID, clientID != client.identity {
            return .changed
        }
        switch output {
        case let .direct(range, text, provisional):
            var sawChangedCaret = false
            var lastCaret: NSRange?
            for attempt in 0..<2 {
                let caret = client.selectedRange
                guard caret.location != NSNotFound, caret.location >= 0,
                      caret.length != NSNotFound else { continue }
                guard caret.length == 0 else {
                    sawChangedCaret = true
                    continue
                }
                if let recoveryCaret, caret != recoveryCaret {
                    sawChangedCaret = true
                    continue
                }
                lastCaret = caret
                var candidate = range
                if caret.location != NSMaxRange(range) {
                    guard provisional, caret.location >= text.utf16.count else {
                        sawChangedCaret = true
                        continue
                    }
                    // First insertions and appends use the client's current
                    // selection. Resolve their position once from the text.
                    candidate = NSRange(location: caret.location - text.utf16.count,
                                        length: text.utf16.count)
                }
                guard let observed = client.text(in: candidate) else { continue }
                guard observed == text else { return .changed }
                // Extra client calls can move the caret. Check it again after
                // a retry before allowing the replacement or deletion.
                if attempt > 0 || verifyCaretAfterRead {
                    let confirmedCaret = client.selectedRange
                    if confirmedCaret.location == NSNotFound || confirmedCaret.length == NSNotFound {
                        recoveryCaret = caret
                        return .unavailable
                    }
                    if confirmedCaret != caret { return .changed }
                }
                output = .direct(candidate, text, provisional: false)
                recoveryCaret = nil
                recentEnd = NSMaxRange(candidate)
                return .valid
            }
            if sawChangedCaret { return .changed }
            // A delayed retry must not relocate a provisional first insertion
            // to another occurrence of the same letter after a cursor move.
            recoveryCaret = lastCaret ?? NSRange(location: NSMaxRange(range), length: 0)
            return .unavailable
        case .marked(true):
            let range = client.markedRange
            if range.location == NSNotFound || range.length == 0 { return .changed }
        case .none where !recentText.isEmpty:
            let caret = client.selectedRange
            let last = String(recentText.last!)
            guard caret.length == 0, caret.location == recentEnd,
                  caret.location >= last.utf16.count,
                  client.text(in: NSRange(location: caret.location - last.utf16.count,
                                         length: last.utf16.count)) == last else {
                return .changed
            }
        default:
            break
        }
        return .valid
    }

    /// Keep deletion on the same path as insertion. Passing the last owned
    /// Backspace to a web editor may queue it behind the next IMK insertion.
    /// Call only after reconcile and when the composer has no preedit left.
    func removeLast(in client: TextClient) -> Bool {
        let range: NSRange
        switch output {
        case let .direct(current, text, _) where text.count == 1:
            range = current
        case .none:
            guard let last = recentText.last, let end = recentEnd else { return false }
            let length = String(last).utf16.count
            range = NSRange(location: end - length, length: length)
        default:
            return false
        }
        client.remove(in: range)
        recentText.removeLast()
        recentEnd = range.location
        output = .none
        if recentText.isEmpty { reset() }
        return true
    }

    func update(committed: String, preedit: String, client: TextClient) {
        if case .none = output {
            guard !committed.isEmpty || !preedit.isEmpty else { return }
            clientID = client.identity
            let selection = client.selectedRange
            // Ghostty exposes selection text for services such as Quick Look,
            // not an editable document. It ignores insertText replacementRange,
            // so it needs standard marked composition even if TSM advertises
            // document access. Do not commit individual jamo to its terminal.
            if client.bundleIdentifier != "com.mitchellh.ghostty", client.supportsDocumentAccess,
               selection.location != NSNotFound, selection.length != NSNotFound,
               selection.location >= 0, selection.length >= 0,
               selection.length <= Int.max - selection.location {
                output = .direct(selection, "", provisional: true)
            } else {
                // Query the documented capability. A zero-length substring is
                // nil even in NSTextView and cannot detect document access.
                output = .marked(false)
            }
        }
        switch output {
        case let .direct(range, previousText, _):
            let firstInsertion = previousText.isEmpty
            let text = committed + preedit
            recentText.removeLast(previousText.count)
            recentText.append(text)
            recentEnd = range.location + text.utf16.count
            let appending = !firstInsertion && text != previousText && text.hasPrefix(previousText)
            if firstInsertion {
                // NSNotFound means insert at the client's current selection.
                // Sending a cached, explicit range here takes a different
                // Chromium path and can target a document the app has cleared.
                client.insert(text)
            } else if appending {
                // The old text and caret were verified by reconcile. If that
                // text stays intact, append only the new suffix at the caret.
                client.insert(String(text.dropFirst(previousText.count)))
            } else if text != previousText {
                // Reconcile already checked this range. Send only changes.
                client.insert(text, replacing: range)
            }
            if preedit.isEmpty {
                output = .none
            } else {
                output = .direct(NSRange(location: range.location + committed.utf16.count,
                                         length: preedit.utf16.count), preedit,
                                 provisional: firstInsertion || appending)
            }
        case let .marked(hadMarkedRange):
            if !committed.isEmpty { client.insert(committed) }
            if !preedit.isEmpty || hadMarkedRange && committed.isEmpty { client.mark(preedit) }
            let range = client.markedRange
            output = preedit.isEmpty ? .none : .marked(range.location != NSNotFound && range.length > 0)
            if preedit.isEmpty { clientID = nil }
        case .none:
            break
        }
    }

}
