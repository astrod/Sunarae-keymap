import AppKit
import Carbon

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        var flags: UInt32 = 0
        if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
        modifiers = flags
    }

    static let modifierMask = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    static let functionKeys: [UInt32: String] = [
        122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6", 98:"F7", 100:"F8",
        101:"F9", 109:"F10", 103:"F11", 111:"F12", 105:"F13", 107:"F14", 113:"F15",
        106:"F16", 64:"F17", 79:"F18", 80:"F19", 90:"F20"
    ]
    private static let names: [UInt32: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 10:"§",
        11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3",
        21:"4", 22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]",
        31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 36:"Return", 37:"L", 38:"J", 39:"'", 40:"K",
        41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 48:"Tab", 49:"Space", 50:"`",
        51:"Delete", 53:"Esc", 65:"숫자패드 .", 67:"숫자패드 *", 69:"숫자패드 +", 71:"Clear",
        75:"숫자패드 /", 76:"숫자패드 Enter", 78:"숫자패드 -", 81:"숫자패드 =",
        82:"숫자패드 0", 83:"숫자패드 1", 84:"숫자패드 2", 85:"숫자패드 3", 86:"숫자패드 4",
        87:"숫자패드 5", 88:"숫자패드 6", 89:"숫자패드 7", 91:"숫자패드 8", 92:"숫자패드 9",
        93:"¥", 94:"_", 95:"숫자패드 ,", 102:"英数", 104:"かな", 114:"Help", 115:"Home",
        116:"Page Up", 117:"Forward Delete", 119:"End", 121:"Page Down", 123:"←", 124:"→", 125:"↓", 126:"↑"
    ]

    var validationError: String? {
        guard modifiers & ~Self.modifierMask == 0,
              Self.names[keyCode] != nil || Self.functionKeys[keyCode] != nil else {
            return "이 키는 지원하지 않아요. 기능키 또는 수정키와 다른 키의 조합을 눌러 주세요."
        }
        if (keyCode == 53 && modifiers == 0) || (keyCode == 33 && modifiers == UInt32(controlKey)) {
            return "Esc와 Ctrl+[는 기존 ABC 전환 기능용이에요. 다른 키를 골라 주세요."
        }
        // Plain typing keys and Shift-only shortcuts are not reliable global
        // hotkeys. Function keys can be registered without a modifier.
        if Self.functionKeys[keyCode] == nil && modifiers & UInt32(cmdKey | controlKey | optionKey) == 0 {
            return "일반 키에는 Control·Option·Command 중 하나를 함께 눌러 주세요. F1–F20은 단독으로 쓸 수 있어요."
        }
        return nil
    }

    var displayName: String {
        var result = ""
        for (mask, symbol) in [(controlKey,"⌃"), (optionKey,"⌥"), (shiftKey,"⇧"), (cmdKey,"⌘")] {
            if modifiers & UInt32(mask) != 0 { result += symbol }
        }
        return result + (Self.functionKeys[keyCode] ?? Self.names[keyCode] ?? "지원하지 않는 키")
    }
}
