import AppKit

// Match Ghostty's NSTextInputClient contract: selection is not an insertion
// point, substring reads may be nil, and insertText ignores replacementRange.
private final class TerminalClient: TextClient {
    let bundleIdentifier: String? = "com.mitchellh.ghostty"
    var supportsDocumentAccess: Bool { true }
    var selectedRange: NSRange { NSRange(location: 0, length: 0) }
    var markedRange: NSRange { NSRange(location: 0, length: preedit.utf16.count) }
    var committed = ""
    var preedit = ""
    var replacements = 0
    var documentReads = 0
    func text(in range: NSRange) -> String? { documentReads += 1; return nil }
    func insert(_ text: String, replacing range: NSRange) {
        if range.location != NSNotFound { replacements += 1 }
        preedit = ""
        committed += text
    }
    func mark(_ text: String) { preedit = text }
    func remove(in range: NSRange) { replacements += 1; preedit = "" }
}

func runCompatibilityChecks() {
    for (keys, expected) in [("tjfrul", "설계"), ("tjfrP", "설계"),
                             ("rkk rkr rhk dul", "까 각 과 예"), ("dkssudgktpdy", "안녕하세요")] {
        let client = TerminalClient(), session = InputSession()
        type(keys, session: session, client: client)
        expect(client.committed + client.preedit, expected, "Ghostty composes \(keys)")
        expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Ghostty passes Return")
        expect(client.committed, expected, "Ghostty commits before Return")
        expect(client.preedit, "", "Ghostty clears preedit on Return")
        expect(String(client.replacements), "0", "Ghostty never replaces committed text")
        expect(String(client.documentReads), "0", "Ghostty never reads a document range")
        session.commit(to: client)
        expect(client.committed, expected, "Ghostty does not commit twice")
    }
    do {
        let client = TerminalClient(), session = InputSession()
        type("rkk", session: session, client: client)
        expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "true", "Ghostty handles composition Backspace")
        expect(client.committed + client.preedit, "가", "Ghostty restores prior vowel")
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        expect(client.committed + client.preedit, "", "Ghostty deletes last jamo")
        type("tjfrul ", session: session, client: client)
        expect(client.committed, "설계 ", "Ghostty resumes after deletion")
    }
    for id: String? in [nil, "com.apple.TextEdit", "org.example.Editor"] {
        let client = ViewClient(), session = InputSession()
        client.bundleIdentifier = id
        type("tjfrul", session: session, client: client)
        expect(client.view.string, "설계", "other editors keep direct text")
        expect(String(client.markCount), "0", "other editors do not gain composition display")
    }
}
