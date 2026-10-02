import Foundation

extension Character {
    var isASCIIHangulKey: Bool {
        guard let value = asciiValue else { return false }
        return (65...90).contains(value) || (97...122).contains(value)
    }
}

/// Converts physical keys to the standard two-set QWERTY positions.
enum KeyMap {
    // macOS virtual key codes denote positions for built-in, USB and Bluetooth
    // keyboards alike. Shift is intentional; Caps Lock alone does not make jamo tense.
    static let positions: [UInt16: Character] = [
        0:"a", 1:"s", 2:"d", 3:"f", 4:"h", 5:"g", 6:"z", 7:"x", 8:"c", 9:"v",
        11:"b", 12:"q", 13:"w", 14:"e", 15:"r", 16:"y", 17:"t", 31:"o", 32:"u",
        34:"i", 35:"p", 37:"l", 38:"j", 40:"k", 41:";", 43:",", 45:"n", 46:"m"
    ]

    static func ascii(keyCode: UInt16, shifted: Bool) -> Character? {
        guard let key = positions[keyCode] else { return nil }
        if key == ";" { return shifted ? ":" : ";" }
        if key == "," { return shifted ? "<" : "," }
        return shifted ? Character(String(key).uppercased()) : key
    }
}
