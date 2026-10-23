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
    private struct LateReturn {
        let entryID: Int
        var destinationPID: Int32
    }
    private let enabled: () -> Bool
    private let context: () -> FocusRefreshContext
    private let ownPID: Int32
    private let supportedSources: Set<String>
    private let refreshSource: String
    private let enter: () -> Bool
    private let restore: (Int32) -> Bool
    private let hide: (Bool) -> Void
    private let schedule: (Double, @escaping () -> Void) -> Void
    private var nextID = 0
    private var request: Request?
    // AppKit cannot cancel or identify individual activation completions. Keep
    // one return destination after abandoning an entry, even after a first
    // recovery: another previously requested entry may still arrive. Explicit
    // settings activation clears it. The guard has no polling timer and records
    // no input or app history.
    private var lateReturn: LateReturn?
    var isPending: Bool { request != nil }

    init(enabled: @escaping () -> Bool, context: @escaping () -> FocusRefreshContext,
         ownPID: Int32, supportedSources: Set<String>, refreshSource: String, enter: @escaping () -> Bool,
         restore: @escaping (Int32) -> Bool, hide: @escaping (Bool) -> Void,
         schedule: @escaping (Double, @escaping () -> Void) -> Void) {
        self.enabled = enabled
        self.context = context
        self.ownPID = ownPID
        self.supportedSources = supportedSources
        self.refreshSource = refreshSource
        self.enter = enter
        self.restore = restore
        self.hide = hide
        self.schedule = schedule
    }

    func selected(_ identifier: String) {
        let current = context()
        rememberExternalApp(current.applicationPID)
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
        // Direct English selection never starts a trip. If a Korean trip was
        // already active, the branch above lets it return to the same editor.
        guard identifier == refreshSource, let pid = current.applicationPID, pid != ownPID else { return }
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
            else { self.abandonEntry(id) }
        }
        let previousLateReturn = lateReturn
        let entered = enter()
        if !entered {
            // A rejected entry sent no activation request. A synchronous cancel
            // inside enter() must not leave a recovery record for that attempt.
            if lateReturn?.entryID == id {
                lateReturn = previousLateReturn
                rememberExternalApp(context().applicationPID)
            }
            if request?.id == id { finish(id) }
            else { hide(false) }
            return
        }
        guard request?.id == id else {
            // AppKit may finish ordering the panel after a reentrant cancellation.
            hide(false)
            return
        }
    }

    func observedActivation(pid: Int32) {
        if pid == ownPID {
            // An old notification must not pull the user away from another app.
            guard context().applicationPID == ownPID else { return }
            if request == nil || request?.phase == .queued {
                guard let destination = lateReturn?.destinationPID else { return }
                // A late entry also satisfies a newer queued Korean request.
                // Replace it before its callback can issue another activation.
                nextID += 1
                request = Request(id: nextID, originalPID: destination,
                                  sourceID: context().sourceID ?? "", phase: .entering)
            }
            guard var pending = request else { return }
            guard pending.phase == .entering, !pending.activated else { return }
            pending.activated = true
            request = pending
            // Same as the successful Y trial: no fixed dwell after activation.
            schedule(0) { [weak self] in self?.returnToOriginal(pending.id) }
            return
        }
        rememberExternalApp(pid)
        guard let pending = request else { return }
        if pid == pending.originalPID {
            if pending.phase == .returning || pending.activated { finish(pending.id, activePID: pid) }
        } else {
            // If entry completes after the user changes apps, return to that
            // newer app, not to the editor where the first request began.
            abandonEntry(pending.id, activePID: pid)
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

    private func finish(_ id: Int, activePID: Int32? = nil) {
        guard let pending = request, pending.id == id else { return }
        request = nil
        if pending.phase != .queued {
            // A workspace return notification can arrive before our local
            // isActive flag clears. Never hide the whole app on normal return.
            hide((activePID ?? context().applicationPID) == ownPID)
        }
    }

    private func rememberExternalApp(_ pid: Int32?) {
        guard let pid, pid != ownPID else { return }
        lateReturn?.destinationPID = pid
    }

    private func retainLateReturn(_ pending: Request, activePID: Int32?) {
        guard pending.phase == .entering, !pending.activated, activePID != ownPID else { return }
        lateReturn = LateReturn(entryID: pending.id, destinationPID: activePID ?? pending.originalPID)
    }

    private func abandonEntry(_ id: Int, activePID: Int32? = nil) {
        guard let pending = request, pending.id == id else { return }
        retainLateReturn(pending, activePID: activePID ?? context().applicationPID)
        finish(id, activePID: activePID)
    }

    func cancel() {
        guard let pending = request else { return }
        retainLateReturn(pending, activePID: context().applicationPID)
        request = nil
        if pending.phase == .entering, context().applicationPID == ownPID {
            _ = restore(pending.originalPID)
        }
        if pending.phase != .queued { hide(context().applicationPID == ownPID) }
    }

    func prepareForUserActivation() {
        // Opening settings is deliberate activation, not a late refresh. Let
        // it stay active and invalidate all queued return/entry callbacks.
        let pending = request
        request = nil
        lateReturn = nil
        if let pending, pending.phase != .queued { hide(false) }
    }
}

/// Hides this app's pointer while it briefly handles a keyboard-driven refresh.
/// The editor keeps control of its own cursor after we return.
final class FocusRefreshCursor {
    private let location: () -> NSPoint
    private let setHidden: (Bool) -> Void
    private var startLocation: NSPoint?

    init(location: @escaping () -> NSPoint, setHidden: @escaping (Bool) -> Void) {
        self.location = location
        self.setHidden = setHidden
    }

    func prepare() {
        startLocation = location()
        setHidden(true)
    }

    func becameActive() {
        guard let startLocation else { return }
        // Do not re-hide a pointer the user moved while activation was pending.
        if location() != startLocation { clear() }
        else { setHidden(true) }
    }

    func clear() {
        guard startLocation != nil else { return }
        startLocation = nil
        setHidden(false)
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
    private var localObservers: [NSObjectProtocol] = []
    private let cursor = FocusRefreshCursor(location: { NSEvent.mouseLocation },
                                           setHidden: { NSCursor.setHiddenUntilMouseMoves($0) })
    private lazy var runner = FocusRefreshRunner(
        enabled: { InputSettings.shared.refreshFocusOnInputSwitch },
        context: {
            FocusRefreshContext(sourceID: InputSource.currentIdentifier(),
                                applicationPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        },
        ownPID: ProcessInfo.processInfo.processIdentifier,
        supportedSources: [InputSource.sunaraeID, InputSource.abcID],
        refreshSource: InputSource.sunaraeID,
        enter: { [weak self] in self?.activatePanel() ?? false },
        restore: { pid in
            guard let original = NSRunningApplication(processIdentifier: pid), !original.isTerminated else { return false }
            if #available(macOS 14, *) {
                NSApp.yieldActivation(to: original)
                return original.activate(from: .current, options: [])
            }
            return original.activate(options: [.activateIgnoringOtherApps])
        },
        hide: { [weak self] abandonActivation in
            self?.panel?.orderOut(nil)
            if abandonActivation && NSApp.isActive { NSApp.hide(nil) }
            if !NSApp.isActive { self?.cursor.clear() }
        },
        schedule: { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        }
    )

    private init() {
        localObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in self?.cursor.becameActive() })
        localObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main
        ) { [weak self] _ in self?.cursor.clear() })
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
        if !NSApp.isActive { cursor.clear() }
    }

    func prepareForUserActivation() {
        precondition(Thread.isMainThread)
        runner.prepareForUserActivation()
        cursor.clear()
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
        cursor.prepare()
        panel?.makeKeyAndOrderFront(nil)
        // A nonactivating panel alone did not recover the failed input connection.
        if #available(macOS 14, *) { NSApp.activate() }
        else { NSApp.activate(ignoringOtherApps: true) }
        return true
    }
}
