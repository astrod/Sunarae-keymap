import AppKit
import Carbon

struct FocusRefreshContext: Equatable {
    let sourceID: String?
    let applicationPID: Int32?
}

/// Briefly makes a panel key without activating or restoring an application.
/// System actions are injected so lifecycle checks never change real focus.
final class FocusRefreshRunner {
    private enum Phase { case queued, opening, waiting }
    private struct Request {
        let id: Int
        let context: FocusRefreshContext
        var phase = Phase.queued
        var becameKey = false
    }
    private let enabled: () -> Bool
    private let context: () -> FocusRefreshContext
    private let ownPID: Int32
    private let refreshSource: String
    private let show: () -> Bool
    private let hide: () -> Void
    private let schedule: (Double, @escaping () -> Void) -> Void
    private var nextID = 0
    private var request: Request?
    private var isShowingPanel = false
    var isPending: Bool { request != nil }

    init(enabled: @escaping () -> Bool, context: @escaping () -> FocusRefreshContext,
         ownPID: Int32, refreshSource: String, show: @escaping () -> Bool,
         hide: @escaping () -> Void, schedule: @escaping (Double, @escaping () -> Void) -> Void) {
        self.enabled = enabled
        self.context = context
        self.ownPID = ownPID
        self.refreshSource = refreshSource
        self.show = show
        self.hide = hide
        self.schedule = schedule
    }

    func selected(_ identifier: String) {
        cancel()
        let initial = context()
        guard enabled(), identifier == refreshSource, initial.sourceID == identifier,
              let pid = initial.applicationPID, pid != ownPID else { return }
        nextID += 1
        let id = nextID
        request = Request(id: id, context: initial)
        if isShowingPanel {
            // A selection inside AppKit's ordering callback must not nest another
            // ordering operation on the same panel. Finish the old one first.
            schedule(0) { [weak self] in self?.begin(id) }
        } else {
            begin(id)
        }
    }

    private func begin(_ id: Int) {
        guard var pending = request, pending.id == id, pending.phase == .queued else { return }
        guard enabled(), context() == pending.context else { cancel(); return }
        pending.phase = .opening
        request = pending
        isShowingPanel = true
        let shown = show()
        isShowingPanel = false
        guard var current = request, current.id == id else {
            // AppKit can order the panel after a synchronous key/cancel callback.
            // Any newer request is still queued, so this only closes the old one.
            hide()
            return
        }
        current.phase = .waiting
        request = current
        guard shown, enabled(), context() == current.context else { cancel(); return }
        if current.becameKey {
            cancel()
        } else {
            // Cleanup only: normal completion closes on the key-window event.
            schedule(0.2) { [weak self] in
                guard let self, self.request?.id == id else { return }
                self.cancel()
            }
        }
    }

    func panelBecameKey() {
        guard var pending = request, pending.phase != .queued else { return }
        pending.becameKey = true
        request = pending
        if pending.phase == .waiting { cancel() }
    }

    func panelResignedKey() {
        guard let pending = request, pending.phase != .queued else { return }
        cancel()
    }

    func contextChanged() {
        guard let pending = request else { return }
        if !enabled() || context() != pending.context { cancel() }
    }

    func cancel() {
        guard let pending = request else { return }
        request = nil
        if pending.phase != .queued && !isShowingPanel { hide() }
    }
}

private final class InputFocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Refreshes key-window focus after Korean selection. Never activates an app,
/// reselects a source, hides a cursor, or replays a key.
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
        refreshSource: InputSource.sunaraeID,
        show: { [weak self] in self?.showPanel() ?? false },
        hide: { [weak self] in self?.panel?.orderOut(nil) },
        schedule: { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    )

    private override init() {
        super.init()
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.runner.contextChanged() }
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // TIS can notify inside select(); let selected() record the new source.
            DispatchQueue.main.async { self?.runner.contextChanged() }
        }
    }

    func selected(_ identifier: String) {
        precondition(Thread.isMainThread)
        runner.selected(identifier)
    }

    func cancel() {
        precondition(Thread.isMainThread)
        runner.cancel()
    }

    private func showPanel() -> Bool {
        if NSApp.activationPolicy() == .prohibited,
           !NSApp.setActivationPolicy(.accessory) { return false }
        if panel == nil {
            let window = InputFocusPanel(
                contentRect: NSRect(x: -100, y: -100, width: 1, height: 1),
                styleMask: [.borderless, .utilityWindow, .nonactivatingPanel],
                backing: .buffered, defer: false)
            window.alphaValue = 0
            window.backgroundColor = .clear
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
        }
        panel?.makeKeyAndOrderFront(nil)
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === panel else { return }
        runner.panelBecameKey()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as AnyObject?) === panel else { return }
        runner.panelResignedKey()
    }
}
