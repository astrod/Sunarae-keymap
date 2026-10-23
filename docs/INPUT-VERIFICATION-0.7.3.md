# 0.7.3 verification — 2026-10-23 (Asia/Seoul)

## User report

After installing 0.7.2, the user reported window-frame flicker in Chrome when switching to English and a mouse pointer appearing in ChatGPT. They want to retain the app round trip that recovered failed input switches.

## Changes

- Keep both language directions, the real app activation and immediate return sequence from 0.7.2.
- When a workspace notification confirms return to the original app or activation of a third app, close only the panel. Do not hide the entire input-method app based on a potentially stale local active flag. Whole-app hiding remains a fallback when a failed or cancelled trip still owns activation.
- Apply `NSCursor.setHiddenUntilMouseMoves(true)` before and at the input method's brief activation. If the user moved the pointer before activation, release that policy instead of re-hiding it. Local resignation and inactive cleanup release the policy.
- Keep pointer-position comparison in memory only. No mouse monitor, cursor hide-count API, private cursor visibility API, event tap or new permission is used.

The extra whole-app hide was a possible source of avoidable transitions, not a measured root cause of the reported Chrome flicker. The pointer change affects Sunarae's own activation; it does not force the editor to keep its pointer hidden after return.

## Validation

The final `make check` passed:

- 27 rules match the pinned source; 265,593 composition/session checks passed.
- 49 app round-trip and pointer-policy checks passed, including stale active state on return, third-app activation, failed return, mouse movement and late activation after cancellation.
- IMK menu, Caps Lock, shortcut/persistence and eight packaging checks passed.
- Signed self-check: `composition_ok=true network_blocked=true errno=1`.

These checks do not prove the appearance of a real app switch. Physical appearance checks remain pending.

## Installation

- Installed 0.7.3 (29) in `~/Library/Input Methods/Sunarae.app` after the user switched to ABC and requested installation.
- The installed and built executables share SHA-256 `7ab615d73c9394ef96a83708ccfb03a485c22cb4fe54d5e1d28116e0adf426a8`. Strict bundle signature verification passed.
- Confirmed a new process running from the installed path (PID 87665). The launch UI request timed out, but the process check confirmed launch; the app was not launched again.
- The installed executable passed its composition/network self-check. Sunarae remains registered and enabled; ABC remains selected for the user's next physical switch.
- Preserved `refreshFocusOnInputSwitch`, `capsLockToF18Enabled` and `switchToABCOnEscape`, all set to true. No setting was changed for this update.
- Chrome frame flicker, ChatGPT pointer behavior and physical typing after switching remain to be checked by the user. Installation checks alone do not prove those outcomes.

## Limits

Actual app activation still deactivates and reactivates the editor. Chrome may redraw its frame and ChatGPT may reset its cursor state during that change. This update reduces avoidable operations; it does not establish flicker-free behavior in all apps. There is no claim that pointer state can be preserved across arbitrary apps.

Apple documents the temporary cursor policy in [setHiddenUntilMouseMoves](https://developer.apple.com/documentation/appkit/nscursor/sethiddenuntilmousemoves(_:)). This method resets on mouse movement and must not be balanced with `NSCursor.unhide`.
