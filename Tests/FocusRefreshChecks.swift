import Foundation

private final class FocusFixture {
    var enabled = true
    var context = FocusRefreshContext(sourceID: "korean", applicationPID: 42)
    var visible = false
    var opened = 0
    var hidden = 0
    var appHides = 0
    var restored: [Int32] = []
    var enterAccepted = true
    var returnAccepted = true
    var onEnter: (() -> Void)?
    var onRestore: (() -> Void)?
    var time = 0.0
    var scheduled: [(Double, () -> Void)] = []
    lazy var runner = FocusRefreshRunner(
        enabled: { self.enabled }, context: { self.context }, ownPID: 7,
        supportedSources: ["korean", "english"], refreshSource: "korean",
        enter: {
            self.opened += 1
            self.onEnter?()
            self.visible = true
            return self.enterAccepted
        },
        restore: { self.restored.append($0); self.onRestore?(); return self.returnAccepted },
        hide: { abandon in
            self.hidden += 1; self.visible = false
            if abandon { self.appHides += 1 }
        },
        schedule: { self.scheduled.append((self.time + $0, $1)) }
    )

    func activate(_ pid: Int32) {
        context = FocusRefreshContext(sourceID: context.sourceID, applicationPID: pid)
        runner.observedActivation(pid: pid)
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
        f.advance(2)
        check(f.opened == 0 && !f.runner.isPending, "disabled option leaves activation alone")
        f.enabled = true
        f.runner.selected("unrelated")
        f.runner.selected("english")
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 7)
        f.runner.selected("korean")
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: nil)
        f.runner.selected("korean")
        f.advance(2)
        check(f.opened == 0 && f.hidden == 0, "unsupported, stale and own-settings contexts are skipped")
    }
    do {
        let f = FocusFixture()
        f.source("english")
        f.runner.selected("english")
        f.advance(2)
        check(f.opened == 0 && f.hidden == 0 && f.restored.isEmpty,
              "English selection changes no panel or app activation")
        check(!f.runner.isPending && f.scheduled.isEmpty, "English selection queues no refresh")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        check(f.opened == 0, "the triggering key returns before activation")
        f.advance()
        check(f.opened == 1 && f.visible && f.restored.isEmpty, "request entry without assuming activation")
        f.activate(7)
        check(f.restored.isEmpty, "return outside activation callback")
        f.advance()
        check(f.restored == [42], "return immediately without the diagnostic's 100ms hold")
        check(f.runner.isPending, "accepted request does not prove app returned")
        f.activate(42)
        check(!f.runner.isPending && !f.visible, "return notification closes the panel")
        check(f.appHides == 0, "normal return never hides the whole input-method app")
        f.advance(2)
        check(f.restored == [42] && f.hidden == 1, "stale timeouts do nothing")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.source("english")
        f.runner.selected("english")
        f.advance()
        check(f.opened == 0 && !f.runner.isPending, "English cancels a queued Korean trip before entry")
        f.source("korean")
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.source("korean")
        f.runner.selected("korean")
        f.runner.sourceChanged()
        f.advance()
        check(f.restored == [42] && f.opened == 1, "a switch while away retains original app")
        f.source("english")
        f.runner.selected("english")
        f.runner.sourceChanged()
        f.advance()
        check(f.opened == 1 && f.appHides == 0, "English during return starts no trip and does not hide the app")
        f.activate(42)
        f.advance(2)
        check(!f.visible && f.restored == [42], "latest choice survives return without another trip")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.advance()
        // The app is already back, but its activation notification is still queued.
        f.context = FocusRefreshContext(sourceID: "english", applicationPID: 42)
        f.runner.selected("english")
        f.activate(42)
        f.advance()
        check(f.opened == 1 && !f.runner.isPending, "English after actual return starts no new refresh")
        check(f.restored == [42] && !f.visible, "delayed return notification leaves the editor in English")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.source("english")
        f.runner.selected("english")
        f.source("korean")
        f.runner.selected("korean")
        f.advance()
        check(f.opened == 1, "rapid Korean-English-Korean requests start only the final Korean trip")
        f.activate(7)
        f.advance()
        f.activate(42)
        f.advance(2)
        check(f.restored == [42] && !f.visible, "cancelled queued callback cannot affect the final trip")
    }
    for returning in [false, true] {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        if returning { f.advance() }
        f.source("english")
        f.runner.selected("english")
        f.runner.sourceChanged()
        f.advance()
        check(f.opened == 1 && f.restored == [42] && f.appHides == 0,
              "English during an active Korean trip only completes the existing return")
        f.activate(42)
        f.advance(2)
        check(!f.runner.isPending && !f.visible && f.context.sourceID == "english",
              "English stays selected after the existing Korean trip finishes")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.activate(99)
        f.advance(2)
        check(f.opened == 0 && f.restored.isEmpty, "user switch before entry cancels queued refresh")
    }
    for afterActivation in [false, true] {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        if afterActivation { f.activate(7) }
        f.activate(99)
        f.advance(2)
        check(f.restored.isEmpty && !f.visible, "never steal focus from a third app")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.activate(42)
        f.advance(2)
        check(f.restored.isEmpty && !f.visible, "manual return before request is respected")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance(1)
        check(!f.visible && !f.runner.isPending && f.restored.isEmpty, "entry timeout closes panel")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.context = FocusRefreshContext(sourceID: "korean", applicationPID: 7)
        f.advance(0.71)
        check(f.restored == [42], "restore owned activation even if entry notification is missing")
        f.advance(1)
        check(!f.visible && !f.runner.isPending, "return timeout cleans up")
    }
    do {
        let f = FocusFixture()
        f.enterAccepted = false
        f.runner.selected("korean")
        f.advance(2)
        check(!f.visible && !f.runner.isPending, "failed entry cleans up")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.advance()
        // The return notification is authoritative even if local state is stale.
        f.runner.observedActivation(pid: 42)
        check(!f.visible && f.appHides == 0, "stale active state must not cause another app hide on return")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.runner.observedActivation(pid: 99)
        check(!f.visible && f.appHides == 0, "third-app notification must not cause app hide")
    }
    do {
        let f = FocusFixture()
        f.returnAccepted = false
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.advance(2)
        check(f.restored == [42] && !f.visible && !f.runner.isPending, "rejected return does not leave hidden key panel")
        check(f.appHides == 1, "failed return still abandons owned activation")
    }
    for duringEntry in [false, true] {
        let f = FocusFixture()
        f.runner.selected("korean")
        if duringEntry { f.advance(); f.activate(7) }
        f.source("third.source")
        f.runner.sourceChanged()
        f.advance(2)
        check(!f.visible && !f.runner.isPending, "external source changes cancel refresh")
        check(f.restored == (duringEntry ? [42] : []), "restore only activation owned by refresh")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.enabled = false
        f.runner.cancel()
        f.advance(2)
        check(f.restored == [42] && !f.visible, "disabling or quitting while away restores editor")
    }
    do {
        let f = FocusFixture()
        f.onEnter = { f.runner.cancel() }
        f.runner.selected("korean")
        f.advance(2)
        check(!f.visible && !f.runner.isPending, "reentrant cancel cannot leave reordered panel visible")
    }
    do {
        let f = FocusFixture()
        f.onEnter = { f.activate(7) }
        f.onRestore = { f.activate(42) }
        f.runner.selected("korean")
        f.advance(2)
        check(f.restored == [42] && !f.visible && !f.runner.isPending, "synchronous notifications do not leave stale work")
    }
    do {
        let f = FocusFixture()
        f.runner.selected("korean")
        f.advance()
        f.activate(7)
        f.advance()
        f.activate(42)
        f.advance(0.5)
        f.runner.selected("korean")
        f.advance(0.21)
        check(f.runner.isPending && f.visible, "old timeout cannot finish a newer request")
        f.activate(7)
        f.advance()
        f.activate(42)
        f.advance(2)
        check(f.opened == 2 && f.restored == [42, 42] && !f.visible, "new request completes independently")
    }
    do {
        var point = NSPoint(x: 20, y: 30)
        var cursorChanges: [Bool] = []
        let cursor = FocusRefreshCursor(location: { point }, setHidden: { cursorChanges.append($0) })
        cursor.becameActive()
        cursor.clear()
        check(cursorChanges.isEmpty, "settings activation outside a refresh leaves cursor alone")
        cursor.prepare()
        cursor.becameActive()
        check(cursorChanges == [true, true], "apply the pointer policy again after actual activation")
        cursor.clear()
        cursor.clear()
        check(cursorChanges == [true, true, false], "resign or cleanup releases pointer policy once")
        cursor.prepare()
        point = NSPoint(x: 21, y: 30)
        cursor.becameActive()
        cursor.clear()
        check(cursorChanges == [true, true, false, true, false], "mouse movement before activation cancels pointer hiding")
        cursor.prepare()
        cursor.clear()
        cursor.becameActive()
        check(cursorChanges == [true, true, false, true, false, true, false], "late activation after cancellation does not hide pointer")
    }
    print("App round-trip lifecycle checks passed: \(count) (no real focus changes)")
}
