import AppKit
import ServiceManagement

private final class ShortcutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ShortcutSettingsController: NSWindowController, NSWindowDelegate {
    static let shared = ShortcutSettingsController()
    private let manager: ShortcutManager
    private let value = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let record = NSButton(title: "키 입력하기", target: nil, action: nil)
    private let caps = NSButton(checkboxWithTitle: "Caps Lock으로 한영 전환", target: nil, action: nil)
    private let focusRefresh = NSButton(checkboxWithTitle: "한영 전환 보완", target: nil, action: nil)
    private var candidate: KeyboardShortcut?
    private var manualCandidate: KeyboardShortcut?
    private var recording = false
    private var monitor: Any?
    private var previousApp: NSRunningApplication?

    init(manager: ShortcutManager = .shared) {
        self.manager = manager
        let panel = ShortcutPanel(contentRect: NSRect(x: 0, y: 0, width: 550, height: 560),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "순아래 한영 전환 키"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let root = panel.contentView!
        caps.font = .boldSystemFont(ofSize: 18)
        caps.frame = NSRect(x: 24, y: 508, width: 500, height: 26)
        caps.target = self; caps.action = #selector(capsChanged)
        root.addSubview(caps)
        let capsHelp = NSTextField(wrappingLabelWithString:
            "Caps Lock을 F18로 바꾸고, 로그인할 때 순아래를 실행해 다시 적용해요.\n입력 모니터링 권한은 필요 없어요. 대문자 고정 기능은 사라져요.\n끄면 이 매핑을 해제하고 이전 한영 전환 키로 돌아가요.")
        capsHelp.frame = NSRect(x: 24, y: 438, width: 500, height: 60)
        root.addSubview(capsHelp)
        let capsSettings = NSButton(title: "로그인 항목 설정…", target: self,
                                    action: #selector(openLoginSettings))
        capsSettings.bezelStyle = .rounded
        capsSettings.frame = NSRect(x: 24, y: 396, width: 190, height: 32)
        root.addSubview(capsSettings)
        let title = NSTextField(labelWithString: "다른 키로 전환 (ABC ↔ 순아래)")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 358, width: 500, height: 26)
        root.addSubview(title)
        let help = NSTextField(wrappingLabelWithString:
            "F1–F20 또는 Control·Option·Command와 다른 키의 조합을 지정하세요.\n이 키는 모든 앱에서 한영 전환에 쓰이며, 원래 단축키로 전달되지 않아요.")
        help.frame = NSRect(x: 24, y: 302, width: 500, height: 46)
        root.addSubview(help)
        value.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        value.frame = NSRect(x: 24, y: 254, width: 300, height: 30)
        root.addSubview(value)
        record.frame = NSRect(x: 356, y: 253, width: 170, height: 32)
        record.bezelStyle = .rounded
        record.target = self; record.action = #selector(beginRecording)
        root.addSubview(record)
        message.frame = NSRect(x: 24, y: 182, width: 500, height: 58)
        message.font = .systemFont(ofSize: 12)
        root.addSubview(message)
        focusRefresh.frame = NSRect(x: 24, y: 126, width: 500, height: 26)
        root.addSubview(focusRefresh)
        let focusHelp = NSTextField(wrappingLabelWithString:
            "한글로 전환할 때 작은 패널로 입력 연결을 갱신해요.\n순아래 앱을 활성화하지 않으며, 영어 전환에는 적용하지 않아요.")
        focusHelp.frame = NSRect(x: 24, y: 68, width: 500, height: 50)
        root.addSubview(focusHelp)
        for (label, x, action) in [("사용 안 함", 24.0, #selector(disable)),
                                    ("취소", 346.0, #selector(cancel)), ("적용", 438.0, #selector(apply))] {
            let button = NSButton(title: label, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 18, width: 88, height: 32)
            root.addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        guard let window else { return }
        if window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        candidate = manager.savedShortcut
        manualCandidate = manager.capsLockEnabled ? manager.shortcutBeforeCapsLock : candidate
        caps.state = manager.capsLockEnabled ? .on : .off
        focusRefresh.state = manager.focusRefreshEnabled ? .on : .off
        record.isEnabled = caps.state == .off
        value.stringValue = candidate?.displayName ?? "사용 안 함"
        message.stringValue = manager.errorMessage ?? (manager.loginNeedsApproval
            ? "현재 매핑은 사용할 수 있어요. 재부팅 뒤에도 쓰려면 ‘로그인 항목 설정’에서 순아래 실행을 허용해 주세요."
            : "설정은 ‘적용’을 눌러야 저장돼요. 다른 도구에서 같은 키를 쓰고 있다면 기존 설정을 해제해 주세요.")
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.accessory)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.recording else { return event }
            self.capture(event)
            return nil
        }
    }

    @objc private func beginRecording() {
        guard caps.state == .off else { return }
        if let error = manager.suspend() { message.stringValue = error; return }
        recording = true
        record.title = "키를 눌러 주세요"
        message.stringValue = "원하는 키를 누르세요. Esc로 입력을 취소할 수 있어요. 수정키 하나만 누르는 방식은 지원하지 않아요."
    }

    private func endRecording() {
        let wasRecording = recording
        recording = false; record.title = "키 입력하기"
        if wasRecording { manager.restore() }
    }

    @objc private func openLoginSettings() {
        endRecording()
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func capsChanged() {
        endRecording()
        if caps.state == .on { manualCandidate = candidate; candidate = .capsLockF18 }
        else { candidate = manualCandidate }
        record.isEnabled = caps.state == .off
        value.stringValue = candidate?.displayName ?? "사용 안 함"
        message.stringValue = "‘적용’을 누르면 Caps Lock 매핑과 로그인 시 실행 설정을 함께 바꿔요. 다른 키 매핑은 유지해요."
    }

    private func capture(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let shortcut = KeyboardShortcut(event: event)
        if shortcut.keyCode == 53 && shortcut.modifiers == 0 { endRecording(); return }
        // AppKit synthesizes Fn for function/navigation keys. A real Fn chord
        // on a letter cannot be represented by RegisterEventHotKey.
        if event.modifierFlags.contains(.function),
           KeyboardShortcut.functionKeys[shortcut.keyCode] == nil,
           !(114...126).contains(shortcut.keyCode) {
            message.stringValue = "Fn 조합은 지원하지 않아요. Control·Option·Command 조합을 골라 주세요."
            return
        }
        if let error = shortcut.validationError { message.stringValue = error; return }
        candidate = shortcut
        value.stringValue = shortcut.displayName
        message.stringValue = "‘적용’을 누르면 \(shortcut.displayName)로 한영을 전환해요. 다른 도구의 같은 키 설정은 해제해 주세요."
        endRecording()
    }

    @objc private func disable() {
        endRecording(); caps.state = .off; record.isEnabled = true
        candidate = nil; manualCandidate = nil; value.stringValue = "사용 안 함"
        message.stringValue = "‘적용’을 누르면 순아래의 한영 전환 키를 해제해요. Esc 전환 설정은 유지해요."
    }

    @objc private func apply() {
        endRecording()
        if let error = manager.apply(candidate, capsLockEnabled: caps.state == .on,
                                     focusRefreshEnabled: focusRefresh.state == .on) { message.stringValue = error; return }
        if manager.loginNeedsApproval {
            message.stringValue = "현재 매핑은 사용할 수 있어요. 재부팅 뒤에도 쓰려면 ‘로그인 항목 설정’에서 순아래 실행을 허용해 주세요."
            return
        }
        close()
    }

    @objc private func cancel() { close() }

    func windowDidResignKey(_ notification: Notification) { endRecording() }

    func windowWillClose(_ notification: Notification) {
        endRecording()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        previousApp?.activate(options: [])
        previousApp = nil
    }
}
