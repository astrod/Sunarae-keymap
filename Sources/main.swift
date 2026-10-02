import AppKit
import InputMethodKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Opening the running input-method app in Finder also opens its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ShortcutSettingsController.shared.show()
        return true
    }
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
if CommandLine.arguments.contains("--check-server") {
    print("InputMethodKit connection ready")
} else {
    ShortcutManager.shared.restore()
    withExtendedLifetime(server) { app.run() }
}
