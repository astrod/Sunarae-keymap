import AppKit

let sunaraeExamples: [(String, String)] = [
    ("dkssudgktpdy", "안녕하세요"), ("tkfkaemf", "사람들"), ("qnfakstmfjdn", "불만스러우"),
    ("ghafhdn", "홈로우"), ("dlqfur", "입력"), ("gkrfur", "학력"), ("gkrry", "학교"),
    ("akfr", "맑"), ("dksg", "않"), ("djqt", "없"), ("dltt", "있"), ("tlfg", "싫"),
    ("rkk", "까"), ("ejj", "떠"), ("qkk", "빠"), ("tkk", "싸"), ("wkk", "짜"),
    ("emmt", "뜻"), ("rhhor", "꽥"), ("rjjrr", "꺾"), ("dult", "옛"),
    ("il", "ㅒ"), ("ul", "ㅖ"), ("ril", "걔"), ("rul", "계"),
    ("rO", "걔"), ("rP", "계"), ("RjR", "꺾"),
    ("rhk", "과"), ("rhl", "괴"), ("rnj", "궈"), ("rnl", "귀"), ("dml", "의"),
    ("rkkk", "까ㅏ"), ("Rkk", "까ㅏ"), ("akk", "마ㅏ"), ("kk", "ㅏㅏ"),
    ("rr", "ㄱㄱ"), ("tt", "ㅅㅅ"), ("rktk", "가사"), ("rktt", "갔"),
    ("rkrfk", "각라"), ("rkfrk", "갈가"), ("rkrrk", "각가"), ("rkttk", "갓사"),
    ("rkh", "가ㅗ"), ("rkJ", "가ㅓ"), ("rkU", "가ㅕ"), ("rkI", "가ㅑ"),
    ("rkL", "가ㅣ"), ("rkK", "까"), ("r,", "ㄱ,"), ("rkqt,", "값,"),
    ("r,,", "ㄱ,,"), ("r;", "ㄱ;"), ("r<", "ㄱ<"), ("r:", "ㄱ:")
]

private func checkSyllableAndUndo(_ keys: String, expected: String, label: String) {
    let composer = Composer()
    var states: [String] = []
    var committed = ""
    for key in keys {
        states.append(composer.preedit)
        committed += composer.input(key).committed
    }
    expect(committed + composer.preedit, expected, label)
    expect(committed, "", "one syllable remains editable \(keys)")
    // Compare with the actual state before each key. This also checks the
    // snapshot restores compound vowels/finals and repeated-vowel initials.
    for state in states.reversed() {
        expect(String(composer.backspace()), "true", "undo one key \(keys)")
        expect(composer.preedit, state, "restore previous syllable state \(keys)")
    }
    expect(String(composer.backspace()), "false", "nothing left to undo \(keys)")
    for key in keys { committed += composer.input(key).committed }
    expect(committed + composer.flush(), expected, "retype and flush \(keys)")
}

func runSunaraeChecks() {
    let initials = Array("rRseEfaqQtTdwWczxvg").map(String.init)
    let vowels = ["k", "o", "i", "O", "j", "p", "u", "P", "h", "hk", "ho", "hl", "y", "n", "nj", "np", "nl", "b", "m", "ml", "l"]
    let finals = ["", "r", "R", "rt", "s", "sw", "sg", "e", "f", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "a", "q", "qt", "t", "T", "d", "w", "c", "z", "x", "v", "g"]
    // Every modern syllable has both a normal two-set path and a Shift-free
    // Sunarae path. Expected Unicode comes from the Hangul syllable formula.
    for l in 0..<19 {
        for v in 0..<21 {
            for t in 0..<28 {
                let expected = String(Unicode.Scalar(0xac00 + (l * 21 + v) * 28 + t)!)
                let standard = initials[l] + vowels[v] + finals[t]
                checkSyllableAndUndo(standard, expected: expected, label: "standard syllable \(standard)")
                var vowel = vowels[v].replacingOccurrences(of: "O", with: "il").replacingOccurrences(of: "P", with: "ul")
                if initials[l] != initials[l].lowercased() { vowel = String(vowel.first!) + vowel }
                let final = finals[t].replacingOccurrences(of: "R", with: "rr").replacingOccurrences(of: "T", with: "tt")
                let keys = initials[l].lowercased() + vowel + final
                checkSyllableAndUndo(keys, expected: expected, label: "Sunarae syllable \(keys)")
            }
        }
    }
    // Standard ordered finals retain the first consonant and carry the second.
    for pair in ["rr", "rt", "sw", "sg", "fr", "fa", "fq", "ft", "fx", "fv", "fg", "qt", "tt"] {
        let retained = finals.firstIndex(of: String(pair.first!))!
        let carried = initials.firstIndex(of: String(pair.last!))!
        for v in 0..<21 {
            let expected = String(Unicode.Scalar(0xac00 + retained)!)
                + String(Unicode.Scalar(0xac00 + (carried * 21 + v) * 28)!)
            expect(compose("rk" + pair + vowels[v]), expected, "final boundary \(pair) \(vowels[v])")
        }
    }
    for (keys, states) in [
        ("rkk", ["가", "ㄱ", ""]), ("emmt", ["뜨", "드", "ㄷ", ""]),
        ("ril", ["갸", "ㄱ", ""]), ("rjjrr", ["꺽", "꺼", "거", "ㄱ", ""]),
        ("rhhor", ["꽤", "꼬", "고", "ㄱ", ""]), ("rktt", ["갓", "가", "ㄱ", ""])
    ] {
        for direct in [true, false] {
            let client = ViewClient(), session = InputSession()
            client.supportsText = direct
            type(keys, session: session, client: client)
            expect(client.view.string, compose(keys), "Sunarae client \(keys) \(direct)")
            for state in states {
                let handled = session.input(keyCode: 51, modifiers: [], client: client)
                expect(String(handled), "true", "Sunarae undo consumes key \(keys)")
                expect(client.view.string, state, "Sunarae undo state \(keys) \(direct)")
            }
            type("rkk", session: session, client: client)
            expect(client.view.string, "까", "Sunarae resumes after undo \(direct)")
            let writes = client.insertCount
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "Sunarae Enter reaches app")
            expect(String(client.insertCount - writes), direct ? "0" : "1", "Sunarae Enter writes \(direct)")
            if direct { expect(session.markedText, "", "Sunarae direct exposes no marked text") }
        }
    }
    // Caps Lock alone does not act like Shift, and normal key-repeat events
    // use the same deterministic Sunarae rules as separate key presses.
    do {
        let client = ViewClient(), session = InputSession()
        _ = session.input(keyCode: 15, modifiers: .capsLock, client: client)
        _ = session.input(keyCode: 40, modifiers: [], client: client)
        expect(client.view.string, "가", "Caps Lock preserves ordinary initial")
        _ = session.input(keyCode: 40, modifiers: [], client: client)
        expect(client.view.string, "까", "repeat event follows Sunarae")
        _ = session.input(keyCode: 40, modifiers: [], client: client)
        expect(client.view.string, "까ㅏ", "further repeat is ordinary vowel")
    }
}
