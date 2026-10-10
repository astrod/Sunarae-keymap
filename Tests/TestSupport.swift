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

// Exercise marked text and app-owned editing on a real NSTextView.
final class ViewClient: TextClient {
    let view: NSTextView
    init(view: NSTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))) {
        self.view = view
    }
    var insertCount = 0
    var markCount = 0
    var markedReadCount = 0
    var lastMarkedText = NSAttributedString(string: "")
    var beforeInsert: (() -> Void)?
    var beforeMark: (() -> Void)?
    var onMarkedRead: (() -> Void)?
    var markedRange: NSRange {
        markedReadCount += 1
        let callback = onMarkedRead; onMarkedRead = nil; callback?()
        return view.markedRange()
    }
    func insert(_ text: String) {
        insertCount += 1
        let callback = beforeInsert; beforeInsert = nil; callback?()
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func mark(_ text: NSAttributedString) {
        markCount += 1
        lastMarkedText = text
        let callback = beforeMark; beforeMark = nil; callback?()
        view.setMarkedText(text, selectedRange: NSRange(location: text.length, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}
func type(_ keys: String, session: InputSession, client: TextClient) {
    for key in keys {
        let lower = Character(String(key).lowercased())
        let position: Character = key == "<" ? "," : key == ":" ? ";" : lower
        if let (code, _) = KeyMap.positions.first(where: { $0.value == position }) {
            let flags: NSEvent.ModifierFlags = key == position ? [] : .shift
            if !session.input(keyCode: code, modifiers: flags, client: client) { client.insert(String(key)) }
        } else {
            if !session.input(keyCode: key == " " ? 49 : 36, modifiers: [], client: client) {
                client.insert(String(key))
            }
        }
    }
}
