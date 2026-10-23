import AppKit
import Carbon

struct FocusRefreshContext: Equatable {
    let sourceID: String?
    let applicationPID: Int32?
}

/// Owns the app round trip. All system actions are injected for tests.
final class FocusRefreshRunner {
    private enum Phase { case queued, entering, returning }
    private struct Request {
        let id: Int
        let originalPID: Int32
        var sourceID: String
        var phase = Phase.queued
        var activated = false
    }
    private let enabled: () -> Bool
    private let context: () -> FocusRefreshContext
    private let ownPID: Int32
    private let supportedSources: Set<String>
    private let enter: () -> Bool
    private let restore: (Int32) -> Bool
    private let hide: () -> Void
    private let schedule: (Double, @escaping () -> Void) -> Void
    private var nextID = 0
    private var request: Request?
    var isPending: Bool { request != nil }

    init(enabled: @escaping () -> Bool, context: @escaping () -> FocusRefreshContext,
         ownPID: Int32, supportedSources: Set<String>, enter: @escaping () -> Bool,
         restore: @escaping (Int32) -> Bool, hide: @escaping () -> Void,
         schedule: @escaping (Double, @escaping () -> Void) -> Void) {
        self.enabled = enabled
        self.context = context
        self.ownPID = ownPID
        self.supportedSources = supportedSources
        self.enter = enter
        self.restore = restore
        self.hide = hide
        self.schedule = schedule
    }

    func selected(_ identifier: String) {
        let current = context()
        guard enabled(), supportedSources.contains(identifier), current.sourceID == identifier else {
            cancel()
            return
        }
        if var pending = request, current.applicationPID == ownPID, pending.phase != .queued {
            // A second shortcut while we are away still belongs to the original app.
            pending.sourceID = identifier
            request = pending
            return
        }
        cancel()
        guard let pid = current.applicationPID, pid != ownPID else { return }
        nextID += 1
        let id = nextID
        request = Request(id: id, originalPID: pid, sourceID: identifier)
        // Return the current hotkey/Escape event before changing app activation.
        schedule(0) { [weak self] in self?.begin(id) }
    }

    private func begin(_ id: Int) {
        guard var pending = request, pending.id == id, pending.phase == .queued else { return }
        let current = context()
        guard enabled(), current.sourceID == pending.sourceID,
              current.applicationPID == pending.originalPID else { finish(id); return }
        pending.phase = .entering
        request = pending
        schedule(0.7) { [weak self] in
            guard let self, let current = self.request, current.id == id, current.phase == .entering else { return }
            if self.context().applicationPID == self.ownPID { self.returnToOriginal(id) }
            else { self.finish(id) }
        }
        let entered = enter()
        guard request?.id == id else {
            // AppKit may finish ordering the panel after a reentrant cancellation.
            hide()
            return
        }
        if !entered { cancel() }
    }

    func observedActivation(pid: Int32) {
        guard var pending = request else { return }
        if pid == ownPID {
            guard pending.phase == .entering, !pending.activated else { return }
            pending.activated = true
            request = pending
            // Same as the successful Y trial: no fixed dwell after activation.
            schedule(0) { [weak self] in self?.returnToOriginal(pending.id) }
        } else if pid == pending.originalPID {
            if pending.phase == .returning || pending.activated { finish(pending.id) }
        } else {
            // A user-selected third app wins. Never pull it back to the old app.
            finish(pending.id)
        }
    }

    func sourceChanged() {
        guard let pending = request else { return }
        if !enabled() || context().sourceID != pending.sourceID { cancel() }
    }

    private func returnToOriginal(_ id: Int) {
        guard var pending = request, pending.id == id, pending.phase == .entering else { return }
        guard context().applicationPID == ownPID else { finish(id); return }
        pending.phase = .returning
        request = pending
        let accepted = restore(pending.originalPID)
        guard request?.id == id else { return }
        guard accepted else { finish(id); return }
        schedule(0.7) { [weak self] in
            guard let self, self.request?.id == id, self.request?.phase == .returning else { return }
            self.finish(id)
        }
    }

    private func finish(_ id: Int) {
        guard let pending = request, pending.id == id else { return }
        request = nil
        if pending.phase != .queued { hide() }
    }

    func cancel() {
        guard let pending = request else { return }
        request = nil
        if pending.phase == .entering, context().applicationPID == ownPID {
            _ = restore(pending.originalPID)
        }
        if pending.phase != .queued { hide() }
    }
}

private final class InputFocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Activates this app through a tiny panel, then returns to the original app.
/// No event tap, key replay, input-source reselection or diagnostic log is used.
final class InputSourceFocusRefresh {
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
        enter: { [weak self] in self?.activatePanel() ?? false },
        restore: { pid in
            guard let original = NSRunningApplication(processIdentifier: pid), !original.isTerminated else { return false }
            if #available(macOS 14, *) {
                NSApp.yieldActivation(to: original)
                return original.activate(from: .current, options: [])
            }
            return original.activate(options: [.activateIgnoringOtherApps])
        },
        hide: { [weak self] in
            self?.panel?.orderOut(nil)
            if NSApp.isActive { NSApp.hide(nil) }
        },
        schedule: { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    )

    private init() {
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.runner.observedActivation(pid: app.processIdentifier)
        }
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            // TIS can notify inside select(); let selected() record the latest target first.
            DispatchQueue.main.async { self?.runner.sourceChanged() }
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

    private func activatePanel() -> Bool {
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
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
        // A nonactivating panel alone did not recover the failed input connection.
        if #available(macOS 14, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
        return true
    }
}
