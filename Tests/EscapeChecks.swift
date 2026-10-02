import AppKit

func runEscapeChecks() {
    let suite = "SunaraeTests.Escape.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = InputSettings(defaults: defaults)
    expect(String(settings.switchToABCOnEscape), "false", "Escape switching defaults to off")
    settings.switchToABCOnEscape = true
    let restored = InputSettings(defaults: UserDefaults(suiteName: suite)!)
    expect(String(restored.switchToABCOnEscape), "true", "Escape preference persists")
    restored.switchToABCOnEscape = false
    expect(String(settings.switchToABCOnEscape), "false", "Escape preference updates across instances")

    for enabled in [false, true] {
        settings.switchToABCOnEscape = enabled
        for direct in [true, false] {
            for succeeds in [false, true] {
                for (name, code, flags) in [("Escape", UInt16(53), NSEvent.ModifierFlags()),
                                            ("Control-[", UInt16(33), .control)] {
                    let client = ViewClient(), session = InputSession(settings: settings)
                    client.supportsText = direct
                    type("rkk", session: session, client: client)
                    var switches = 0
                    let selectABC = { () -> Bool in
                        switches += 1
                        expect(client.view.string, "까", "text is final before switching")
                        expect(String(client.view.hasMarkedText()), "false", "no marked text before switching")
                        expect(String(session.composer.isEmpty), "true", "local state ends before switching")
                        session.commit(to: client) // TIS may synchronously reenter IMK.
                        expect(String(session.input(keyCode: 15, modifiers: [], client: client)),
                               "false", "nested key is not processed twice")
                        return succeeds
                    }
                    let selections = client.selectionReadCount, texts = client.textReadCount
                    let writes = client.insertCount
                    let label = "\(name) enabled=\(enabled) direct=\(direct) succeeds=\(succeeds)"
                    expect(String(session.input(keyCode: code, modifiers: flags, client: client, selectABC: selectABC)),
                           "false", "original key reaches editor \(label)")
                    expect(String(switches), enabled ? "1" : "0", "switch count \(label)")
                    expect(client.view.string, "까", "last syllable preserved \(label)")
                    expect(String(client.view.hasMarkedText()), "false", "composition ended \(label)")
                    expect(String(client.selectionReadCount - selections), "0", "no extra caret query \(label)")
                    expect(String(client.textReadCount - texts), "0", "no extra text query \(label)")
                    expect(String(client.insertCount - writes), direct ? "0" : "1", "no duplicate commit \(label)")
                    // A reused session must not need an activation callback or
                    // a current-source query to accept Korean input again.
                    type("sk", session: session, client: client)
                    expect(client.view.string, "까나", "Korean resumes in the same session \(label)")
                }
            }
        }
    }

    settings.switchToABCOnEscape = true
    let modifierBits: [NSEvent.ModifierFlags] = [.shift, .control, .option, .command, .capsLock]
    for code: UInt16 in [53, 33] {
        for mask in 0..<32 {
            var flags: NSEvent.ModifierFlags = []
            for (bit, flag) in modifierBits.enumerated() where mask & (1 << bit) != 0 {
                flags.insert(flag)
            }
            let expected = (code == 53 && mask & 15 == 0) || (code == 33 && mask & 15 == 2)
            var switches = 0
            let session = InputSession(settings: settings)
            expect(String(session.input(keyCode: code, modifiers: flags, client: ViewClient(),
                selectABC: { switches += 1; return true })), "false", "shortcut reaches editor \(code) \(mask)")
            expect(String(switches), expected ? "1" : "0", "only exact exit shortcuts switch \(code) \(mask)")
        }
    }
    for code: UInt16 in [15, 36, 49, 51, 79, 123] {
        var switches = 0
        let session = InputSession(settings: settings)
        _ = session.input(keyCode: code, modifiers: [], client: ViewClient(), selectABC: { switches += 1; return true })
        expect(String(switches), "0", "unrelated key never switches \(code)")
    }
    do {
        let session = InputSession(settings: settings), client = ViewClient()
        var switches = 0
        for enabled in [false, true, false, true, false] {
            settings.switchToABCOnEscape = enabled
            type("rkk", session: session, client: client)
            _ = session.input(keyCode: 53, modifiers: [], client: client, selectABC: { switches += 1; return true })
        }
        expect(String(switches), "2", "existing session respects setting changes")
        expect(client.view.string, "까까까까까", "toggling after a switch cannot leave an English mode")
    }
}
