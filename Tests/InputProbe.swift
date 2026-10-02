import AppKit
import WebKit
import Carbon

// An isolated test document. No global event taps, other-app document access,
// or network requests. Only this window's known sample input is recorded.
final class Trace {
    static let shared = Trace()
    let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("input-probe.jsonl")
    var number = 0
    var sample = "idle"
    func write(_ name: String, _ values: [String: Any] = [:]) {
        number += 1
        var row = values
        row["event"] = name; row["sequence"] = number; row["sample"] = sample
        row["time"] = ProcessInfo.processInfo.systemUptime
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd(); try? file.write(contentsOf: data + Data([10]))
    }
}
func rangeValue(_ range: NSRange) -> [String: Any] {
    ["location": range.location == NSNotFound ? -1 : range.location,
     "length": range.length == NSNotFound ? -1 : range.length]
}
func stringValue(_ value: Any) -> String {
    (value as? NSAttributedString)?.string ?? (value as? String ?? "")
}
final class ProbeTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        Trace.shared.write("native.keyDown", ["code": event.keyCode,
            "source": inputContext?.selectedKeyboardInputSource ?? "nil"])
        super.keyDown(with: event)
        Trace.shared.write("native.afterKeyDown", ["text": string,
            "marked": rangeValue(super.markedRange()), "selection": rangeValue(super.selectedRange())])
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        Trace.shared.write("native.insertText", ["text": stringValue(insertString), "range": rangeValue(replacementRange)])
        super.insertText(insertString, replacementRange: replacementRange)
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        Trace.shared.write("native.setMarkedText", ["text": stringValue(string), "range": rangeValue(replacementRange)])
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
    override func unmarkText() { Trace.shared.write("native.unmarkText"); super.unmarkText() }
    override func selectedRange() -> NSRange {
        let value = super.selectedRange()
        Trace.shared.write("native.selectedRange", rangeValue(value)); return value
    }
    override func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let result = super.attributedSubstring(forProposedRange: range, actualRange: actualRange)
        Trace.shared.write("native.substring", ["range": rangeValue(range), "text": result?.string ?? "<nil>"])
        return result
    }
    override func doCommand(by selector: Selector) {
        Trace.shared.write("native.command", ["selector": NSStringFromSelector(selector)])
        super.doCommand(by: selector)
    }
}
final class ProbeApp: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    let native = ProbeTextView(frame: .zero)
    var web: WKWebView!
    let status = NSTextField(labelWithString: "Select a source and type the fixed sample: djfuqek, then Return")
    var targetIsWeb = false
    var desiredSource: String?
    var previousSource: String?
    let vimMode = NSButton(checkboxWithTitle: "Vim mode", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        if let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            previousSource = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        }
        let menu = NSMenu()
        let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Input Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1060, height: 740),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sunarae Input Probe — isolated test document"
        let root = NSView(frame: window.contentView!.bounds); window.contentView = root
        let titles = ["Native: Apple", "Native: Sunarae", "Web: Apple", "Web: Sunarae", "Snapshot"]
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: index < 4 ? #selector(selectSource(_:)) : #selector(snapshot))
            button.tag = index
            button.frame = NSRect(x: 12 + index * 173, y: 690, width: 167, height: 32)
            root.addSubview(button)
        }
        status.frame = NSRect(x: 12, y: 650, width: 730, height: 32); root.addSubview(status)
        vimMode.frame = NSRect(x: 745, y: 650, width: 110, height: 32); root.addSubview(vimMode)
        let regression = NSButton(title: "Editor regression", target: self, action: #selector(editorRegression))
        regression.frame = NSRect(x: 860, y: 650, width: 180, height: 32); root.addSubview(regression)
        let deletion = NSButton(title: "Deletion API check", target: self, action: #selector(deletionRegression))
        deletion.frame = NSRect(x: 860, y: 616, width: 180, height: 30); root.addSubview(deletion)
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 470, width: 1030, height: 135))
        native.frame = scroll.bounds; native.isRichText = false
        native.font = .systemFont(ofSize: 25)
        native.isAutomaticTextReplacementEnabled = false
        native.isAutomaticSpellingCorrectionEnabled = false
        scroll.documentView = native; root.addSubview(scroll)
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "trace")
        web = WKWebView(frame: NSRect(x: 12, y: 12, width: 1030, height: 445), configuration: config)
        root.addSubview(web)
        if let index = Bundle.main.url(forResource: "index", withExtension: "html") {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else { web.loadHTMLString(Self.html, baseURL: nil) }
        window.makeKeyAndOrderFront(nil)
        Trace.shared.write("launch")
    }

    @objc func selectSource(_ button: NSButton) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        targetIsWeb = button.tag >= 2
        let id = button.tag % 2 == 0 ? "com.apple.inputmethod.Korean.2SetKorean" : "local.inputmethod.Sunarae"
        desiredSource = id
        Trace.shared.sample = "\(targetIsWeb ? "web" : "native")-\(button.tag % 2 == 0 ? "apple" : "sunarae")"
        if targetIsWeb {
            web.evaluateJavaScript("resetEditor(\(vimMode.state == .on ? "true" : "false"))") { [self] _, _ in
                window.makeFirstResponder(web)
                web.evaluateJavaScript("focusEditor()") { [self] _, _ in setSource(id) }
            }
        } else {
            native.inputContext?.discardMarkedText()
            native.string = "- "; native.setSelectedRange(NSRange(location: 2, length: 0))
            window.makeFirstResponder(native); setSource(id)
        }
    }
    func setSource(_ id: String) {
        // WKWebView's outer NSView has no input context. Use the window's
        // actual text responder through the public NSView API.
        let context = (window.firstResponder as? NSView)?.inputContext
        context?.activate()
        let available = context?.keyboardInputSources ?? []
        guard available.contains(id) else {
            status.stringValue = "Unavailable source: \(id). Available: \(available)"
            Trace.shared.write("source.unavailable", ["available": available]); return
        }
        context?.selectedKeyboardInputSource = id
        status.stringValue = "\(Trace.shared.sample): source = \(context?.selectedKeyboardInputSource ?? "nil")"
        Trace.shared.write("source.selected", ["source": context?.selectedKeyboardInputSource ?? "nil", "active": NSApp.isActive])
    }
    @objc func snapshot() {
        Trace.shared.write("native.snapshot", ["text": native.string,
            "source": native.inputContext?.selectedKeyboardInputSource ?? "nil"])
        web.evaluateJavaScript("JSON.stringify(probeSnapshot())") { value, error in
            Trace.shared.write("web.snapshot", ["result": value as? String ?? "nil", "error": error?.localizedDescription ?? ""])
        }
    }
    @objc func editorRegression() {
        Trace.shared.sample = "editor-regression"
        web.evaluateJavaScript("JSON.stringify(editorRegression())") { [self] value, error in
            status.stringValue = error?.localizedDescription ?? (value as? String ?? "No result")
            Trace.shared.write("editor.regression.result", ["result": value as? String ?? "nil", "error": error?.localizedDescription ?? ""])
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let object = message.body as? [String: Any] { Trace.shared.write("web.event", object) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if let previousSource, let context = (window.firstResponder as? NSView)?.inputContext,
           context.selectedKeyboardInputSource == desiredSource {
            context.selectedKeyboardInputSource = previousSource
        }
    }
    static let html = #"""
    <!doctype html><meta charset="utf-8"><style>
    body{font:15px system-ui}#editor{font-size:26px;min-height:100px;border:1px solid #aaa;padding:12px}
    #report{width:98%;height:220px;font:12px monospace}
    </style><p>Plain WebKit editor — no list handler yet. Sample: djfuqek then Return.</p>
    <div id="editor" contenteditable="true" spellcheck="false"></div><textarea id="report" readonly></textarea>
    <script>
    let records=[];const editor=document.getElementById('editor'),report=document.getElementById('report');
    function resetEditor(){editor.textContent='- ';records=[];report.value='';editor.focus();const r=document.createRange();r.selectNodeContents(editor);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r)}
    function focusEditor(){editor.focus()}function probeSnapshot(){return {text:editor.innerText,events:records}}
    for(const type of ['keydown','keyup','beforeinput','input','compositionstart','compositionupdate','compositionend']){
      editor.addEventListener(type,e=>{const row={type,key:e.key||'',keyCode:e.keyCode||0,isComposing:!!e.isComposing,inputType:e.inputType||'',data:e.data||'',text:editor.innerText,time:performance.now()};
      records.push(row);report.value=JSON.stringify(records,null,1);window.webkit.messageHandlers.trace.postMessage(row)})}
    resetEditor();
    </script>
    """#
}
@main struct ProbeMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ProbeApp(); app.delegate = delegate; app.run()
    }
}
