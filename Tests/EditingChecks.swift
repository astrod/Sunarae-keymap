import AppKit

private final class UndoTextView: NSTextView {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
}

func runEditingChecks() {
    // Reproduce the observed WebKit ordering: the last native Backspace can
    // reach the editor after the next IMK insertion. Use a real NSTextView
    // and defer that native command, instead of making every edit synchronous.
    for count in [1, 5, 30, 257] {
        for prefix in ["", "- ", "😀 "] {
            let client = ViewClient(), session = InputSession()
            client.ignoreEmptyReplacement = true
            client.insert(prefix)
            type(String(repeating: "f", count: count), session: session, client: client)
            var pendingDelete = false
            for index in 1...count {
                if !session.input(keyCode: 51, modifiers: [], client: client) {
                    if index == count { pendingDelete = true }
                    else { client.view.deleteBackward(nil) }
                }
                expect(client.view.string, prefix + String(repeating: "ㄹ", count: count - index),
                       "ordered deletion \(index)/\(count) prefix=\(prefix)")
            }
            type("t", session: session, client: client)
            if pendingDelete { client.view.deleteBackward(nil) }
            type("lfg", session: session, client: client)
            expect(client.view.string, prefix + "싫", "queued Backspace cannot delete next initial \(count) \(prefix)")
            expect(session.markedText, "", "ordered deletion leaves no IME marked text")
            expect(String(client.view.hasMarkedText()), "false", "ordered deletion leaves no client marked text")
            let writes = client.insertCount
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Enter after ordered deletion passes through")
            expect(String(client.insertCount), String(writes), "Enter after ordered deletion does not write")
        }
    }
    // The IME must never use its retained text to erase an app's new content.
    for change in ["caret", "selection", "document", "client", "commit", "shortcut", "space"] {
        let client = ViewClient(), session = InputSession()
        type("fff", session: session, client: client)
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        var target = client
        switch change {
        case "caret": client.view.setSelectedRange(NSRange(location: 0, length: 0))
        case "selection": client.view.setSelectedRange(NSRange(location: 0, length: 2))
        case "document": client.view.string = "가나"; client.view.setSelectedRange(NSRange(location: 2, length: 0))
        case "client": target = ViewClient(); target.insert("ㄹㄹ")
        case "commit": session.commit(to: client)
        case "shortcut": _ = session.input(keyCode: 8, modifiers: .command, client: client)
        default: _ = session.input(keyCode: 49, modifiers: [], client: client); client.insert(" ")
        }
        let before = target.view.string
        expect(String(session.input(keyCode: 51, modifiers: [], client: target)), "false", "delete after \(change) belongs to app")
        expect(target.view.string, before, "retained text cannot erase after \(change)")
        type("rk", session: session, client: target)
        expect(String(target.view.string.contains("가")), "true", "typing resumes after \(change)")
    }
    do {
        let client = ViewClient(), session = InputSession()
        type("fff", session: session, client: client)
        _ = session.input(keyCode: 51, modifiers: [], client: client)
        // An earlier edit may leave the current caret and last jamo intact.
        client.insert("X", replacing: NSRange(location: 0, length: 1))
        client.view.setSelectedRange(NSRange(location: 2, length: 0))
        expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "true", "verified last jamo still deletes")
        expect(client.view.string, "X", "earlier app edit remains intact")
        expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "false", "mismatching earlier edit belongs to app")
        expect(client.view.string, "X", "IME never deletes mismatching retained text")
    }
    // Exercise the caller's normal Backspace when the IME passes the key on.
    // Some web editors ignore insertText("", replacementRange: ...).
    for direct in [true, false] {
        for ignoresEmpty in [true, false] {
            for prefix in ["", "- ", "😀 "] {
                for key in ["f", "r", "z", "t", "l"] {
                    for count in [1, 5, 30] {
                        let client = ViewClient(), session = InputSession()
                        client.supportsText = direct
                        client.ignoreEmptyReplacement = ignoresEmpty
                        client.insert(prefix)
                        let keys = String(repeating: key, count: count)
                        type(keys, session: session, client: client)
                        let original = compose(keys)
                        let label = "\(key)×\(count), direct=\(direct), ignoresEmpty=\(ignoresEmpty), prefix=\(prefix)"
                        expect(client.view.string, prefix + original, "repeat before delete \(label)")
                        for removed in 1...count {
                            if !session.input(keyCode: 51, modifiers: [], client: client) {
                                client.view.deleteBackward(nil)
                            }
                            expect(client.view.string, prefix + String(original.dropLast(removed)), "delete \(removed) \(label)")
                        }
                        type("rk", session: session, client: client)
                        expect(client.view.string, prefix + "가", "compose after deleting all jamo \(label)")
                    }
                }
            }
        }
    }
    for direct in [true, false] {
        let client = ViewClient(), session = InputSession()
        client.supportsText = direct
        client.ignoreEmptyReplacement = true
        type("rkr", session: session, client: client)
        for expected in ["가", "ㄱ", ""] {
            let handled = session.input(keyCode: 51, modifiers: [], client: client)
            if !handled { client.view.deleteBackward(nil) }
            expect(client.view.string, expected, "syllable deletion direct=\(direct)")
            expect(String(handled), "true", "owned syllable deletion stays in IME direct=\(direct)")
        }
    }

    // Real AppKit paste/undo commands on isolated NSTextViews. A named
    // pasteboard keeps fixed test text away from the user's general clipboard.
    for direct in [true, false] {
        let view = UndoTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        view.isRichText = false
        view.allowsUndo = true
        view.history.groupsByEvent = false
        let client = ViewClient(view: view), session = InputSession()
        client.supportsText = direct
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
            expect(String(session.input(keyCode: 9, modifiers: .command, client: client)), "false", "paste shortcut passes through \(direct)")
        }
        expect(client.view.string, "깟", "paste boundary finishes Sunarae once \(direct)")
        group {
            expect(String(view.readSelection(from: board)), "true", "AppKit reads named pasteboard \(direct)")
        }
        expect(view.string, "깟붙여넣기 😀", "AppKit paste after composition \(direct)")
        expect(String(session.input(keyCode: 6, modifiers: .command, client: client)), "false", "undo shortcut passes through \(direct)")
        view.history.undo()
        expect(view.string, "깟", "AppKit undo removes paste \(direct)")
        expect(String(session.input(keyCode: 6, modifiers: [.command, .shift], client: client)), "false", "redo shortcut passes through \(direct)")
        view.history.redo()
        expect(view.string, "깟붙여넣기 😀", "AppKit redo restores paste \(direct)")
        group { type("sk", session: session, client: client); session.commit(to: client) }
        expect(view.string, "깟붙여넣기 😀나", "Korean resumes after undo redo and emoji \(direct)")
        view.history.undo()
        expect(view.string, "깟붙여넣기 😀", "undo removes resumed Korean group \(direct)")
        view.history.redo()
        expect(view.string, "깟붙여넣기 😀나", "redo restores resumed Korean group \(direct)")
        group {
            _ = session.input(keyCode: 0, modifiers: .command, client: client)
            view.selectAll(nil)
            expect(String(view.readSelection(from: board)), "true", "paste replaces selection \(direct)")
            type("rk", session: session, client: client)
            session.commit(to: client)
        }
        expect(view.string, "붙여넣기 😀가", "compose after paste replaces whole document \(direct)")
        view.history.undo()
        expect(view.string, "깟붙여넣기 😀나", "undo selection replacement preserves previous text \(direct)")
        view.history.redo()
        expect(view.string, "붙여넣기 😀가", "redo selection replacement \(direct)")
        if direct {
            group { type("fff", session: session, client: client) }
            group {
                for _ in 0..<3 {
                    if !session.input(keyCode: 51, modifiers: [], client: client) { view.deleteBackward(nil) }
                }
            }
            expect(view.string, "붙여넣기 😀가", "ordered deletion removes only the new jamo")
            _ = session.input(keyCode: 6, modifiers: .command, client: client)
            view.history.undo()
            expect(view.string, "붙여넣기 😀가ㄹㄹㄹ", "undo restores ordered deletion")
            view.history.redo()
            expect(view.string, "붙여넣기 😀가", "redo reapplies ordered deletion")
        }
    }
}
