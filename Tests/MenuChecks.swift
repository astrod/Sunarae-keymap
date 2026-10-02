import AppKit
import InputMethodKit

@main struct MenuChecks {
    static func main() {
        _ = NSApplication.shared
        // This unbundled test executable has its own preference domain. Never
        // run these toggles under the installed input method's bundle identity.
        let domain = ProcessInfo.processInfo.processName
        precondition(Bundle.main.bundleIdentifier == nil && domain == "SunaraeMenuTests")
        let previous = UserDefaults.standard.persistentDomain(forName: domain)
        defer {
            if let previous { UserDefaults.standard.setPersistentDomain(previous, forName: domain) }
            else { UserDefaults.standard.removePersistentDomain(forName: domain) }
        }
        let server = IMKServer(name: "local.sunarae.menucheck.\(ProcessInfo.processInfo.processIdentifier)",
                               bundleIdentifier: "local.sunarae.MenuCheck")!
        let controller = InputController(server: server, delegate: nil, client: nil)!
        InputSettings.shared.switchToABCOnEscape = false
        let menu = controller.menu()!
        precondition(menu.items.count == 3)
        precondition(menu.items[2].title.contains("한영 전환 키 설정"))
        precondition(controller.responds(to: menu.items[2].action))
        let item = menu.items[0]
        precondition(item.state == .off && item.isEnabled)
        precondition(controller.responds(to: item.action))
        controller.doCommand(by: item.action, command: [:])
        precondition(InputSettings.shared.switchToABCOnEscape && controller.menu()!.items[0].state == .on)
        controller.doCommand(by: item.action, command: [:])
        precondition(!InputSettings.shared.switchToABCOnEscape && controller.menu()!.items[0].state == .off)
        print("IMK menu action and both check states passed")
    }
}
