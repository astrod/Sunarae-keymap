import AppKit

func runEscapeChecks() {
    let suite = "SunaraeTests.Escape.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = InputSettings(defaults: defaults)
    expect(String(settings.switchToABCOnEscape), "false", "Escape switching defaults to off")
    settings.switchToABCOnEscape = true
    let restored = InputSettings(defaults: UserDefaults(suiteName: suite)!)
    expect(String(restored.switchToABCOnEscape), "true", "Escape preference survives settings recreation")
    restored.switchToABCOnEscape = false
    expect(String(settings.switchToABCOnEscape), "false", "Escape preference updates across instances")

    for enabled in [false, true] {
        settings.switchToABCOnEscape = enabled
        for direct in [true, false] {
            for (name, code, flags) in [("Escape", UInt16(53), NSEvent.ModifierFlags()),
                                        ("Control-[", UInt16(33), .control)] {
                let client = ViewClient()
                client.supportsText = direct
                var switches = 0
                let session = InputSession(settings: settings)
                let selectABC = { () -> Bool in
                    switches += 1
                    expect(client.view.string, "까", "text is final before source switch")
                    expect(String(client.view.hasMarkedText()), "false", "no marked text before source switch")
                    expect(String(session.composer.isEmpty), "true", "local state ends before source switch")
                    // Model a synchronous deactivation and nested key event from IMK.
                    session.commit(to: client)
                    expect(String(session.input(keyCode: 15, modifiers: [], client: client)),
                           "false", "source switch cannot reenter key handling")
                    return true
                }
                type("rkk", session: session, client: client)
                let selections = client.selectionReadCount, texts = client.textReadCount
                let writes = client.insertCount
                let label = "\(name) enabled=\(enabled) direct=\(direct)"
                expect(String(session.input(keyCode: code, modifiers: flags, client: client, selectABC: selectABC)),
                       "false", "original key reaches editor \(label)")
                expect(String(switches), enabled ? "1" : "0", "switch count \(label)")
                expect(client.view.string, "까", "last syllable preserved \(label)")
                expect(String(client.view.hasMarkedText()), "false", "composition ended \(label)")
                expect(String(client.selectionReadCount - selections), "0", "no extra caret query \(label)")
                expect(String(client.textReadCount - texts), "0", "no extra text query \(label)")
                expect(String(client.insertCount - writes), direct ? "0" : "1", "no duplicate commit \(label)")
                if enabled {
                    expect(String(session.input(keyCode: 2, modifiers: [], client: client, sunaraeIsSelected: { false })),
                           "false", "queued D passes through after source selection \(label)")
                    expect(client.view.string, "까", "no stray Korean after source selection \(label)")
                }
                session.activate()
                type("k", session: session, client: client)
                expect(client.view.string, "까ㅏ", "next session starts fresh \(label)")
            }
        }
    }

    // Only bare Escape and Control-[ switch. Caps Lock does not alter them;
    // Shift/Option/Command combinations remain the application's shortcuts.
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
            let handled = session.input(keyCode: code, modifiers: flags, client: ViewClient(), selectABC: { switches += 1; return true })
            expect(String(handled), "false", "Escape combination passes through code=\(code) flags=\(mask)")
            expect(String(switches), expected ? "1" : "0", "Escape combination selection code=\(code) flags=\(mask)")
        }
    }
    for code: UInt16 in [15, 36, 49, 51, 79, 123] { // R, Enter, Space, Backspace, F18, Left
        var switches = 0
        let session = InputSession(settings: settings)
        _ = session.input(keyCode: code, modifiers: [], client: ViewClient(), selectABC: { switches += 1; return true })
        expect(String(switches), "0", "unrelated key never switches code=\(code)")
    }
    do {
        var switches = 0
        let session = InputSession(settings: settings)
        let client = ViewClient()
        settings.switchToABCOnEscape = false
        _ = session.input(keyCode: 53, modifiers: [], client: client, selectABC: { switches += 1; return true })
        settings.switchToABCOnEscape = true
        _ = session.input(keyCode: 53, modifiers: [], client: client, selectABC: { switches += 1; return true })
        expect(String(switches), "1", "existing session respects preference changes immediately")
    }
    do {
        let session = InputSession(settings: settings), client = ViewClient()
        type("rk", session: session, client: client)
        _ = session.input(keyCode: 53, modifiers: [], client: client, selectABC: { false })
        type("k", session: session, client: client)
        expect(client.view.string, "가ㅏ", "failed source selection leaves Korean typing usable")
    }
    do {
        let session = InputSession(settings: settings), client = ViewClient()
        _ = session.input(keyCode: 53, modifiers: [], client: client, selectABC: {
            session.activate()
            return true
        })
        type("rk", session: session, client: client)
        expect(client.view.string, "가", "reentrant activation can resume Korean")
    }
    do {
        let session = InputSession(settings: settings), client = ViewClient()
        _ = session.input(keyCode: 53, modifiers: [], client: client, selectABC: { true })
        _ = session.input(keyCode: 2, modifiers: [], client: client, sunaraeIsSelected: { false })
        expect(client.view.string, "", "pending source change does not compose queued keys")
        expect(String(session.input(keyCode: 15, modifiers: [], client: client, sunaraeIsSelected: { true })),
               "true", "source reselection resumes without activation callback")
        type("k", session: session, client: client)
        expect(client.view.string, "가", "Korean works after source reselection")
    }
    do {
        var sourceQueries = 0
        let session = InputSession(settings: settings), client = ViewClient()
        _ = session.input(keyCode: 15, modifiers: [], client: client, sunaraeIsSelected: { sourceQueries += 1; return true })
        expect(String(sourceQueries), "0", "normal typing never queries the input source")
    }
}
