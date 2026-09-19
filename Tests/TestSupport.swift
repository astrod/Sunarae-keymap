import AppKit

var checks = 0
var failures = 0
func expect(_ actual: String, _ expected: String, _ label: String) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL \(label): expected [\(expected)], got [\(actual)]")
    }
}
func compose(_ keys: String) -> String {
    let composer = Composer()
    var result = ""
    for key in keys {
        let update = composer.input(key)
        result += update.committed
        if !update.handled { result.append(key) }
    }
    return result + composer.flush()
}

// Exercise client replacement/selection semantics on AppKit's real text view.
final class ViewClient: TextClient {
    let view: NSTextView
    init(view: NSTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))) {
        self.view = view
    }
    var supportsRanges = true
    var supportsText = true
    var supportsDocumentAccess: Bool { supportsRanges && supportsText }
    var insertCount = 0
    var markCount = 0
    var selectionReadCount = 0
    var textReadCount = 0
    var markedReadCount = 0
    var lastInsertionRange = NSRange(location: NSNotFound, length: 0)
    var lastInsertedText = ""
    var ignoreEmptyReplacement = false
    var beforeInsert: (() -> Void)?
    var staleSelection: NSRange?
    var onSelectionRead: (() -> Void)?
    var onTextRead: (() -> Void)?
    var onMarkedRead: (() -> Void)?
    var selectedRange: NSRange {
        selectionReadCount += 1
        let callback = onSelectionRead; onSelectionRead = nil; callback?()
        if let staleSelection {
            self.staleSelection = nil
            return staleSelection
        }
        return supportsRanges ? view.selectedRange() : NSRange(location: NSNotFound, length: NSNotFound)
    }
    var markedRange: NSRange {
        markedReadCount += 1
        let callback = onMarkedRead; onMarkedRead = nil; callback?()
        return view.markedRange()
    }
    func text(in range: NSRange) -> String? {
        textReadCount += 1
        let callback = onTextRead; onTextRead = nil; callback?()
        guard supportsText else { return nil }
        return view.attributedSubstring(forProposedRange: range, actualRange: nil)?.string
    }
    func insert(_ text: String, replacing range: NSRange) {
        insertCount += 1
        lastInsertionRange = range
        lastInsertedText = text
        let callback = beforeInsert; beforeInsert = nil; callback?()
        if ignoreEmptyReplacement && text.isEmpty && range.location != NSNotFound { return }
        // A remote editor may have cleared its document since it reported its
        // selection. Reject stale ranges instead of throwing an AppKit exception.
        if range.location != NSNotFound && NSMaxRange(range) > view.string.utf16.count { return }
        view.insertText(text, replacementRange: range)
    }
    func mark(_ text: String) {
        markCount += 1
        view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func remove(in range: NSRange) {
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: range)
    }
}
func type(_ keys: String, session: InputSession, client: ViewClient) {
    for key in keys {
        let lower = Character(String(key).lowercased())
        let position: Character = key == "<" ? "," : key == ":" ? ";" : lower
        if let (code, _) = KeyMap.positions.first(where: { $0.value == position }) {
            let flags: NSEvent.ModifierFlags = key == position ? [] : .shift
            if !session.input(keyCode: code, modifiers: flags, client: client) { client.insert(String(key)) }
        } else {
            _ = session.input(keyCode: key == " " ? 49 : 36, modifiers: [], client: client)
            client.insert(String(key))
        }
    }
}
