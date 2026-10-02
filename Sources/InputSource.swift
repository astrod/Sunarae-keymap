import Carbon
import Foundation

enum InputSource {
    static let abcID = "com.apple.keylayout.ABC"

    static func selectABC() -> Bool {
        // Never enable a layout or change the input-source list on Escape.
        let filter = [kTISPropertyInputSourceID as String: abcID] as CFDictionary
        guard let result = TISCreateInputSourceList(filter, false),
              let sources = result.takeRetainedValue() as? [TISInputSource],
              let abc = sources.first else {
            NSLog("Sunarae: ABC is not enabled; keeping the current input source.")
            return false
        }
        // Requires the narrowly scoped com.apple.tsm.portname sandbox exception
        // to notify the focused editor, not just change the menu-bar source.
        let status = TISSelectInputSource(abc)
        if status != noErr {
            NSLog("Sunarae: could not select ABC (status %d).", status)
        }
        return status == noErr
    }
}
