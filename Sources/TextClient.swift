import AppKit

/// A small interface also exercised against a real NSTextView in the tests.
protocol TextClient: AnyObject {
    var identity: ObjectIdentifier { get }
    var supportsDocumentAccess: Bool { get }
    var selectedRange: NSRange { get }
    var markedRange: NSRange { get }
    func text(in range: NSRange) -> String?
    func insert(_ text: String, replacing range: NSRange)
    func mark(_ text: String)
    func remove(in range: NSRange)
}

extension TextClient {
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    func insert(_ text: String) {
        insert(text, replacing: NSRange(location: NSNotFound, length: 0))
    }
}

