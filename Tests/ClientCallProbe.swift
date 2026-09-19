import AppKit

// Fixed, isolated documents. Count the TextClient calls that become IMK calls
// in the app; no latency claim is made from this in-process NSTextView probe.
private final class CountedClient: TextClient {
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    var calls: [String: Int] = [:]
    var replacements = 0
    var currentSelectionInsertions = 0
    var sentUTF16Units = 0
    var supportsDocumentAccess: Bool {
        calls["capability", default: 0] += 1
        return true
    }
    var selectedRange: NSRange {
        calls["selection", default: 0] += 1
        return view.selectedRange()
    }
    var markedRange: NSRange {
        calls["markedRange", default: 0] += 1
        return view.markedRange()
    }
    func text(in range: NSRange) -> String? {
        calls["substring", default: 0] += 1
        return view.attributedSubstring(forProposedRange: range, actualRange: nil)?.string
    }
    func insert(_ text: String, replacing range: NSRange) {
        calls["insert", default: 0] += 1
        if range.location == NSNotFound { currentSelectionInsertions += 1 }
        else { replacements += 1 }
        sentUTF16Units += text.utf16.count
        view.insertText(text, replacementRange: range)
    }
    func remove(in range: NSRange) {
        calls["remove", default: 0] += 1
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: range)
    }
    func mark(_ text: String) {
        calls["mark", default: 0] += 1
        view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}

@main
private enum ClientCallProbe {
    static func main() throws {
        _ = NSApplication.shared
        let cases = [
            ("chat sentence", "dkssudgktpdy. enrjjqlfh gksrmfdmf dlqfurgkqslek.", "안녕하세요. 두꺼비로 한글을 입력합니다."),
            ("commas and punctuation", "todrkr, rkqt, ekfr, r; r: r<", "생각, 값, 닭, ㄱ; ㄱ: ㄱ<"),
            ("single word", "dkssudgktpdy", "안녕하세요")
        ]
        var rows: [[String: Any]] = []
        for (name, keys, expected) in cases {
            let client = CountedClient(), session = InputSession()
            for key in keys {
                let lower = Character(String(key).lowercased())
                let position: Character = key == "<" ? "," : key == ":" ? ";" : lower
                let code = KeyMap.positions.first { $0.value == position }?.key
                    ?? (key == " " ? 49 : 47)
                let flags: NSEvent.ModifierFlags = key == position ? [] : .shift
                if !session.input(keyCode: code, modifiers: flags, client: client) {
                    // Model the app's normal key handling, without counting it
                    // as another call from the input method to the app.
                    client.view.insertText(String(key), replacementRange: NSRange(location: NSNotFound, length: 0))
                }
            }
            let handled = session.input(keyCode: 36, modifiers: [], client: client)
            guard client.view.string == expected, !handled else {
                fputs("Call probe failed: \(name), actual [\(client.view.string)]\n", stderr)
                exit(1)
            }
            rows.append(["case": name, "keys_including_enter": keys.count + 1,
                         "text": client.view.string, "calls": client.calls,
                         "total_calls": client.calls.values.reduce(0, +),
                         "explicit_replacements": client.replacements,
                         "current_selection_insertions": client.currentSelectionInsertions,
                         "sent_utf16_units": client.sentUTF16Units])
        }
        let result: [String: Any] = ["scope": "TextClient call counts on real in-process NSTextView; not IPC or screen latency", "cases": rows]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
