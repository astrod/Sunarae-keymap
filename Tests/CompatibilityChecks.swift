import AppKit

// A client with no editable document API. The same marked path serves terminals
// and text editors, including clients that cannot report their marked range.
private final class BufferClient: TextClient {
    let reportsRange: Bool
    init(reportsRange: Bool) { self.reportsRange = reportsRange }
    var committed = ""
    var preedit = ""
    var markedRange: NSRange {
        reportsRange ? NSRange(location: 0, length: preedit.utf16.count) : NSRange(location: NSNotFound, length: 0)
    }
    func insert(_ text: String) { committed += text; preedit = "" }
    func mark(_ text: NSAttributedString) { preedit = text.string }
}

func runCompatibilityChecks() {
    for reportsRange in [true, false] {
        for (keys, expected) in [("tjfrul", "설계"), ("tjfrP", "설계"),
                                 ("rkk rkr rhk dul", "까 각 과 예"), ("rjffh", "걸로")] {
            let client = BufferClient(reportsRange: reportsRange), session = InputSession()
            type(keys, session: session, client: client)
            expect(client.committed + client.preedit, expected, "marked client range=\(reportsRange): \(keys)")
            expect(String(session.input(keyCode: 36, modifiers: [], client: client)), "false", "terminal retains Return")
            expect(client.committed, expected, "commit before Return")
            expect(client.preedit, "", "clear marked text")
            session.commit(to: client)
            expect(client.committed, expected, "never commit twice")
        }
    }
}
