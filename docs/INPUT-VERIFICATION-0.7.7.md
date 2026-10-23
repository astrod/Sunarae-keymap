# 0.7.7 verification — 2026-10-23 (Asia/Seoul)

## Scope

The user asked to fix cancellation before a delayed activation completes, keep app round trips limited to Korean selection, and check rapid switching.

The 0.7.6 review found four failing injected sequences: English before activation, disabling before activation, activation after the cleanup timeout, and Korean-English-Korean with an earlier activation still outstanding. The normal sequence passed. No physical app focus changed in that review.

Version 0.7.7 (33) keeps one late-return record when an entry is cancelled or times out before activation. If Sunarae later becomes frontmost, it requests return without another entry or input-source selection. If the user picked a different app in the meantime, that newer app becomes the destination.

- A late entry supersedes newer queued work, preventing an extra activation from that queued callback.
- A new Korean selection can retry an uncompleted entry. Multiple already submitted activations can each be returned from.
- The final input language is preserved. Standalone English selection starts no trip.
- The late-return record has no polling timer or disk storage. It stores one destination PID and an entry ID, not typed text or an app history.
- Because AppKit does not identify individual activation completions, the record survives the first recovery. Deliberately opening Sunarae settings clears it and queued work before activating the settings app. Process exit also discards it.
- A known rejected entry cannot create a spurious recovery record or erase an older outstanding one. A failed return closes the panel and releases owned activation without a retry loop.
- Existing pointer handling, input rules, shortcuts, permissions and saved preferences are unchanged.

## Validation

The five original review scenarios were rerun against the changed runner: all passed, including the four that failed in 0.7.6. These tests inject system actions; they do not prove real macOS timing or physical input behavior.

The full `make check` passed: 27 pinned rules, 265,593 composition/session checks, 95 app round-trip and pointer checks, menu/Caps Lock/shortcut checks, and all eight packaging checks. The signed app self-check reported `composition_ok=true network_blocked=true errno=1`.

The new cases include 200 alternating selections before late activation, final English and final Korean choices, entry timeout, external app/source changes, duplicate or stale notifications, multiple outstanding activations, deliberate settings activation, synchronous cancellation during entry, rejected entry with an older outstanding request, and a failed return. No automatic check changes real app focus.

## Installation

ABC was already selected and the existing installer completed successfully.

- The previous 0.7.6 app remains in `build/backups/before-late-return.r5s8n0j8/Sunarae.app`; its signature passed verification.
- Confirmed installed version 0.7.7 (33), registered and enabled at `~/Library/Input Methods/Sunarae.app`.
- Installed and built executables share SHA-256 `8694b3c8659b0c4a547cdc40f6ef959f2cc118fd22b79478f0f320ada995cfeb`. Strict signature verification and the installed composition/network self-check passed.
- The UI launch request timed out, but a process check confirmed the installed executable running as PID 32479. No second launch was attempted.
- Focus refresh, Caps Lock mapping and Escape-to-ABC remain enabled. No saved preference was changed. ABC remains selected for the user's next physical switch.
- Physical delayed-activation recovery and rapid typing in the user's apps remain unverified for this version.

## Limits

AppKit activation remains asynchronous and is not guaranteed. This change retains cleanup information rather than claiming to cancel an OS request. If a return destination has quit or macOS rejects the return, the app closes its panel and abandons owned activation. It cannot guarantee the exact editor receives focus in that case, or revoke a return request already submitted to macOS.

Window-frame and pointer changes may remain. Fast physical typing immediately after a switch, actual failed-switch recovery and settings interaction still require user checks. No user document or input content was recorded.
