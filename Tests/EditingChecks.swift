import AppKit

private final class UndoTextView: NSTextView {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

func runEditingChecks() {
    for prefix in ["", "- ", "😀 "] {
        for key in ["f", "r", "z", "t", "l"] {
            for count in [1, 5, 30] {
                let client = ViewClient(), session = InputSession()
                client.insert(prefix)
                let keys = String(repeating: key, count: count)
                type(keys, session: session, client: client)
                let original = compose(keys)
                expect(client.view.string, prefix + original, "repeat before deletion")
                for removed in 1...count {
                    if !session.input(keyCode: 51, modifiers: [], client: client) { client.view.deleteBackward(nil) }
                    expect(client.view.string, prefix + String(original.dropLast(removed)), "delete repeated jamo")
                }
                type("tlfg", session: session, client: client)
                expect(client.view.string, prefix + "싫", "new composition after repeated deletion")
            }
        }
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("rkk", session: session, client: client)
        for expected in ["가", "ㄱ", ""] {
            expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "true", "Backspace handles only composing jamo")
            expect(client.view.string, expected, "undo one composing key")
        }
        expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "false", "empty composition leaves Backspace to app")
        client.insert("기존 글자")
        type("rk", session: session, client: client)
        session.commit(to: client)
        expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "false", "committed character deletion belongs to app")
        expect(client.view.string, "기존 글자가", "IME does not delete committed text")
        client.view.deleteBackward(nil)
        expect(client.view.string, "기존 글자", "app deletes its own text")
    }
    // Real AppKit paste/undo commands on isolated NSTextViews. A named
    // pasteboard keeps fixed test text away from the user's general clipboard.
    do {
        let view = UndoTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        view.isRichText = false
        view.allowsUndo = true
        view.history.groupsByEvent = false
        let client = ViewClient(view: view), session = InputSession()
        func group(_ body: () -> Void) {
            view.breakUndoCoalescing()
            view.history.beginUndoGrouping()
            body()
            view.breakUndoCoalescing()
            view.history.endUndoGrouping()
        }
        let board = NSPasteboard(name: .init("local.sunarae.editing-test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("붙여넣기 😀", forType: .string)
        group {
            type("rkkt", session: session, client: client)
            expect(String(session.input(keyCode: 9, modifiers: .command, client: client)), "false", "paste shortcut passes through")
        }
        expect(client.view.string, "깟", "paste boundary finishes Sunarae once")
        group {
            expect(String(view.readSelection(from: board)), "true", "AppKit reads named pasteboard")
        }
        expect(view.string, "깟붙여넣기 😀", "AppKit paste after composition")
        expect(String(session.input(keyCode: 6, modifiers: .command, client: client)), "false", "undo shortcut passes through")
        view.history.undo()
        expect(view.string, "깟", "AppKit undo removes paste")
        expect(String(session.input(keyCode: 6, modifiers: [.command, .shift], client: client)), "false", "redo shortcut passes through")
        view.history.redo()
        expect(view.string, "깟붙여넣기 😀", "AppKit redo restores paste")
        group { type("sk", session: session, client: client); session.commit(to: client) }
        expect(view.string, "깟붙여넣기 😀나", "Korean resumes after undo redo and emoji")
        view.history.undo()
        expect(view.string, "깟붙여넣기 😀", "undo removes resumed Korean group")
        view.history.redo()
        expect(view.string, "깟붙여넣기 😀나", "redo restores resumed Korean group")
        group {
            _ = session.input(keyCode: 0, modifiers: .command, client: client)
            view.selectAll(nil)
            expect(String(view.readSelection(from: board)), "true", "paste replaces selection")
            type("rk", session: session, client: client)
            session.commit(to: client)
        }
        expect(view.string, "붙여넣기 😀가", "compose after paste replaces whole document")
        view.history.undo()
        expect(view.string, "깟붙여넣기 😀나", "undo selection replacement preserves previous text")
        view.history.redo()
        expect(view.string, "붙여넣기 😀가", "redo selection replacement")
    }
}
