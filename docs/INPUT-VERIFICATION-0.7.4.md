# 0.7.4 verification — 2026-10-23 (Asia/Seoul)

## Scope

The user asked to remove the app round trip when switching to English and keep Korean switching unchanged. Version 0.7.4 (30) follows Sejong98's direct English selection. It does not adopt Sejong98's panel-only Korean workaround.

- Successful ABC selection starts no panel, app activation, return request or pointer change. This includes the existing toggle shortcut and Escape / Control-[ paths.
- English selection cancels a Korean trip that has not started.
- If a Korean trip already owns activation, English selection updates its target and lets that trip return to the original editor. It starts no extra trip and does not force an extra whole-app hide.
- Korean selection keeps the 0.7.3 activation, return and pointer behavior, with the same saved option and default.
- Settings help and README explain the changed scope. No new preference, permission, input handling or composition rule was added.

## Reference comparison

The public [Noctiluca CJK manager](https://github.com/team-unstablers/NoctilucaServer/blob/ce049c59129a2faee681cfa8599b0464cd103036/CJKKeyboardHacks/shared/CJKInputMethodManager.swift) skips its workaround for ASCII-capable targets. Its non-ASCII workaround makes a nonactivating panel key and closes it on the window notification, without explicitly activating the app.

Static inspection of the linked Sejong98 1.0.2 (3) distribution also found the ASCII-target branch around the workaround, a nonactivating NSPanel with key=true/main=false, and panel closure in the key-window callback. It was not installed or run. This does not verify the App Store edition or prove behavior in the user's apps. The older P trial tested recovery after a failed switch, not prevention by this exact selection sequence.

## Validation

The final `make check` passed: 27 pinned rules, 265,593 composition/session checks, menu, Caps Lock, shortcut and 50 round-trip/pointer checks, plus all eight packaging checks. The signed executable reported `composition_ok=true network_blocked=true errno=1`.

The new regression cases cover standalone English selection, cancellation before entry, rapid Korean-English-Korean selection, English during entry or return, and English after actual return but before its notification. Tests inject system actions and do not change the user's input source or app focus.

## Installation

The installed 0.7.3 app was backed up in `build/backups/before-english-switch.0UCc70/Sunarae.app`; its signature passed verification. The first install attempt stopped before replacing the app because Sunarae was selected again. Installation awaits the user's switch to ABC.

## Limits

No physical switching or appearance test of 0.7.4 has been completed. Korean switching can still produce the previously reported occasional flicker. Rapid English selection while a Korean trip is already active still needs that existing trip to finish returning; it cannot undo an activation that has already happened. Removing the English workaround requires physical checks for English switch reliability and immediate typing in the user's editors.
