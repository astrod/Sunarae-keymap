import Carbon
import Foundation

enum InputSource {
    static let abcID = "com.apple.keylayout.ABC"
    static let sunaraeID = "local.inputmethod.Dukkeobi"

    static func destination(from identifier: String) -> String {
        identifier == sunaraeID ? abcID : sunaraeID
    }

    static func toggle(beforeLeavingSunarae: () -> Void) -> Bool {
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return false }
        let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        guard !identifier.isEmpty else { return false }
        return select(destination(from: identifier), beforeSelection: {
            if identifier == sunaraeID { beforeLeavingSunarae() }
        })
    }

    static func selectABC() -> Bool {
        select(abcID)
    }

    private static func select(_ identifier: String, beforeSelection: () -> Void = {}) -> Bool {
        // Never enable a layout or change the input-source list on Escape.
        let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
        guard let result = TISCreateInputSourceList(filter, false),
              let sources = result.takeRetainedValue() as? [TISInputSource],
              let source = sources.first else {
            NSLog("Sunarae: requested input source is not enabled.")
            return false
        }
        // Requires the narrowly scoped com.apple.tsm.portname sandbox exception
        // to notify the focused editor, not just change the menu-bar source.
        beforeSelection()
        let status = TISSelectInputSource(source)
        if status != noErr {
            NSLog("Sunarae: could not select input source (status %d).", status)
        }
        return status == noErr
    }
}
