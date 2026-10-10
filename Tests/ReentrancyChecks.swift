import AppKit

func runReentrancyChecks() {
    for point in ["markedRange", "mark"] {
        for ending in ["frul", "frP", "frul tjfrP "] {
            let client = ViewClient(), session = InputSession()
            type("t", session: session, client: client)
            let callback = { type(ending, session: session, client: client) }
            if point == "markedRange" { client.onMarkedRead = callback }
            else { client.beforeMark = callback }
            type("j", session: session, client: client)
            expect(client.view.string, ending.contains(" ") ? "설계 설계 " : "설계", "ordered nested keys during \(point)")
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Return passes after nested keys")
        }
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("tjfr", session: session, client: client)
        client.beforeInsert = { type("l", session: session, client: client) }
        type("u", session: session, client: client)
        expect(client.view.string, "설계", "keys arriving during syllable commit keep their order")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("t", session: session, client: client)
        client.beforeMark = {
            type("f", session: session, client: client)
            client.beforeMark = { type("rul", session: session, client: client) }
        }
        type("j", session: session, client: client)
        expect(client.view.string, "설계", "new keys during queue drain follow earlier keys")
    }
    do {
        let first = ViewClient(), second = ViewClient(), session = InputSession()
        type("t", session: session, client: first)
        first.beforeMark = { type("frul", session: session, client: second) }
        type("j", session: session, client: first)
        expect(first.view.string, "서", "nested client switch preserves first text")
        expect(second.view.string, "ㄹ계", "queued keys retain their own client")
    }
    for point in ["markedRange", "mark", "insert"] {
        let client = ViewClient(), session = InputSession()
        type("r", session: session, client: client)
        let callback = { session.commit(to: client) }
        if point == "markedRange" { client.onMarkedRead = callback }
        else if point == "mark" { client.beforeMark = callback }
        else { client.beforeInsert = callback }
        type(point == "insert" ? "rk" : "kr", session: session, client: client)
        expect(client.view.string, point == "insert" ? "ㄱ가" : "각", "nested commit cannot reset active write: \(point)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rk", session: session, client: client)
        client.beforeInsert = { type("sk", session: session, client: client) }
        session.commit(to: client)
        expect(client.view.string, "가나", "keys arriving during commit survive")
        session.commit(to: client)
        expect(client.view.string, "가나", "queued letters commit once")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("t", session: session, client: client)
        client.onMarkedRead = {
            for flags: NSEvent.ModifierFlags in [.command, .control, .option] {
                expect(String(session.input(keyCode: 8, modifiers: flags, client: client)), "false", "nested shortcut stays with app")
            }
        }
        type("j", session: session, client: client)
        expect(client.view.string, "서", "shortcuts do not become Hangul")
    }
}
