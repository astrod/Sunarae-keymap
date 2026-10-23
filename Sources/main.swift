import AppKit
import InputMethodKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        InputSourceFocusRefresh.shared.cancel()
    }
    // Opening the running input-method app in Finder also opens its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ShortcutSettingsController.shared.show()
        return true
    }
}

// The uninstall script uses the installed bundle's settings and registration.
// Exit before creating an IMK server or claiming any shortcut.
// Keep the old argument for uninstall tools shipped before 0.8.0.
if CommandLine.arguments.contains("--disable-switch-key") || CommandLine.arguments.contains("--disable-caps-lock") {
    let settings = InputSettings.shared
    if let key = settings.mappedSwitchKey {
        do {
            _ = try SwitchKeyConfiguration.live().change(from: key, to: nil,
                ownsLoginItem: settings.switchKeyOwnsLoginItem)
            settings.toggleShortcut = nil
            settings.mappedSwitchKey = nil
            settings.switchKeyOwnsLoginItem = false
        } catch {
            fputs("전환 키 설정을 해제하지 못했어요: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    exit(0)
}

// A local diagnostic on the actual signed executable, with no user input.
if CommandLine.arguments.contains("--self-check") {
    let examples = ["rkk": "까", "emmt": "뜻", "rjjrr": "꺾", "dult": "옛", "ghafhdn": "홈로우", "dlqfur": "입력", "tlfg": "싫"]
    let compositionOK = examples.allSatisfy { keys, expected in
        let composer = Composer()
        var text = ""
        for key in keys { text += composer.input(key).committed }
        return text + composer.flush() == expected
    }
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var error = errno
    var connected: Int32 = -1
    if fd >= 0 {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        error = errno
        close(fd)
    }
    let blocked = connected == -1 && (error == EPERM || error == EACCES)
    print("composition_ok=\(compositionOK) network_blocked=\(blocked) errno=\(error)")
    exit(compositionOK && blocked ? 0 : 1)
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
guard let connection = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
      let identifier = Bundle.main.bundleIdentifier,
      let server = IMKServer(name: connection, bundleIdentifier: identifier) else {
    fputs("Sunarae could not start its input-method connection.\n", stderr)
    exit(1)
}
ShortcutManager.shared.restore()
let keyboardConnections = KeyboardConnectionObserver { ShortcutManager.shared.restoreMapping() }
withExtendedLifetime((server, keyboardConnections)) { app.run() }
