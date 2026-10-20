import Foundation

private final class FocusFixture {
    var enabled = true
    var context = FocusRefreshContext(sourceID: "korean", applicationPID: 42)
    var visible = false
    var opened = 0
    var hidden = 0
    var onShow: (() -> Void)?
    var delayed: [() -> Void] = []
    lazy var runner = FocusRefreshRunner(
        enabled: { self.enabled }, context: { self.context }, ownPID: 7, supportedSources: ["korean", "english"],
        show: { self.opened += 1; self.onShow?(); self.visible = true; return true },
        hide: { self.hidden += 1; self.visible = false },
        schedule: { _, action in self.delayed.append(action) }
    )
}

func runFocusRefreshChecks() {
    do {
        let f = FocusFixture()
        f.enabled = false
        f.runner.selected("korean")
        precondition(f.opened == 0 && !f.runner.isPending)
        f.enabled = true
        f.runner.selected("unrelated")
        precondition(f.opened == 0)
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 7)
        f.runner.selected("korean")
        precondition(f.opened == 0) // Do not refresh the input method's own settings.
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: nil)
        f.runner.selected("korean")
        precondition(f.opened == 0)
    }
    do {
        let f = FocusFixture()
        f.onShow = { f.runner.panelBecameKey(); precondition(f.hidden == 0) }
        f.runner.selected("korean")
        precondition(f.opened == 1 && f.hidden == 1 && !f.visible && !f.runner.isPending)
        precondition(f.delayed.isEmpty) // Closed before returning to key event processing.
        f.runner.panelBecameKey()
        precondition(f.hidden == 1)
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        precondition(f.visible && f.runner.isPending)
        f.runner.panelBecameKey()
        precondition(!f.visible && !f.runner.isPending)
        f.delayed[0]()
        precondition(f.hidden == 1) // Late timeout is inert.
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.delayed[0]()
        precondition(!f.visible && !f.runner.isPending) // Missing notification still closes.
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.runner.selected("unrelated")
        precondition(!f.visible && !f.runner.isPending)
        f.runner.selected("korean")
        f.delayed[0]()
        precondition(f.visible && f.runner.isPending) // Old request cannot close the new one.
        f.delayed[1]()
        precondition(!f.visible)
    }
    do {
        let f = FocusFixture()
        f.onShow = { f.runner.panelBecameKey() }
        f.runner.selected("korean")
        f.context = FocusRefreshContext(sourceID: "english", applicationPID: 42)
        f.runner.selected("english")
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 42)
        f.runner.selected("korean")
        precondition(f.opened == 3 && f.hidden == 3 && !f.visible && !f.runner.isPending)
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 99)
        f.runner.contextChanged()
        precondition(!f.visible && !f.runner.isPending)
        f.runner.selected("korean")
        f.enabled = false
        f.runner.contextChanged()
        precondition(!f.visible)
    }
    do {
        let f = FocusFixture()
        f.onShow = {
            f.context = FocusRefreshContext(sourceID: "english", applicationPID: 42)
            f.runner.contextChanged()
        }
        f.runner.selected("korean")
        precondition(!f.visible && !f.runner.isPending) // Even a reentrant cancellation leaves no window.
    }
    print("Nonactivating focus panel lifecycle checks passed (no real focus changes)")
}
