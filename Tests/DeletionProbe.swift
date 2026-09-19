import AppKit
import WebKit

// Use the real WKWebView text responder, without injecting keyboard events.
// This exercises InputSession -> NSTextInputClient -> WebKit -> CodeMirror.
private final class WebDeletionClient: TextClient {
    let target: NSTextInputClient
    var calls: [[String: Any]] = []
    var document = "- "
    var caret = 2
    init(_ target: NSTextInputClient) { self.target = target }
    var supportsDocumentAccess: Bool { true }
    // WKWebView exposes selection asynchronously. The IMK proxy normally
    // bridges this; the fixture refreshes it from its own editor after each key.
    var selectedRange: NSRange { NSRange(location: caret, length: 0) }
    var markedRange: NSRange { target.markedRange() }
    func text(in range: NSRange) -> String? {
        guard range.location != NSNotFound, NSMaxRange(range) <= document.utf16.count else { return nil }
        return (document as NSString).substring(with: range)
    }
    func insert(_ text: String, replacing range: NSRange) {
        calls.append(["text": text, "range": rangeValue(range)])
        target.insertText(text, replacementRange: range)
    }
    func mark(_ text: String) {
        target.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    func remove(in range: NSRange) {
        target.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: range)
    }
}

extension ProbeApp {
    @objc func deletionRegression() {
        Task { @MainActor in
            Trace.shared.sample = "deletion-regression"
            var results: [[String: Any]] = []
            do {
                for useVim in [false, true] {
                    _ = try await web.evaluateJavaScript("resetEditor(\(useVim))")
                    window.makeFirstResponder(web)
                    _ = try await web.evaluateJavaScript("focusEditor()")
                    guard let target = window.firstResponder as? NSTextInputClient else {
                        throw NSError(domain: "DeletionProbe", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Web responder lacks NSTextInputClient"])
                    }
                    let client = WebDeletionClient(target), session = InputSession()
                    for index in 1...5 {
                        _ = session.input(keyCode: 3, modifiers: [], client: client)
                        let snapshot = try await deletionSnapshot()
                        client.document = snapshot["text"] as? String ?? ""
                        client.caret = snapshot["selection"] as? Int ?? 0
                        let expected = "- " + String(repeating: "ㄹ", count: index)
                        results.append(["name": "type \(index)", "vim": useVim, "expected": expected,
                                        "snapshot": snapshot, "passed": snapshot["text"] as? String == expected])
                    }
                    for count in stride(from: 4, through: 0, by: -1) {
                        let handled = session.input(keyCode: 51, modifiers: [], isRepeat: count < 4, client: client)
                        if !handled { target.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }
                        let snapshot = try await deletionSnapshot()
                        client.document = snapshot["text"] as? String ?? ""
                        client.caret = snapshot["selection"] as? Int ?? 0
                        let expected = "- " + String(repeating: "ㄹ", count: count)
                        results.append(["name": "delete to \(count)", "vim": useVim, "handled": handled,
                                        "expected": expected, "snapshot": snapshot,
                                        "passed": snapshot["text"] as? String == expected])
                    }
                    Trace.shared.write("deletion.client.calls", ["vim": useVim, "calls": client.calls])
                }
                let passed = results.allSatisfy { $0["passed"] as? Bool == true }
                status.stringValue = "Deletion: \(results.count) checks, \(passed ? "PASS" : "FAIL")"
                Trace.shared.write("deletion.regression.result", ["results": results, "passed": passed])
            } catch {
                status.stringValue = "Deletion: \(error.localizedDescription)"
                Trace.shared.write("deletion.regression.error", ["error": error.localizedDescription])
            }
        }
    }

    @MainActor private func deletionSnapshot() async throws -> [String: Any] {
        // Let the editor's DOM observer process the native text edit. This is
        // fixture pacing, not a product delay or a latency measurement.
        let value = try await web.callAsyncJavaScript(
            "await new Promise(resolve => setTimeout(resolve, 40)); return probeSnapshot();",
            arguments: [:], in: nil, contentWorld: .page)
        return value as? [String: Any] ?? [:]
    }
}
