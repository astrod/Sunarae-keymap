import AppKit

func runSpaceChecks() {
    // A web editor can deliver an unhandled Space after the next IMK insert.
    // Reproduce that ordering with real NSTextView insertion and replacement.
    for (before, initial, rest, expected) in [
        ("rkk", "r", "kr", "까 각"), ("rkr", "r", "hk", "각 과"),
        ("rhk", "d", "ul", "과 예")
    ] {
        let client = ViewClient(), session = InputSession()
        type(before, session: session, client: client)
        let handled = session.input(keyCode: 49, modifiers: [], client: client)
        type(initial, session: session, client: client)
        if !handled { client.insert(" ") }
        type(rest, session: session, client: client)
        expect(client.view.string, expected, "Space precedes the next initial: \(expected)")
        expect(String(client.markCount), "0", "Space ordering needs no marked text")
        expect(String(client.view.selectedRange().length), "0", "Space leaves no selected syllable")
    }

    for flags: NSEvent.ModifierFlags in [[], .capsLock] {
        let client = ViewClient(), session = InputSession()
        type("rkk", session: session, client: client)
        let writes = client.insertCount
        expect(String(session.input(keyCode: 49, modifiers: flags, client: client)), "true", "consume plain Space after direct Hangul")
        expect(client.view.string, "까 ", "insert exactly one space")
        expect(String(client.insertCount - writes), "1", "Space writes once")
        expect(String(session.composer.isEmpty), "true", "Space ends composition")
        expect(session.markedText, "", "Space exposes no composition")
        expect(String(client.view.hasMarkedText()), "false", "Space creates no marked range")
        let reads = client.selectionReadCount + client.textReadCount + client.markedReadCount
        let afterSpace = client.insertCount
        expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Enter still reaches the editor")
        expect(String(client.insertCount - afterSpace), "0", "Enter does not write")
        expect(String(client.selectionReadCount + client.textReadCount + client.markedReadCount - reads), "0", "Enter does not query")
        client.view.insertNewline(nil)
        type("rk", session: session, client: client)
        expect(client.view.string, "까 \n가", "input resumes after app handles Enter")
    }

    for flags: NSEvent.ModifierFlags in [.shift, .control, .option, .command, .function] {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        let writes = client.insertCount
        expect(String(session.input(keyCode: 49, modifiers: flags, client: client)), "false", "modified Space reaches the app: \(flags.rawValue)")
        expect(String(client.insertCount - writes), "0", "modified Space does not insert text")
        expect(String(session.composer.isEmpty), "true", "modified Space ends composition")
    }

    for state in ["empty", "committed", "Escape", "second space", "deleted"] {
        let client = ViewClient(), session = InputSession()
        if state != "empty" { type("rk", session: session, client: client) }
        switch state {
        case "committed": session.commit(to: client)
        case "Escape": _ = session.input(keyCode: 53, modifiers: [], client: client)
        case "second space": type(" ", session: session, client: client)
        case "deleted":
            _ = session.input(keyCode: 51, modifiers: [], client: client)
            _ = session.input(keyCode: 51, modifiers: [], client: client)
        default: break
        }
        let writes = client.insertCount
        expect(String(session.input(keyCode: 49, modifiers: [], client: client)), "false", "Space with no composition passes through: \(state)")
        expect(String(client.insertCount - writes), "0", "Space with no composition writes nothing: \(state)")
    }

    for change in ["caret", "selection", "text", "unreadable", "client"] {
        let original = ViewClient(), session = InputSession()
        type("rk", session: session, client: original)
        let client = change == "client" ? ViewClient() : original
        switch change {
        case "caret": client.view.setSelectedRange(NSRange(location: 0, length: 0))
        case "selection": client.view.setSelectedRange(NSRange(location: 0, length: 1))
        case "text":
            client.view.string = "X"
            client.view.setSelectedRange(NSRange(location: 1, length: 0))
        case "unreadable": client.unavailableTextReads = 2
        default: break
        }
        let text = client.view.string, writes = client.insertCount
        expect(String(session.input(keyCode: 49, modifiers: [], client: client)), "false", "Space after \(change) reaches app")
        expect(client.view.string, text, "Space preserves document after \(change)")
        expect(String(client.insertCount - writes), "0", "Space after \(change) does not write")
        expect(String(session.composer.isEmpty), "true", "Space clears old composition after \(change)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        client.supportsText = false
        type("rk", session: session, client: client)
        expect(String(session.input(keyCode: 49, modifiers: [], client: client)), "false", "marked fallback leaves Space to app")
        expect(client.view.string, "가", "marked fallback commits only Hangul")
        expect(String(client.view.hasMarkedText()), "false", "marked fallback ends composition")
        client.insert(" ")
        expect(client.view.string, "가 ", "app inserts one space after marked fallback")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.unavailableTextReads = 1
        client.beforeInsert = { session.commit(to: client) }
        type(" sk", session: session, client: client)
        expect(client.view.string, "가 나", "Space tolerates a transient read and reentrant commit")
        expect(String(client.markCount), "0", "Space retry does not mark text")
    }
}
