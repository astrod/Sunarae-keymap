import Foundation

private final class FocusFixture {
    var enabled = true
    var context = FocusRefreshContext(sourceID: "korean", applicationPID: 42)
    var visible = false
    var opened = 0
    var hidden = 0
    var showAccepted = true
    var onShow: (() -> Void)?
    var onHide: (() -> Void)?
    var time = 0.0
    var scheduled: [(Double, () -> Void)] = []
    lazy var runner = FocusRefreshRunner(
        enabled: { self.enabled }, context: { self.context }, ownPID: 7,
        refreshSource: "korean",
        show: {
            self.opened += 1
            self.onShow?()
            // AppKit may finish ordering after sending a synchronous notification.
            self.visible = true
            return self.showAccepted
        },
        hide: { self.hidden += 1; self.visible = false; self.onHide?() },
        schedule: { self.scheduled.append((self.time + $0, $1)) }
    )

    func activate(_ pid: Int32) {
        context = FocusRefreshContext(sourceID: context.sourceID, applicationPID: pid)
        runner.contextChanged()
    }

    func source(_ identifier: String) {
        context = FocusRefreshContext(sourceID: identifier, applicationPID: context.applicationPID)
    }

    func advance(_ delta: Double = 0) {
        let target = time + delta
        while let index = scheduled.indices.min(by: { scheduled[$0].0 < scheduled[$1].0 }),
              scheduled[index].0 <= target {
            let (due, action) = scheduled.remove(at: index)
            time = due
            action()
        }
        time = target
    }
}

func runFocusRefreshChecks() {
    var count = 0
    func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
        count += 1
    }
    do {
        let f = FocusFixture()
        f.enabled = false
        f.runner.selected("korean")
        f.enabled = true
        f.runner.selected("unrelated")
        f.source("english")
        f.runner.selected("korean")
        f.runner.selected("english")
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 7)
        f.runner.selected("korean")
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: nil)
        f.runner.selected("korean")
        check(f.opened == 0 && f.hidden == 0 && !f.runner.isPending,
              "disabled, English, stale, own-app and unknown contexts leave focus alone")
        check(f.scheduled.isEmpty, "skipped selections queue no work")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        check(f.opened == 1 && f.visible && f.runner.isPending, "Korean selection opens the panel immediately")
        check(f.context.applicationPID == 42, "panel lifecycle does not need an app activation")
        f.runner.panelBecameKey()
        check(!f.visible && !f.runner.isPending && f.hidden == 1, "key-window event closes the panel immediately")
        f.advance(1)
        f.runner.panelBecameKey()
        f.runner.panelResignedKey()
        check(f.hidden == 1, "late key events and timeouts do nothing")
    }
    do {
        let f = FocusFixture()
        f.onShow = { f.runner.panelBecameKey() }
        f.runner.selected("korean")
        check(!f.visible && !f.runner.isPending, "synchronous key callback cannot leave a reordered panel visible")
        check(f.hidden == 1 && f.scheduled.isEmpty, "synchronous completion needs no timer or deferred close")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance(0.19)
        check(f.visible, "missing key notification keeps cleanup armed")
        f.advance(0.02)
        check(!f.visible && !f.runner.isPending, "missing key notification closes after 200ms")
    }
    do {
        let f = FocusFixture()
        f.showAccepted = false
        f.runner.selected("korean")
        check(!f.visible && !f.runner.isPending && f.hidden == 1, "rejected panel opening cleans up")
        check(f.scheduled.isEmpty, "failed opening schedules no timeout")
    }
    for duringShow in [false, true] {
        let f = FocusFixture()
        let english = { f.source("english"); f.runner.selected("english") }
        if duringShow { f.onShow = english }
        f.runner.selected("korean")
        if !duringShow { english() }
        f.advance(1)
        check(f.opened == 1 && !f.visible && !f.runner.isPending,
              "English selection closes a pending panel without opening another")
        check(f.context.sourceID == "english" && f.context.applicationPID == 42,
              "English remains selected in the original app")
    }
    for duringShow in [false, true] {
        let f = FocusFixture()
        if duringShow { f.onShow = { f.activate(99) } }
        f.runner.selected("korean")
        if !duringShow { f.activate(99) }
        f.advance(1)
        check(!f.visible && !f.runner.isPending && f.context.applicationPID == 99,
              "another app taking focus closes the panel without restoring the old app")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.source("third.source")
        f.runner.contextChanged()
        check(!f.visible && !f.runner.isPending, "external source change closes the panel")
        f.source("korean")
        f.runner.contextChanged()
        check(f.opened == 1, "external source changes cannot start a refresh")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.runner.contextChanged()
        check(f.visible, "unchanged source notification does not cancel the panel")
        f.runner.panelResignedKey()
        check(!f.visible && !f.runner.isPending, "losing key status closes the panel")
    }
    for duringShow in [false, true] {
        let f = FocusFixture()
        if duringShow { f.onShow = { f.runner.cancel() } }
        f.runner.selected("korean")
        if !duringShow { f.runner.cancel() }
        f.runner.cancel()
        f.advance(1)
        check(!f.visible && !f.runner.isPending && f.hidden == 1,
              "cancellation or termination closes once even inside panel ordering")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.enabled = false
        f.runner.contextChanged()
        check(!f.visible && !f.runner.isPending, "disabling the option cancels the panel")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance(0.1)
        f.source("english")
        f.runner.selected("english")
        f.source("korean")
        f.runner.selected("korean")
        f.advance(0.11)
        check(f.visible && f.runner.isPending && f.opened == 2, "old timeout cannot close a newer Korean panel")
        f.runner.panelBecameKey()
        f.advance(1)
        check(!f.visible && !f.runner.isPending && f.hidden == 2, "rapid switching cleans up each panel")
    }
    do {
        let f = FocusFixture()
        f.onShow = {
            if f.opened == 1 {
                f.runner.selected("korean")
                f.runner.panelBecameKey()
                check(f.opened == 1, "reentrant Korean selection does not nest panel ordering")
            } else {
                f.runner.panelBecameKey()
            }
        }
        f.onHide = { f.runner.panelResignedKey() }
        f.runner.selected("korean")
        check(!f.visible && f.runner.isPending, "old opening closes while the new selection stays queued")
        f.advance()
        check(f.opened == 2 && f.hidden == 2 && !f.visible && !f.runner.isPending,
              "queued reentrant selection completes after old cleanup")
    }
    do {
        let f = FocusFixture()
        f.onShow = {
            f.runner.selected("korean")
            f.source("english")
            f.runner.selected("english")
        }
        f.runner.selected("korean")
        f.advance(1)
        check(f.opened == 1 && !f.visible && !f.runner.isPending, "English cancels a reentrant queued request")
    }
    do {
        let f = FocusFixture()
        f.onShow = {
            f.runner.selected("korean")
            f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 99)
        }
        f.runner.selected("korean")
        f.advance(1)
        check(f.opened == 1 && !f.visible && !f.runner.isPending,
              "queued request rechecks the app before opening")
    }
    print("Nonactivating panel lifecycle checks passed: \(count) (no real focus changes)")
}
