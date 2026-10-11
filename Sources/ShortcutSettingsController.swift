import AppKit

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
    private var candidate: KeyboardShortcut?
    private var recording = false
    private var monitor: Any?
    private var previousApp: NSRunningApplication?

    init(manager: ShortcutManager = .shared) {
        self.manager = manager
        let panel = ShortcutPanel(contentRect: NSRect(x: 0, y: 0, width: 550, height: 440),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "순아래 한영 전환 키"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let root = panel.contentView!
        let capsTitle = NSTextField(labelWithString: "Caps Lock으로 전환")
        capsTitle.font = .boldSystemFont(ofSize: 18)
        capsTitle.frame = NSRect(x: 24, y: 388, width: 500, height: 26)
        root.addSubview(capsTitle)
        let capsHelp = NSTextField(wrappingLabelWithString:
            "키보드 → 텍스트 입력 → 편집에서\n‘Caps Lock 키로 ABC 입력 소스 전환’을 켜세요.\n짧게 누르면 한영 전환, 길게 누르면 대문자 고정입니다.")
        capsHelp.frame = NSRect(x: 24, y: 318, width: 500, height: 60)
        root.addSubview(capsHelp)
        let capsSettings = NSButton(title: "키보드 설정 열기…", target: self,
                                    action: #selector(openKeyboardSettings))
        capsSettings.bezelStyle = .rounded
        capsSettings.frame = NSRect(x: 24, y: 276, width: 190, height: 32)
        root.addSubview(capsSettings)
        let title = NSTextField(labelWithString: "다른 키로 전환 (ABC ↔ 순아래)")
        title.font = .boldSystemFont(ofSize: 18)
        title.frame = NSRect(x: 24, y: 238, width: 500, height: 26)
        root.addSubview(title)
        let help = NSTextField(wrappingLabelWithString:
            "F1–F20 또는 Control·Option·Command와 다른 키의 조합을 지정하세요.\n이 키는 모든 앱에서 한영 전환에 쓰이며, 원래 단축키로 전달되지 않아요.")
        help.frame = NSRect(x: 24, y: 182, width: 500, height: 46)
        root.addSubview(help)
        value.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        value.frame = NSRect(x: 24, y: 134, width: 300, height: 30)
        root.addSubview(value)
        record.frame = NSRect(x: 356, y: 133, width: 170, height: 32)
        record.bezelStyle = .rounded
        record.target = self; record.action = #selector(beginRecording)
        root.addSubview(record)
        message.frame = NSRect(x: 24, y: 62, width: 500, height: 58)
        message.font = .systemFont(ofSize: 12)
        root.addSubview(message)
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
        // Temporarily release the old chord so it can be recorded again here.
        if let error = manager.suspend() {
            let alert = NSAlert(); alert.messageText = error; alert.runModal(); return
        }
        candidate = manager.savedShortcut
        value.stringValue = candidate?.displayName ?? "사용 안 함"
        message.stringValue = "설정은 ‘적용’을 눌러야 저장돼요. 다른 도구에서 같은 키를 쓰고 있다면 기존 설정을 해제해 주세요."
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
        recording = true
        record.title = "키를 눌러 주세요"
        message.stringValue = "원하는 키를 누르세요. Esc로 입력을 취소할 수 있어요. 수정키 하나만 누르는 방식은 지원하지 않아요."
    }

    private func endRecording() { recording = false; record.title = "키 입력하기" }

    @objc private func openKeyboardSettings() {
        endRecording()
        // macOS owns Caps Lock switching. Open its UI without changing system
        // preferences, registering Caps Lock, or adding a global key monitor.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard")!
        if !NSWorkspace.shared.open(url) {
            message.stringValue = "시스템 설정을 열지 못했어요. 직접 키보드 → 텍스트 입력 → 편집으로 이동해 주세요."
        }
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
        endRecording(); candidate = nil; value.stringValue = "사용 안 함"
        message.stringValue = "‘적용’을 누르면 순아래의 한영 전환 키를 해제해요. Esc 전환 설정은 유지해요."
    }

    @objc private func apply() {
        endRecording()
        if let error = manager.apply(candidate) { message.stringValue = error; return }
        close()
    }

    @objc private func cancel() { close() }

    func windowDidResignKey(_ notification: Notification) { endRecording() }

    func windowWillClose(_ notification: Notification) {
        endRecording()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        manager.restore()
        previousApp?.activate(options: [])
        previousApp = nil
    }
}
