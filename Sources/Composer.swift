import Foundation
import CLibHangul

struct CompositionUpdate {
    let handled: Bool
    let committed: String
    let preedit: String
}

/// Sunarae rules live in the pinned libhangul keyboard. This wrapper owns only
/// the current syllable and snapshots for per-key undo, including vowel repeats.
final class Composer {
    private var context: OpaquePointer
    private var undo: [OpaquePointer] = []

    init() {
        guard let context = hangul_ic_new("2noshift") else {
            fatalError("Unable to allocate a composition context")
        }
        self.context = context
        hangul_ic_set_option(context, Int32(HANGUL_IC_OPTION_AUTO_REORDER), false)
        // The Sunarae table combines repeated final ㄱ/ㅅ, but has no rule
        // for repeated initial consonants. rr stays ㄱㄱ; rkk becomes 까.
        hangul_ic_set_option(context, Int32(HANGUL_IC_OPTION_COMBI_ON_DOUBLE_STROKE), true)
    }

    deinit {
        clearUndo()
        hangul_ic_delete(context)
    }

    var preedit: String { Self.text(hangul_ic_get_preedit_string(context)) }
    var isEmpty: Bool { hangul_ic_is_empty(context) }

    private static func text(_ pointer: UnsafePointer<UInt32>?) -> String {
        guard let pointer else { return "" }
        var result = String.UnicodeScalarView()
        var index = 0
        while pointer[index] != 0 {
            if let scalar = Unicode.Scalar(pointer[index]) { result.append(scalar) }
            index += 1
        }
        return String(result)
    }

    private func clearUndo() {
        for snapshot in undo { hangul_ic_delete(snapshot) }
        undo.removeAll(keepingCapacity: true)
    }

    func reset() {
        hangul_ic_reset(context)
        clearUndo()
    }

    func flush() -> String {
        let text = Self.text(hangul_ic_flush(context))
        clearUndo()
        return text
    }

    func backspace() -> Bool {
        if let snapshot = undo.popLast() {
            hangul_ic_delete(context)
            context = snapshot
            return true
        }
        return hangul_ic_backspace(context)
    }

    func input(_ key: Character) -> CompositionUpdate {
        guard let ascii = key.asciiValue, key.isASCIIHangulKey else {
            return CompositionUpdate(handled: false, committed: flush(), preedit: "")
        }
        guard let snapshot = sunarae_clone(context) else {
            fatalError("Unable to allocate an undo context")
        }
        let handled = hangul_ic_process(context, Int32(ascii))
        let committed = Self.text(hangul_ic_get_commit_string(context))
        if committed.isEmpty {
            undo.append(snapshot)
        } else {
            hangul_ic_delete(snapshot)
            clearUndo()
        }
        return CompositionUpdate(handled: handled, committed: committed, preedit: preedit)
    }
}
