import AppKit

func runDeliveryChecks() {
    // Keep the text view real; only its replies to the input method are faulty.
    for prefix in ["", "😀 "] {
        for fault in ["text", "caret", "missing caret"] {
            for (before, key, expected) in [
                ("r", "k", "가"), ("rk", "k", "까"), ("rk", "r", "각"),
                ("rh", "k", "과"), ("rkr", "t", "갃"), ("du", "l", "예"),
                ("rkr", "k", "가가"), ("dks", "s", "안ㄴ")
            ] {
                let client = ViewClient(), session = InputSession()
                client.insert(prefix)
                type(before, session: session, client: client)
                switch fault {
                case "text": client.unavailableTextReads = 1
                case "caret": client.staleSelection = NSRange(location: 0, length: 0)
                default: client.staleSelection = NSRange(location: NSNotFound, length: 0)
                }
                let label = "\(before)+\(key), \(fault), prefix=\(prefix)"
                type(key, session: session, client: client)
                expect(client.view.string, prefix + expected, "recover direct input \(label)")
                expect(String(client.markCount), "0", "recovery does not mark text \(label)")
                expect(String(client.view.hasMarkedText()), "false", "no marked range \(label)")
                expect(session.markedText, "", "no IME composition display \(label)")
                expect(String(client.view.selectedRange().length), "0", "no selected last letter \(label)")
                let reads = client.selectionReadCount + client.textReadCount + client.markedReadCount
                let writes = client.insertCount
                expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Enter passes after recovery \(label)")
                expect(String(client.insertCount - writes), "0", "Enter does not rewrite \(label)")
                expect(String(client.selectionReadCount + client.textReadCount + client.markedReadCount - reads), "0", "Enter does not query \(label)")
                client.view.insertNewline(nil)
                expect(client.view.string, prefix + expected + "\n", "app handles Enter once \(label)")
            }
        }
    }

    // Recovery is bounded. A readable, different letter is an external edit,
    // so do not keep querying until the old letter happens to appear again.
    for unavailableReads in [2, 100] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rk", session: session, client: client)
        client.unavailableTextReads = unavailableReads
        let reads = client.textReadCount
        type("k", session: session, client: client)
        expect(client.view.string, "가", "missing replies defer the key without changing the document")
        expect(String(client.textReadCount - reads), "2", "at most two substring attempts")
        clock.drain()
        expect(client.view.string, unavailableReads == 2 ? "까" : "가ㅏ", "recover a short failure and bound a permanent failure")
        expect(String(client.markCount), "0", "persistent failure does not switch display mode")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.view.string = "X"
        client.view.setSelectedRange(NSRange(location: 1, length: 0))
        let reads = client.textReadCount
        type("k", session: session, client: client)
        expect(client.view.string, "Xㅏ", "preserve a concrete text change")
        expect(String(client.textReadCount - reads), "1", "do not retry a concrete mismatch")
    }

    for change in ["caret", "selection", "text", "clear", "caret during retry"] {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.unavailableTextReads = 1
        client.onTextRead = {
            switch change {
            case "caret": client.view.setSelectedRange(NSRange(location: 0, length: 0))
            case "selection": client.view.setSelectedRange(NSRange(location: 0, length: 1))
            case "text":
                client.view.string = "X"
                client.view.setSelectedRange(NSRange(location: 1, length: 0))
            case "clear":
                client.view.string = ""
                client.view.setSelectedRange(NSRange(location: 0, length: 0))
            default:
                // The second read sees the old text, then the cursor moves
                // before that read returns. Its final caret check must fail.
                client.afterTextRead = { client.view.setSelectedRange(NSRange(location: 0, length: 0)) }
            }
        }
        type("k", session: session, client: client)
        let expected = change == "text" ? "Xㅏ" : ["clear", "selection"].contains(change) ? "ㅏ" : "ㅏ가"
        expect(client.view.string, expected, "do not replace after \(change)")
    }
    do {
        let first = ViewClient(), second = ViewClient(), session = InputSession()
        type("rk", session: session, client: first)
        second.insert("가")
        second.unavailableTextReads = 1
        type("k", session: session, client: second)
        expect(first.view.string, "가", "client change preserves old document")
        expect(second.view.string, "가ㅏ", "client change cannot resume old composition")
    }

    // Backspace uses the same check, including its extra calls into the client.
    for fault in ["text", "caret"] {
        let client = ViewClient(), session = InputSession()
        type("rkk", session: session, client: client)
        if fault == "text" { client.unavailableTextReads = 1 }
        else { client.staleSelection = NSRange(location: 0, length: 0) }
        expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "true", "Backspace recovers \(fault)")
        expect(client.view.string, "가", "Backspace restores prior key after \(fault)")
        expect(String(client.view.hasMarkedText()), "false", "Backspace leaves no marked text")
        type("r", session: session, client: client)
        expect(client.view.string, "각", "typing continues after recovered Backspace")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.unavailableTextReads = 1
        client.onTextRead = {
            client.onTextRead = { session.commit(to: client) }
        }
        type("k", session: session, client: client)
        expect(client.view.string, "까", "reentrant commit during retry does not reset composition")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        let caretReads = client.selectionReadCount, textReads = client.textReadCount
        type("k", session: session, client: client)
        expect(client.view.string, "까", "normal input remains unchanged")
        expect(String(client.selectionReadCount - caretReads), "1", "no extra caret query on success")
        expect(String(client.textReadCount - textReads), "1", "no extra text query on success")
    }
}
