import Foundation

/// Owns only text written by this session. Direct output stays in the document
/// without a marked range; clients without document access use marked text.
final class TextDelivery {
    private enum Output {
        case none
        case direct(NSRange, String, provisional: Bool)
        case marked(Bool)
    }
    private var output = Output.none
    private var clientID: ObjectIdentifier?
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
        recentText = ""
        recentEnd = nil
    }

    /// Replace only the text we last wrote, at the caret where we left it.
    /// Cursor movement, app edits, and client changes end the local composition.
    func reconcile(_ client: TextClient) -> Bool {
        if let clientID, clientID != client.identity {
            reset()
            return false
        }
        switch output {
        case let .direct(range, text, provisional):
            // Retry one unavailable read or unexpected caret before dropping
            // composition. Do not wait or run the event loop between attempts.
            for attempt in 0..<2 {
                let caret = client.selectedRange
                guard caret.location != NSNotFound, caret.location >= 0, caret.length == 0 else {
                    continue
                }
                var candidate = range
                if caret.location != NSMaxRange(range) {
                    guard provisional, caret.location >= text.utf16.count else { continue }
                    // First insertions and appends use the client's current
                    // selection. Resolve their position once from the text.
                    candidate = NSRange(location: caret.location - text.utf16.count,
                                        length: text.utf16.count)
                }
                guard let observed = client.text(in: candidate) else { continue }
                // A concrete mismatch ends composition without another query.
                guard observed == text else { reset(); return false }
                // Extra client calls can move the caret. Check it again after
                // a retry before allowing the replacement or deletion.
                if attempt > 0, client.selectedRange != caret { reset(); return false }
                output = .direct(candidate, text, provisional: false)
                recentEnd = NSMaxRange(candidate)
                return true
            }
            reset()
            return false
        case .marked(true):
            let range = client.markedRange
            if range.location == NSNotFound || range.length == 0 { reset(); return false }
        case .none where !recentText.isEmpty:
            let caret = client.selectedRange
            let last = String(recentText.last!)
            guard caret.length == 0, caret.location == recentEnd,
                  caret.location >= last.utf16.count,
                  client.text(in: NSRange(location: caret.location - last.utf16.count,
                                         length: last.utf16.count)) == last else {
                reset()
                return false
            }
        default:
            break
        }
        return true
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
            if client.supportsDocumentAccess,
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
