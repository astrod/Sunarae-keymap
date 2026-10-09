import AppKit

// Advance only the recovery callbacks; do not sleep or pump the app event loop.
final class RecoveryClock {
    var actions: [() -> Void] = []
    var scheduled = 0
    func schedule(_ action: @escaping () -> Void) {
        scheduled += 1
        actions.append(action)
    }
    func runNext() {
        guard !actions.isEmpty else { return }
        actions.removeFirst()()
    }
    func drain() {
        var count = 0
        while !actions.isEmpty, count < 20 { count += 1; runNext() }
        expect(String(actions.isEmpty), "true", "recovery work is bounded")
    }
}

func runRecoveryChecks() {
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rjffh tjfrul ", session: session, client: client)
        client.unavailableTextReads = 1
        type("rkk", session: session, client: client)
        expect(client.view.string, "걸로 설계 까", "normal input and a single failed read stay immediate")
        expect(String(clock.scheduled), "0", "normal input schedules no delayed work")
    }
    for prefix in ["", "😀 "] {
        for (keys, expected) in [("rjffh", "걸로"), ("tjfrul", "설계"), ("tjfrP", "설계")] {
            for failedReads in [2, 3, 4, 6] {
                let clock = RecoveryClock()
                let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
                client.insert(prefix)
                type(String(keys.prefix(2)), session: session, client: client)
                let before = client.view.string, writes = client.insertCount
                client.unavailableTextReads = failedReads
                type(String(keys.dropFirst(2).prefix(1)), session: session, client: client)
                expect(client.view.string, before, "missing replies do not split the final consonant")
                expect(String(client.insertCount), String(writes), "no unchecked replacement")
                type(String(keys.dropFirst(3)), session: session, client: client)
                clock.drain()
                expect(client.view.string, prefix + expected, "recover \(keys) after \(failedReads) missing reads")
                expect(String(client.markCount), "0", "recovery keeps direct display")
                expect(String(client.view.hasMarkedText()), "false", "recovery leaves no marked range")
                expect(String(client.view.selectedRange().length), "0", "recovery leaves no selection")
            }
        }
    }
    // Recover the final key even if the user stops typing after it.
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 6
        type("f", session: session, client: client)
        clock.drain()
        expect(client.view.string, "걸", "last key recovers without another key")
        expect(String(clock.scheduled), "3", "no more than three delayed attempts")
    }
    // Missing caret replies are not evidence of actual cursor movement.
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.onSelectionRead = {
            client.staleSelection = NSRange(location: NSNotFound, length: 0)
            client.onSelectionRead = { client.staleSelection = NSRange(location: NSNotFound, length: 0) }
        }
        type("f", session: session, client: client)
        expect(client.view.string, "거", "unavailable carets defer the key")
        clock.drain()
        type("fh", session: session, client: client)
        expect(client.view.string, "걸로", "recover missing caret replies")
    }
    for boundary in ["Return", "Backspace", "Left", "shortcut", "commit", "client"] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 2
        type("f", session: session, client: client)
        switch boundary {
        case "Return":
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "original Return passes")
            client.view.insertNewline(nil)
        case "Backspace":
            expect(String(session.input(keyCode: 51, modifiers: [], client: client)), "true", "Backspace handles recovered final")
        case "Left":
            expect(String(session.input(keyCode: 123, modifiers: [], client: client)), "false", "original Left passes")
            client.view.setSelectedRange(NSRange(location: 0, length: 0))
        case "shortcut":
            expect(String(session.input(keyCode: 8, modifiers: .command, client: client)), "false", "original shortcut passes")
        case "client":
            let second = ViewClient()
            type("rk", session: session, client: second)
            expect(second.view.string, "가", "deferred keys cannot migrate to a new client")
        default: session.commit(to: client)
        }
        let expected = boundary == "Return" ? "걸\n" : boundary == "Backspace" ? "거" : "걸"
        expect(client.view.string, expected, "finish deferred key before \(boundary)")
        clock.drain()
        expect(client.view.string, expected, "stale callback cannot write after \(boundary)")
    }
    for change in ["caret", "selection", "text", "clear"] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 2
        type("f", session: session, client: client)
        switch change {
        case "caret": client.view.setSelectedRange(NSRange(location: 0, length: 0))
        case "selection": client.view.setSelectedRange(NSRange(location: 0, length: 1))
        case "text": client.view.string = "X"; client.view.setSelectedRange(NSRange(location: 1, length: 0))
        default: client.view.string = ""; client.view.setSelectedRange(NSRange(location: 0, length: 0))
        }
        let before = client.view.string, writes = client.insertCount
        clock.drain()
        expect(client.view.string, before, "changed document cancels the old deferred key: \(change)")
        expect(String(client.insertCount), String(writes), "no late insertion after \(change)")
        type("rk", session: session, client: client)
        let expected = change == "caret" ? "가거" : change == "text" ? "X가" : "가"
        expect(client.view.string, expected, "new input still reaches the current selection: \(change)")
    }
    for boundary in ["timeout", "Return", "commit"] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 100
        type("f", session: session, client: client)
        expect(client.view.string, "거", "persistent failure initially waits")
        switch boundary {
        case "Return":
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Return passes despite permanent failure")
            client.view.insertNewline(nil)
        case "commit": session.commit(to: client)
        default: break
        }
        clock.drain()
        expect(client.view.string, boundary == "Return" ? "거ㄹ\n" : "거ㄹ", "permanent failure keeps key without overwriting: \(boundary)")
        expect(String(clock.scheduled <= 3), "true", "permanent failure cannot wait indefinitely")
    }
    for change in ["caret during read", "same letter elsewhere", "new key before retry"] {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type(change == "same letter elsewhere" ? "rr" : "rj", session: session, client: client)
        client.unavailableTextReads = 2
        type(change == "same letter elsewhere" ? "k" : "f", session: session, client: client)
        switch change {
        case "caret during read":
            client.afterTextRead = { client.view.setSelectedRange(NSRange(location: 0, length: 0)) }
        case "same letter elsewhere": client.view.setSelectedRange(NSRange(location: 1, length: 0))
        default:
            client.view.string = "X"
            client.view.setSelectedRange(NSRange(location: 1, length: 0))
            type("sk", session: session, client: client)
        }
        clock.drain()
        let expected = change == "caret during read" ? "거" : change == "same letter elsewhere" ? "ㄱㄱ" : "X나"
        expect(client.view.string, expected, "cancel only old deferred input after \(change)")
    }
    do {
        let suite = "SunaraeTests.Recovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = InputSettings(defaults: defaults)
        settings.switchToABCOnEscape = true
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(settings: settings, scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 2
        type("f", session: session, client: client)
        client.onTextRead = {
            expect(String(session.input(keyCode: 15, modifiers: [], client: client)), "false", "switch-time key stays with ABC")
        }
        var switches = 0
        expect(String(session.input(keyCode: 53, modifiers: [], client: client, selectABC: {
            switches += 1
            expect(client.view.string, "걸", "deferred Hangul finishes before ABC switch")
            return true
        })), "false", "original Escape passes after recovery")
        clock.drain()
        expect(String(switches), "1", "recovery does not duplicate source switching")
        expect(client.view.string, "걸", "late callback cannot insert a switch-time key")
    }
    // Spaces and keys arriving inside a recovery query must retain order.
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 100
        type("ffh tjfrul ", session: session, client: client)
        client.unavailableTextReads = 0
        client.onTextRead = { type("rkk", session: session, client: client) }
        clock.drain()
        expect(client.view.string, "걸로 설계 까", "deferred and nested keys stay in order")
    }
    do {
        let clock = RecoveryClock()
        let client = ViewClient(), session = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session, client: client)
        client.unavailableTextReads = 2
        type("f", session: session, client: client)
        client.onTextRead = { clock.runNext() }
        type("fh", session: session, client: client)
        clock.drain()
        expect(client.view.string, "걸로", "timer reentry cannot process a key twice")
    }
    do {
        let clock = RecoveryClock()
        let client = ViewClient()
        var session: InputSession? = InputSession(scheduleRecovery: clock.schedule)
        type("rj", session: session!, client: client)
        client.unavailableTextReads = 2
        type("f", session: session!, client: client)
        session = nil
        clock.drain()
        expect(client.view.string, "거", "scheduled callback does not retain a closed session")
    }
}
