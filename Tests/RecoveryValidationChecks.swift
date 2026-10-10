import AppKit

private func staleSelections(_ ranges: [NSRange], client: ViewClient) {
    guard let first = ranges.first else { return }
    client.onSelectionRead = {
        client.staleSelection = first
        staleSelections(Array(ranges.dropFirst()), client: client)
    }
}

private func injectRecoveryMismatch(_ fault: String, client: ViewClient) {
    switch fault {
    case "caret":
        staleSelections(Array(repeating: NSRange(location: 0, length: 0), count: 2), client: client)
    case "selection":
        staleSelections(Array(repeating: NSRange(location: 0, length: 1), count: 2), client: client)
    case "text": client.staleText = "X"
    default:
        client.afterTextRead = { client.staleSelection = NSRange(location: 0, length: 0) }
    }
}

func runRecoveryValidationChecks() {
    let words = [("rj", "ffh", "걸로"), ("rk", "k", "까"), ("rk", "r", "각"),
                 ("rh", "k", "과"), ("du", "l", "예"), ("tj", "frul", "설계")]
    // The actual text/selection never changes. Only client replies are stale.
    // Check both a last key and an ordered queue, including forced recovery.
    for prefix in ["", "😀 "] {
        for (before, pending, expected) in words {
            for fault in ["caret", "selection", "text", "caret after read"] {
                for trigger in ["timer", "next key", "Return", "last attempt"] {
                    let clock = RecoveryClock()
                    let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
                    client.insert(prefix)
                    type(before, session: session, client: client)
                    client.unavailableTextReads = 100
                    type(pending, session: session, client: client)
                    if trigger == "last attempt" { clock.runNext(); clock.runNext() }
                    client.unavailableTextReads = 0
                    let unchanged = client.view.string
                    let caret = client.view.selectedRange()
                    injectRecoveryMismatch(fault, client: client)
                    expect(client.view.string, unchanged, "fault injection does not edit text")
                    expect(String(client.view.selectedRange() == caret), "true", "fault injection does not move caret")
                    switch trigger {
                    case "next key": type(" ", session: session, client: client)
                    case "Return":
                        expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Return passes once after confirmation")
                        client.view.insertNewline(nil)
                    default: break
                    }
                    clock.drain()
                    let suffix = trigger == "next key" ? " " : trigger == "Return" ? "\n" : ""
                    let label = "\(before + pending), \(fault), \(trigger), prefix=\(prefix)"
                    expect(client.view.string, prefix + expected + suffix, "keep consumed keys after stale replies: \(label)")
                    expect(String(client.markCount), "0", "confirmation keeps direct display: \(label)")
                    expect(String(client.view.hasMarkedText()), "false", "no marked range after confirmation: \(label)")
                    expect(String(client.view.selectedRange().length), "0", "no selected last letter: \(label)")
                    expect(String(clock.scheduled <= 3), "true", "confirmation has bounded delayed work: \(label)")
                }
            }
        }
    }
    // Every key in a deferred queue needs the same check, not only the first.
    for fault in ["caret", "selection", "text", "caret after read"] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 100
        type("ffh tjfrul rkk ", session: session, client: client)
        client.unavailableTextReads = 0
        client.beforeInsert = { injectRecoveryMismatch(fault, client: client) }
        clock.drain()
        expect(client.view.string, "걸로 설계 까 ", "recheck a later queued key: \(fault)")
    }
    // A mismatch followed by missing replies does not prove either state.
    // Keep the pending key until a readable check resolves the uncertainty.
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rk", session: session, client: client)
        client.unavailableTextReads = 2
        type("k", session: session, client: client)
        client.staleText = "X"
        client.afterTextRead = { client.unavailableTextReads = 2 }
        clock.runNext()
        expect(client.view.string, "가", "unconfirmed mismatch waits without a write")
        clock.drain()
        expect(client.view.string, "까", "missing confirmation does not lose the pending vowel")
    }
    // An unresolved mismatch must not fall back to inserting at a new selection
    // when the retry budget or an app-owned event ends the wait.
    for boundary in ["timeout", "Return", "commit"] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 2
        type("f", session: session, client: client)
        client.view.string = "X"
        client.view.setSelectedRange(NSRange(location: 1, length: 0))
        client.afterTextRead = { client.unavailableTextReads = 100 }
        let writes = client.insertCount
        clock.runNext()
        switch boundary {
        case "Return":
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Return passes despite unresolved mismatch")
            client.view.insertNewline(nil)
        case "commit": session.commit(to: client)
        default: break
        }
        clock.drain()
        expect(client.view.string, boundary == "Return" ? "X\n" : "X", "unresolved mismatch cannot write into changed text: \(boundary)")
        expect(String(client.insertCount), String(writes), "no fallback insertion after unresolved change: \(boundary)")
        client.unavailableTextReads = 0
        type("rk", session: session, client: client)
        expect(client.view.string, boundary == "Return" ? "X\n가" : "X가", "fresh keys still work after cancelled recovery: \(boundary)")
    }
    // A cursor move during the confirmation itself still blocks replacement.
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 2
        type("f", session: session, client: client)
        client.staleText = "X"
        client.afterTextRead = {
            client.afterTextRead = { client.view.setSelectedRange(NSRange(location: 0, length: 0)) }
        }
        let writes = client.insertCount
        clock.drain()
        expect(client.view.string, "거", "cursor move during confirmation cancels pending key")
        expect(String(client.insertCount), String(writes), "confirmation never overwrites after a cursor move")
    }
}
