# 0.7.6 verification — 2026-10-23 (Asia/Seoul)

## User report and scope

After the 0.7.5 release, the user reported missed Korean switches during repeated switching. They confirmed that visiting another app and returning restored Korean input. They asked to restore the 0.7.4 approach for Korean while keeping English selection direct.

Version 0.7.6 (32) restores `Sources/InputSourceFocusRefresh.swift` and `Tests/FocusRefreshChecks.swift` from commit `9347473` without changes.

- A Korean selection queues the input-method app's activation. Once activation is observed, it requests return to the original app on the next main-queue turn, with no fixed hold.
- An English selection starts no app round trip. It cancels Korean work that has not started. If the Korean trip already owns activation, it preserves the latest language choice and finishes returning to the editor.
- External source changes, a user-selected third app, disabling the option and termination retain the 0.7.4 cleanup behavior. Existing timeout guards and the pointer policy are restored as well.
- The saved option, its default, shortcuts, Caps Lock mapping, composition rules and text delivery are unchanged.
- Settings help, README and implementation notes now describe app activation rather than the panel-only approach.

## Validation

The full `make check` passed: 27 pinned rules, 265,593 composition/session checks, 50 app round-trip and pointer checks, menu/Caps Lock/shortcut checks, and eight packaging checks. The signed app self-check reported `composition_ok=true network_blocked=true errno=1`.

The restored checks include English-only selection, English before Korean activation, English during entry and return, rapid Korean-English-Korean requests, delayed activation notifications, third-app changes, cancellation and old timers. These tests use injected actions and do not change real app focus.

The restored source and test files match commit `9347473` byte for byte. `git diff --check` passed.

## Installation

ABC was already selected, so the existing installer completed without requesting another source change.

- The previous 0.7.5 app remains in `build/backups/before-korean-activation.hklvo9us/Sunarae.app`; its signature passed verification.
- Confirmed installed version 0.7.6 (32), registered and enabled at `~/Library/Input Methods/Sunarae.app`.
- Installed and built executables share SHA-256 `2b8a7932abeca4ad93c5b84c5060bee89ec0bf71cdb1c5a4d9c0ae85a6efc538`. Strict signature verification and the installed composition/network self-check passed.
- A process runs from the installed path (PID 16640). The settings window displayed the new Korean-only activation description and enabled focus-refresh/Caps Lock options; it was dismissed without applying changes.
- Focus refresh, Caps Lock mapping and Escape-to-ABC preferences remain enabled. ABC remains selected.
- No physical switch, failed-switch recovery or appearance check has been completed for 0.7.6. Installation and process checks alone do not prove those outcomes.

## Limits

The earlier I/Y experiment recovered a failed switch through real app activation and return. It does not prove that this version prevents every missed switch. The separate experiment and the production input method also run in different contexts.

App activation may change an editor's window frame or pointer. English starts no new trip, but an already active Korean trip still has to return. Rapid switching, immediate typing and appearance require checks in the user's apps.
