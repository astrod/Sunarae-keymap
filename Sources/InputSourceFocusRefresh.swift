import AppKit
import Carbon

struct FocusRefreshContext: Equatable {
    let sourceID: String?
    let applicationPID: Int32?
}

/// Keeps panel ordering and cleanup in one main-thread operation when AppKit
/// sends didBecomeKey synchronously. No nested run loop or delayed key replay.
final class FocusRefreshRunner {
    private struct Request {
        let id: Int
        let context: FocusRefreshContext
        var opening = true
        var becameKey = false
    }
    private let enabled: () -> Bool
    private let context: () -> FocusRefreshContext
    private let ownPID: Int32
    private let supportedSources: Set<String>
    private let show: () -> Bool
    private let hide: () -> Void
    private let schedule: (Double, @escaping () -> Void) -> Void
    private var nextID = 0
    private var request: Request?
    var isPending: Bool { request != nil }

    init(enabled: @escaping () -> Bool, context: @escaping () -> FocusRefreshContext,
         ownPID: Int32, supportedSources: Set<String>, show: @escaping () -> Bool,
         hide: @escaping () -> Void, schedule: @escaping (Double, @escaping () -> Void) -> Void) {
        self.enabled = enabled
        self.context = context
        self.ownPID = ownPID
        self.supportedSources = supportedSources
        self.show = show
        self.hide = hide
        self.schedule = schedule
    }

    func selected(_ identifier: String) {
        cancel()
        guard enabled(), supportedSources.contains(identifier) else { return }
        let initial = context()
        guard initial.sourceID == identifier, let pid = initial.applicationPID, pid != ownPID else { return }
        nextID += 1
        let id = nextID
        request = Request(id: id, context: initial)
        let shown = show()
        guard var pending = request, pending.id == id else {
            // A synchronous context change may cancel while AppKit is ordering.
            if request == nil { hide() }
            return
        }
        pending.opening = false
        request = pending
        guard shown, enabled(), context() == initial else { cancel(); return }
        if pending.becameKey {
            cancel()
        } else {
            schedule(0.2) { [weak self] in
                guard let self, self.request?.id == id else { return }
                self.cancel()
            }
        }
    }

    func panelBecameKey() {
        guard var pending = request else { return }
        pending.becameKey = true
        request = pending
        // makeKeyAndOrderFront can order the window *after* its callback.
        // The caller closes it as soon as show() returns in that case.
        if !pending.opening { cancel() }
    }

    func contextChanged() {
        guard let pending = request else { return }
        if !enabled() || context() != pending.context { cancel() }
    }

    func cancel() {
        guard request != nil else { return }
        request = nil
        hide()
    }
}

private final class InputFocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// This path deliberately never activates Sunarae or another application.
/// The separate app-activation experiment is not part of the input method.
final class InputSourceFocusRefresh: NSObject, NSWindowDelegate {
    static let shared = InputSourceFocusRefresh()
    private var panel: InputFocusPanel?
    private var applicationObserver: NSObjectProtocol?
    private var sourceObserver: NSObjectProtocol?
    private lazy var runner = FocusRefreshRunner(
        enabled: { InputSettings.shared.refreshFocusOnInputSwitch },
        context: {
            FocusRefreshContext(sourceID: InputSource.currentIdentifier(),
                                applicationPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        },
        ownPID: ProcessInfo.processInfo.processIdentifier,
        supportedSources: [InputSource.sunaraeID, InputSource.abcID],
        show: { [weak self] in self?.showPanel() ?? false },
        hide: { [weak self] in self?.panel?.orderOut(nil) },
        schedule: { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    )

    func selected(_ identifier: String) {
        precondition(Thread.isMainThread)
        runner.selected(identifier)
    }

    func cancel() {
        precondition(Thread.isMainThread)
        runner.cancel()
    }

    private func showPanel() -> Bool {
        if panel == nil {
            // Background-only input methods must allow windows; accessory policy
            // does not add a Dock icon or activate the application.
            if NSApp.activationPolicy() == .prohibited,
               !NSApp.setActivationPolicy(.accessory) { return false }
            let window = InputFocusPanel(
                contentRect: NSRect(x: -100, y: -100, width: 1, height: 1),
                styleMask: [.borderless, .utilityWindow, .nonactivatingPanel],
                backing: .buffered, defer: false)
            window.alphaValue = 0
            window.isOpaque = false
            window.hasShadow = false
            window.animationBehavior = .none
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            window.delegate = self
            panel = window
            applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.runner.contextChanged() }
            sourceObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main
            ) { [weak self] _ in self?.runner.contextChanged() }
        }
        panel?.makeKeyAndOrderFront(nil)
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === panel else { return }
        runner.panelBecameKey()
    }
}
