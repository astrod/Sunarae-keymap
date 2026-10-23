# 0.7.2 verification — 2026-10-23 (Asia/Seoul)

## What changed

The prior panel-only option did not recover an actual failed switch. This version replaces it with the successful Y experiment: open a transparent nonactivating NSPanel, explicitly activate the input-method app, and request return to the original app on the next main-queue turn after activation is observed. There is no fixed dwell. Both Sunarae/ABC directions and the existing Escape action use this path. The option remains default-on and respects a saved false.

## Evidence from the separate experiment

- P (panel only) failed to recover the user's actual switch failure.
- I (real app round trip with an ordinary window and 100ms hold) recovered it.
- U and Y each completed two normal-state trials. The user reported no noticeable flicker. These normal-state trials do not establish recovery.
- The user then tried Y during an actual switch failure and reported recovery with no noticeable flicker.
- The corresponding record was trial 5 in `trial-1792514425-50334.jsonl`, dated `2026-10-23T13:37:10Z`, variant `fastPanel`.
- Both activation notifications showed Codex → diagnostic app → Codex. The source remained `local.inputmethod.Sunarae` before, during and after. The panel was hidden at completion.
- Trial start to return notification: about 24ms. Diagnostic-app activation to original-app return: about 12ms. These exclude the diagnostic's 150ms pre-start key-release allowance and post-return observation delay.
- Recovery and absence of flicker are the user's observations. Metadata does not record text or video and cannot independently prove either.

## Automated checks

`make check` passed:

- 27 rules match the pinned source; 265,593 composition/session checks passed.
- 39 app round-trip checks cover both directions, queued and in-progress rapid switching, source/app changes, rejection, timeout, reentrant cancellation, synchronous notifications and old callbacks.
- IMK menu, Caps Lock, shortcut/persistence checks passed.
- Eight packaging checks passed.
- Signed self-check: `composition_ok=true network_blocked=true errno=1`.

No automated test switches the user's input source or activates another app.

## Installation

- Installed 0.7.2 (28) in `~/Library/Input Methods/Sunarae.app` after the user switched to ABC and authorized installation.
- The installed and built executables share SHA-256 `b6aebf000985ebc62a0db3aa0e7a74487d6a1ea2bfa588d34de62d35078a4ff8`. Strict bundle signature verification passed. The process runs from the installed path.
- Enabled **한영 전환 보완** in the installed app's settings and applied the change. The reopened setting and persisted `refreshFocusOnInputSwitch = true` were confirmed. Caps Lock switching and Escape-to-ABC remain enabled.
- The installed signed executable passed its composition/network self-check. The settings window was closed, leaving ABC selected for the user's next physical switch.
- Physical typing immediately after switching with the installed version has not yet been confirmed. Installation and preference checks alone do not prove that input reaches an existing editor correctly.

## Subsequent user report

The user reported window-frame flicker in Chrome when switching to English, and a mouse pointer appearing in ChatGPT. The standalone Y result did not predict these appearance effects during automatic production switching. The user asked to keep the real app round trip while reducing these effects.

## Limits

The diagnostic used a separate accessory app. The production input method uses the same activation/return sequence but runs inside its existing IMK process and triggers it after source selection. The macOS 13 fallback and typing immediately after production switches require physical verification. No key buffer or synthetic replay is added. A window-free or zero-latency switch is not claimed.

## Cleanup

The standalone focus experiment is no longer part of ongoing development. Its process was stopped, and its source, built app and raw local records were moved to Trash after preserving this result summary. No diagnostic hotkeys remain registered. Regression checks for the shipped implementation remain in `Tests/FocusRefreshChecks.swift`.
