import AppKit

func runReentrancyChecks() {
    for point in ["selection", "substring", "insert", "mark"] {
        for ending in ["frul", "frP"] {
            let client = ViewClient(), session = InputSession()
            client.supportsText = point != "mark"
            type("t", session: session, client: client)
            // While processing ㅓ, later ㄹ/ㄱ/ㅕ/ㅣ requests arrive through
            // the synchronous client call. They must not escape to the app.
            let callback = { type(ending, session: session, client: client) }
            switch point {
            case "selection": client.onSelectionRead = callback
            case "substring": client.onTextRead = callback
            case "insert": client.beforeInsert = callback
            default: client.beforeMark = callback
            }
            type("j", session: session, client: client)
            expect(client.view.string, "설계", "keep key order during \(point): \(ending)")
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Return passes after queued letters")
            expect(client.view.string, "설계", "queued letters commit once")
        }
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("t", session: session, client: client)
        client.onTextRead = {
            type("f", session: session, client: client)
            client.onTextRead = {
                type("rul", session: session, client: client)
                session.commit(to: client)
            }
        }
        type("j", session: session, client: client)
        expect(client.view.string, "설계", "new requests during queue drain stay in order")
        expect(String(client.markCount), "0", "queued letters preserve direct display")
        type(" ", session: session, client: client)
        expect(client.view.string, "설계 ", "plain Space follows queued letters")
    }
    for direct in [true, false] {
        let client = ViewClient(), session = InputSession()
        client.supportsText = direct
        type("t", session: session, client: client)
        let callback = { type("frul tjfrP ", session: session, client: client) }
        if direct { client.beforeInsert = callback }
        else { client.beforeMark = callback }
        type("j", session: session, client: client)
        expect(client.view.string, "설계 설계 ", "queued spaces cannot overtake queued Hangul direct=\(direct)")
        expect(String(session.composer.isEmpty), "true", "queued final Space ends composition")
        expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Return passes after queued spaces")
    }
    do {
        let first = ViewClient(), second = ViewClient(), session = InputSession()
        type("t", session: session, client: first)
        first.beforeInsert = { type("frul", session: session, client: second) }
        type("j", session: session, client: first)
        expect(first.view.string, "서", "queued client switch preserves first document")
        expect(second.view.string, "ㄹ계", "queued key retains its own client")
    }
    do {
        let client = ViewClient(), session = InputSession()
        client.supportsText = false
        type("rk", session: session, client: client)
        client.onMarkedRead = { type("sk", session: session, client: client) }
        session.commit(to: client)
        expect(client.view.string, "가나", "letters arriving during commit are not lost")
        session.commit(to: client)
        expect(client.view.string, "가나", "commit drains each queued letter once")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("t", session: session, client: client)
        client.onTextRead = {
            for flags: NSEvent.ModifierFlags in [.command, .control, .option] {
                expect(String(session.input(keyCode: 8, modifiers: flags, client: client)), "false", "nested shortcut stays with app")
            }
        }
        type("j", session: session, client: client)
        expect(client.view.string, "서", "nested shortcuts do not become Hangul")
    }
}
