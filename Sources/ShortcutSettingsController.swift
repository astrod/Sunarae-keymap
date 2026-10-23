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
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let record = NSButton(title: "키 입력하기", target: nil, action: nil)
    private let focusRefresh = NSButton(checkboxWithTitle: "한영 전환 보완", target: nil, action: nil)
    private var candidate: KeyboardShortcut?
    private var mappedCandidate: SwitchKey?
    private var capture: ShortcutCapture?
    private var monitor: Any?
    private var previousApp: NSRunningApplication?

    init(manager: ShortcutManager = .shared) {
        self.manager = manager
        let panel = ShortcutPanel(contentRect: NSRect(x: 0, y: 0, width: 550, height: 540),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "순아래 한영 전환 키"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let root = panel.contentView!
        let title = NSTextField(labelWithString: "한영 전환 키 (ABC ↔ 순아래)")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 492, width: 500, height: 26)
        root.addSubview(title)
        let help = NSTextField(wrappingLabelWithString:
            "Caps Lock·오른쪽 Option·Command·Control을 단독으로 누르거나,\nF1–F20 또는 Control·Option·Command와 다른 키를 함께 누르세요.\n오른쪽 수정키는 다른 키 없이 눌렀다 놓으면 선택돼요.")
        help.frame = NSRect(x: 24, y: 420, width: 500, height: 62)
        root.addSubview(help)
        value.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        value.frame = NSRect(x: 24, y: 374, width: 325, height: 30)
        root.addSubview(value)
        record.frame = NSRect(x: 356, y: 373, width: 170, height: 32)
        record.bezelStyle = .rounded
        record.target = self; record.action = #selector(beginRecording)
        root.addSubview(record)
        detail.frame = NSRect(x: 24, y: 302, width: 500, height: 62)
        root.addSubview(detail)
        let login = NSButton(title: "로그인 항목 설정…", target: self, action: #selector(openLoginSettings))
        login.bezelStyle = .rounded
        login.frame = NSRect(x: 24, y: 260, width: 190, height: 32)
        root.addSubview(login)
        message.frame = NSRect(x: 24, y: 188, width: 500, height: 62)
        message.font = .systemFont(ofSize: 12)
        root.addSubview(message)
        focusRefresh.frame = NSRect(x: 24, y: 136, width: 500, height: 26)
        root.addSubview(focusRefresh)
        let focusHelp = NSTextField(wrappingLabelWithString:
            "한글 전환 때 순아래 앱을 잠깐 활성화한 뒤 원래 앱으로 돌아와요.\n영어 전환에는 이 처리를 시작하지 않아요.")
        focusHelp.frame = NSRect(x: 24, y: 78, width: 500, height: 50)
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
        InputSourceFocusRefresh.shared.prepareForUserActivation()
        if window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        candidate = manager.savedShortcut
        mappedCandidate = manager.mappedKey
        focusRefresh.state = manager.focusRefreshEnabled ? .on : .off
        updateChoice()
        message.stringValue = manager.errorMessage ?? (manager.loginNeedsApproval
            ? "현재 매핑은 사용할 수 있어요. 재부팅 뒤에도 쓰려면 ‘로그인 항목 설정’에서 순아래 실행을 허용해 주세요."
            : "설정은 ‘적용’을 눌러야 저장돼요. 다른 도구에서 같은 키를 쓰고 있다면 기존 설정을 해제해 주세요.")
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.setActivationPolicy(.accessory)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, self.capture != nil else { return event }
            self.receive(event)
            return nil
        }
    }

    private func updateChoice() {
        value.stringValue = mappedCandidate?.displayName ?? candidate?.displayName ?? "사용 안 함"
        if let key = mappedCandidate {
            detail.stringValue = "\(key.displayName)을 한영 전환 전용으로 써요. 이 키의 원래 기능과 조합은 사용할 수 없어요.\n로그인·키보드 재연결 때 다시 적용해요. 추가 개인정보 권한은 필요 없어요."
        } else {
            detail.stringValue = "지정한 단축키는 모든 앱에서 한영 전환에 쓰이며 원래 앱으로 전달되지 않아요.\n손쉬운 사용·입력 모니터링 권한은 필요 없어요."
        }
    }

    @objc private func beginRecording() {
        guard capture == nil else { return }
        if let error = manager.suspend() { message.stringValue = error; return }
        capture = ShortcutCapture(initialFlags: NSEvent.modifierFlags)
        record.title = "키를 눌러 주세요"
        message.stringValue = "현재 전환 키를 잠시 해제했어요. 원하는 키를 누르세요.\nEsc 또는 창 전환으로 취소하면 기존 키를 복원해요."
    }

    @discardableResult private func endRecording() -> String? {
        guard capture != nil || manager.recordingIsSuspended else { return nil }
        capture = nil; record.title = "키 입력하기"
        manager.restore()
        if let error = manager.errorMessage { message.stringValue = error }
        return manager.errorMessage
    }

    @objc private func openLoginSettings() {
        guard endRecording() == nil else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    private func receive(_ event: NSEvent) {
        guard let result = capture?.receive(event) else { return }
        switch result {
        case .cancel:
            if endRecording() == nil { message.stringValue = "키 입력을 취소하고 기존 전환 키를 복원했어요." }
            return
        case .rejected(let error): message.stringValue = error; return
        case .mapped(let key): mappedCandidate = key; candidate = .mappedF18
        case .shortcut(let shortcut): mappedCandidate = nil; candidate = shortcut
        }
        updateChoice()
        if endRecording() == nil {
            message.stringValue = "‘적용’을 누르면 \(value.stringValue)로 한영을 전환해요. 다른 도구의 같은 키 설정은 해제해 주세요."
        }
    }

    @objc private func disable() {
        guard endRecording() == nil else { return }
        candidate = nil; mappedCandidate = nil; updateChoice()
        message.stringValue = "‘적용’을 누르면 전환 키 매핑과 이 기능이 추가한 로그인 항목을 해제해요. Esc 전환 설정은 유지해요."
    }

    @objc private func apply() {
        guard endRecording() == nil else { return }
        if let error = manager.apply(candidate, mappedKey: mappedCandidate,
                                     focusRefreshEnabled: focusRefresh.state == .on) { message.stringValue = error; return }
        if manager.loginNeedsApproval {
            message.stringValue = "현재 매핑은 사용할 수 있어요. 재부팅 뒤에도 쓰려면 ‘로그인 항목 설정’에서 순아래 실행을 허용해 주세요."
            return
        }
        close()
    }

    @objc private func cancel() { if endRecording() == nil { close() } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { endRecording() == nil }
    func windowDidResignKey(_ notification: Notification) { endRecording() }
    func windowWillClose(_ notification: Notification) {
        endRecording()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        previousApp?.activate(options: [])
        previousApp = nil
    }
}
