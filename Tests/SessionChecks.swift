import AppKit

func runSessionChecks() {
    let finishingKeys: [(String, UInt16, NSEvent.ModifierFlags)] = [
        ("Enter", 36, []), ("Space", 49, []), ("Shift-Space", 49, .shift),
        ("Tab", 48, []), ("Escape", 53, []), ("Control-[", 33, .control),
        ("Left", 123, []), ("Command-C", 8, .command),
        ("Control-Space", 49, .control), ("Option-R", 15, .option)
    ]
    for (name, code, flags) in finishingKeys {
        let client = ViewClient(), session = InputSession()
        type("rkk", session: session, client: client)
        expect(session.markedText, "까", "active composition before \(name)")
        let writes = client.insertCount
        expect(String(session.input(keyCode: code, modifiers: flags, client: client)), "false", "pass original \(name)")
        expect(String(client.insertCount - writes), "1", "commit once before \(name)")
        expect(client.view.string, "까", "do not insert the finishing key \(name)")
        expect(String(client.view.hasMarkedText()), "false", "end marked text \(name)")
        session.commit(to: client)
        expect(String(client.insertCount - writes), "1", "later commit does not duplicate \(name)")
        type("sk", session: session, client: client)
        expect(client.view.string, "까나", "same session resumes after \(name)")
    }
    for (keys, expected) in sunaraeExamples {
        let client = ViewClient(), session = InputSession()
        type(keys, session: session, client: client)
        expect(client.view.string, expected, "AppKit composition \(keys)")
        expect(String(client.markCount > 0), "true", "every client uses marked composition \(keys)")
        session.commit(to: client)
        expect(client.view.string, expected, "commit preserves \(keys)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        client.insert("😀 ")
        for (key, expected) in [("r", "ㄱ"), ("k", "가"), ("k", "까")] {
            type(key, session: session, client: client)
            expect(client.view.string, "😀 " + expected, "visible marked text after emoji")
            expect(String(client.view.hasMarkedText()), "true", "composition remains active")
            expect(String(client.view.selectedRange().length), "0", "marked text is not selected")
            expect(String(client.view.selectedRange().location), "4", "caret follows UTF-16 text")
            let attributes = client.lastMarkedText.attributes(at: 0, effectiveRange: nil)
            expect(String((attributes[.underlineStyle] as? NSNumber)?.intValue ?? -1), "0", "explicit zero underline")
            expect(String((attributes[.backgroundColor] as? NSColor)?.alphaComponent == 0), "true", "explicit clear background")
        }
        expect(String(client.insertCount), "1", "uncommitted syllable never becomes document insertions")
        _ = session.input(keyCode: 36, modifiers: [], client: client)
        client.view.insertNewline(nil)
        type("sk", session: session, client: client)
        expect(client.view.string, "😀 까\n나", "app owns newline after commit")
    }
    for boundary in ["next key", "Enter", "commit", "Backspace"] {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.view.unmarkText()
        client.view.string = ""
        client.view.setSelectedRange(NSRange(location: 0, length: 0))
        switch boundary {
        case "next key": type("sk", session: session, client: client)
        case "Enter": _ = session.input(keyCode: 36, modifiers: [], client: client)
        case "commit": session.commit(to: client)
        default: expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "false", "cancelled Backspace belongs to app")
        }
        expect(client.view.string, boundary == "next key" ? "나" : "", "do not restore app-cancelled text: \(boundary)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        session.commit(to: client) // IMK finishes before navigation or a click.
        client.view.setSelectedRange(NSRange(location: 0, length: 0))
        type("sk", session: session, client: client)
        expect(client.view.string, "나가", "new composition after caret movement")
        session.commit(to: client)
        client.view.setSelectedRange(NSRange(location: 0, length: 2))
        type("akfr", session: session, client: client)
        expect(client.view.string, "맑", "first marked update replaces user's selection")
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        expect(client.view.string, "말", "compound final Backspace")
    }
    for action in ["type", "commit"] {
        let first = ViewClient(), second = ViewClient(), session = InputSession()
        type("rk", session: session, client: first)
        second.insert("X")
        if action == "type" { type("sk", session: session, client: second) }
        else { session.commit(to: second) }
        expect(first.view.string, "가", "client switch preserves old text")
        expect(second.view.string, action == "type" ? "X나" : "X", "old composition never reaches another client")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.view.unmarkText()
        client.view.string = "외부 수정"
        client.view.setSelectedRange(NSRange(location: 5, length: 0))
        session.commit(to: client)
        expect(client.view.string, "외부 수정", "external content is never restored or replaced")
        type("sk", session: session, client: client)
        expect(client.view.string, "외부 수정나", "new composition after external change")
    }
    for punctuation in [",", ";", ":", "<", " ", "  "] {
        let client = ViewClient(), session = InputSession()
        type("rkk" + punctuation + "rkr", session: session, client: client)
        expect(client.view.string, "까" + punctuation + "각", "literal app-owned boundary \(punctuation)")
    }
}
