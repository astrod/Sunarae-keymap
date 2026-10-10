import Foundation

/// A small interface also exercised against a real NSTextView in the tests.
protocol TextClient: AnyObject {
    var identity: ObjectIdentifier { get }
    var markedRange: NSRange { get }
    func insert(_ text: String)
    func mark(_ text: NSAttributedString)
}

extension TextClient {
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    var hasMarkedText: Bool {
        let range = markedRange
        return range.location != NSNotFound && range.length > 0
    }
}

