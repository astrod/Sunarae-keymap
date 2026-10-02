import AppKit

func runSessionChecks() {
    // Direct text is already in the document: finishing only clears local state.
    // Marked text still needs its safety check before it can be committed.
    let finishingKeys: [(String, UInt16, NSEvent.ModifierFlags)] = [
        ("Enter", 36, []), ("Space", 49, []), ("Tab", 48, []),
        ("Escape", 53, []), ("Control-[", 33, .control),
        ("Left", 123, []), ("Command-C", 8, .command),
        ("Control-Space", 49, .control), ("Option-R", 15, .option)
    ]
    for direct in [true, false] {
        for (name, code, flags) in finishingKeys {
            let client = ViewClient(), session = InputSession()
            client.supportsText = direct
            type("rk", session: session, client: client)
            let selections = client.selectionReadCount, texts = client.textReadCount
            let marked = client.markedReadCount, writes = client.insertCount
            let label = "\(direct ? "direct" : "marked") \(name)"
            expect(String(session.input(keyCode: code, modifiers: flags, client: client)), "false", "pass through \(label)")
            expect(String(client.selectionReadCount - selections), "0", "finish without selection query \(label)")
            expect(String(client.textReadCount - texts), "0", "finish without text query \(label)")
            expect(String(client.markedReadCount - marked), direct ? "0" : "1", "one marked check \(label)")
            expect(String(client.insertCount - writes), direct ? "0" : "1", "commit writes \(label)")
            expect(client.view.string, "가", "preserve text \(label)")
            expect(String(session.composer.isEmpty), "true", "clear local state \(label)")
            // IMK may reuse this session without another activation callback.
            type("sk", session: session, client: client)
            expect(client.view.string, "가나", "Korean continues in the same session \(label)")
        }
    }
    do {
        let client = ViewClient(), session = InputSession()
        client.supportsText = false
        type("rk", session: session, client: client)
        client.view.unmarkText()
        client.view.string = ""
        let writes = client.insertCount
        _ = session.input(keyCode: 36, modifiers: [], client: client)
        expect(client.view.string, "", "Enter cannot restore composition the app removed")
        expect(String(client.insertCount - writes), "0", "cancelled composition is not committed")
    }
    do {
        let client = ViewClient(), session = InputSession()
        // The next selection reply still describes a document the app has cleared.
        client.staleSelection = NSRange(location: 12, length: 0)
        type("d", session: session, client: client)
        expect(client.view.string, "ㅇ", "stale selection cannot swallow the first key")
        expect(String(client.lastInsertionRange.location == NSNotFound), "true", "fresh text uses the client's current selection")
        type("kssudgktpdy", session: session, client: client)
        expect(client.view.string, "안녕하세요", "resolve first insertion before composing the next key")
        expect(String(client.markCount), "0", "stale first selection does not require marked composition")
    }
    do {
        let client = ViewClient(), session = InputSession()
        client.insert("😀 ")
        client.staleSelection = NSRange(location: 0, length: 0)
        type("rk", session: session, client: client)
        expect(client.view.string, "😀 가", "resolve first insertion after a stale zero caret and emoji")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        // A chat sends/clears its input without replacing the native client object.
        client.view.string = ""
        client.view.setSelectedRange(NSRange(location: 0, length: 0))
        client.staleSelection = NSRange(location: 1, length: 0)
        type("sk", session: session, client: client)
        expect(client.view.string, "나", "typing resumes after app clears the same input client")
        expect(String(client.markCount), "0", "cleared input stays modeless")
    }
    do {
        let client = ViewClient(), session = InputSession()
        // NSTextView returns nil for empty ranges. This previously forced every
        // real native client into marked mode, while the NSString-based mock passed.
        expect(String(client.text(in: NSRange(location: 0, length: 0)) == nil), "true", "real empty-range query returns nil")
        type("r", session: session, client: client)
        expect(client.text(in: NSRange(location: 0, length: 1)) ?? "<nil>", "ㄱ", "real nonempty-range query works")
        type("kr", session: session, client: client)
        expect(client.view.string, "각", "document access independent of empty-range query")
        expect(String(client.markCount), "0", "real NSTextView uses direct output")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("ghaf", session: session, client: client)
        expect(client.view.string, "홈ㄹ", "standard consonant before next vowel")
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        expect(client.view.string, "홈", "undo next initial")
        type("fhdn dlqfur gkrfur", session: session, client: client)
        session.commit(to: client)
        expect(client.view.string, "홈로우 입력 학력", "AppKit preserves consonant order across syllables")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("dkssudgktpdy akfr", session: session, client: client)
        expect(client.view.string, "안녕하세요 맑", "AppKit composition")
        session.commit(to: client)
        session.commit(to: client)
        expect(client.view.string, "안녕하세요 맑", "idempotent commit")
        expect(String(client.markedRange.length == 0 || client.markedRange.location == NSNotFound), "true", "committed marked range")
        client.view.setSelectedRange(NSRange(location: 0, length: 5))
        type("djqt", session: session, client: client)
        expect(client.view.string, "없 맑", "replace selection")
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        expect(client.view.string, "업 맑", "compound final deletion")
        expect(String(session.input(keyCode: 8, modifiers: .command, client: client)), "false", "Command-C passthrough")
        expect(client.view.string, "업 맑", "shortcut commits once")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rkk", session: session, client: client)
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        expect(client.view.string, "가", "AppKit undo repeated vowel")
        if !session.input(keyCode: 51, modifiers: [], client: client) { client.view.deleteBackward(nil) }
        if !session.input(keyCode: 51, modifiers: [], client: client) { client.view.deleteBackward(nil) }
        expect(client.view.string, "", "AppKit last jamo deletion")
        client.insert("😀")
        type("rk", session: session, client: client)
        session.commit(to: client)
        expect(client.view.string, "😀가", "UTF-16 selection after emoji")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        session.commit(to: client) // A client requests a commit, e.g. focus changes.
        type("sk", session: session, client: client)
        session.commit(to: client)
        expect(client.view.string, "가나", "client-side commit does not duplicate")
        expect(String(session.input(keyCode: 15, modifiers: .option, client: client)), "false", "Option passthrough")
        expect(String(session.input(keyCode: 49, modifiers: .control, client: client)), "false", "Control-Space passthrough")
    }

    for (keys, expected) in sunaraeExamples {
        let client = ViewClient(), session = InputSession()
        type(keys, session: session, client: client)
        expect(client.view.string, expected, "direct AppKit \(keys)")
        expect(String(client.markCount), "0", "no marked output \(keys)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("djfuqek", session: session, client: client)
        expect(client.view.string, "어렵다", "direct output is already visible")
        expect(session.markedText, "", "input method exposes no marked composition")
        let writes = client.insertCount
        expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Enter reaches app")
        expect(String(client.insertCount), String(writes), "Enter does not insert or end a marked composition")
        expect(String(client.markCount), "0", "Enter never creates marked text")
        client.view.insertNewline(nil) // AppKit handles the unconsumed Return.
        type("rk", session: session, client: client)
        expect(client.view.string, "어렵다\n가", "typing after native app handles Enter")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.view.setSelectedRange(NSRange(location: 0, length: 0))
        type("sk", session: session, client: client)
        expect(client.view.string, "나가", "cursor movement cannot overwrite prior syllable")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.insert("X", replacing: NSRange(location: 0, length: 1))
        type("sk", session: session, client: client)
        expect(client.view.string, "X나", "same-position app edit cannot be overwritten")
    }
    do {
        let first = ViewClient(), second = ViewClient(), session = InputSession()
        type("rk", session: session, client: first)
        second.insert("가") // Same caret and text, but a different document/client.
        type("sk", session: session, client: second)
        expect(first.view.string, "가", "client switch preserves old document")
        expect(second.view.string, "가나", "client switch discards prior local composition")
    }
    for readableSelection in [true, false] {
        let client = ViewClient(), session = InputSession()
        client.supportsRanges = readableSelection
        client.supportsText = false
        type("akfr", session: session, client: client)
        expect(client.view.string, "맑", "fallback composition")
        expect(String(client.markCount > 0), "true", "fallback uses marked text when ranges are unavailable")
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        expect(client.view.string, "말", "fallback Backspace")
        session.commit(to: client)
        session.commit(to: client)
        expect(client.view.string, "말", "fallback commits once")
    }

    // Ordinary punctuation should reach the app without first rewriting the same
    // Korean text. All punctuation goes straight to the app.
    for (keys, punctuation) in [("rk", ","), ("a", ","), ("rkqt", ";"), ("r", ":"), ("rkk", "<")] {
        for direct in [true, false] {
            let client = ViewClient(), session = InputSession()
            client.supportsText = direct
            type(keys, session: session, client: client)
            let original = client.view.string
            let writes = client.insertCount, selections = client.selectionReadCount, texts = client.textReadCount
            type(punctuation, session: session, client: client)
            expect(client.view.string, original + punctuation, "literal punctuation \(keys) \(punctuation) \(direct)")
            expect(String(client.insertCount - writes), direct ? "1" : "2", "one app punctuation write \(keys) \(punctuation) \(direct)")
            if direct {
                let expectedReads = "0"
                expect(String(client.selectionReadCount - selections), expectedReads, "punctuation selection reads \(punctuation)")
                expect(String(client.textReadCount - texts), expectedReads, "punctuation text reads \(punctuation)")
            }
        }
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("r", session: session, client: client)
        // First insertion is provisional. The caret still matches but the app
        // changed the text, so there must be only one query of that same range.
        client.insert("X", replacing: NSRange(location: 0, length: 1))
        let reads = client.textReadCount
        type("sk", session: session, client: client)
        expect(client.view.string, "X나", "provisional external edit preserved")
        expect(String(client.textReadCount - reads), "2", "one range query per composition key")
    }
    // Reentrant IMK requests can arrive during a synchronous client query.
    // They must not clear or alter the composition that the outer key is using.
    for query in ["selection", "text", "marked"] {
        let client = ViewClient(), session = InputSession()
        client.supportsText = query != "marked"
        type("r", session: session, client: client)
        let callback = { session.commit(to: client) }
        switch query {
        case "selection": client.onSelectionRead = callback
        case "text": client.onTextRead = callback
        default: client.onMarkedRead = callback
        }
        type("k", session: session, client: client)
        expect(client.view.string, "가", "query callback cannot reset active composition \(query)")
        type("r", session: session, client: client)
        expect(client.view.string, "각", "typing continues after query callback \(query)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("r", session: session, client: client)
        client.onTextRead = {
            expect(String(session.input(keyCode: 1, modifiers: [], client: client)), "false", "nested key is not processed twice")
        }
        type("k", session: session, client: client)
        expect(client.view.string, "가", "nested key query preserves outer composition")
    }
    for direct in [true, false] {
        let client = ViewClient(), session = InputSession()
        client.supportsText = direct
        type("rkkt", session: session, client: client)
        client.view.unmarkText()
        client.view.string = "외부 수정"
        client.view.setSelectedRange(NSRange(location: 5, length: 0))
        let writes = client.insertCount
        session.commit(to: client)
        expect(client.view.string, "외부 수정", "finish cannot restore externally changed text \(direct)")
        expect(String(client.insertCount - writes), "0", "finish of changed document never writes \(direct)")
        type("sk", session: session, client: client)
        expect(client.view.string, "외부 수정나", "fresh typing after finishing changed document \(direct)")
    }
    for (before, next, appended, expected) in [
        ("r", "r", "ㄱ", "ㄱㄱ"), ("dks", "s", "ㄴ", "안ㄴ"),
        ("rkqt", "r", "ㄱ", "값ㄱ")
    ] {
        let client = ViewClient(), session = InputSession()
        client.insert("😀 ")
        type(before, session: session, client: client)
        let reads = client.textReadCount
        type(next, session: session, client: client)
        expect(client.view.string, "😀 " + expected, "append keeps committed prefix \(before)")
        expect(client.lastInsertedText, appended, "send only new suffix \(before)")
        expect(String(client.lastInsertionRange.location == NSNotFound), "true", "append uses current selection \(before)")
        expect(String(client.textReadCount - reads), "1", "append still checks prior text \(before)")
        if !session.input(keyCode: 51, modifiers: [], client: client) { client.view.deleteBackward(nil) }
        expect(client.view.string, "😀 " + String(expected.dropLast()), "Backspace after append \(before)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("dks", session: session, client: client)
        // The app moves its document between the read and the append. Using its
        // current selection plus one-time anchor resolution preserves that edit.
        client.beforeInsert = {
            client.view.string = "X 안"
            client.view.setSelectedRange(NSRange(location: 3, length: 0))
        }
        type("sk", session: session, client: client)
        expect(client.view.string, "X 안나", "resolve actual append position after app edit")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("r", session: session, client: client)
        type("k", session: session, client: client)
        expect(client.view.string, "가", "changed syllable still replaces")
        expect(String(client.lastInsertionRange.location), "0", "changed syllable uses explicit range")
        expect(client.lastInsertedText, "가", "changed syllable sends full replacement")
    }
}
