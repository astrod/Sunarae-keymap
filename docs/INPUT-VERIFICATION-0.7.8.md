# 0.7.8 verification — 2026-10-24 (Asia/Seoul)

## Report and scope

After installing 0.7.7, the user reported that switching from English to Korean hid the text caret until the next key. They confirmed that this was the insertion caret, not the mouse pointer.

No composition, text selection, pointer policy or activation API changed in this patch. Korean selection still starts an app round trip; English starts none. The late-return handling from 0.7.7 remains.

## Timing regression

Version 0.7.7 added an immediate frontmost-app check to the own-app activation notification. An injected sequence delivers that notification before the frontmost-app snapshot changes, then updates the snapshot before the next queued task:

- 0.7.6 requests return on that next turn.
- 0.7.7 drops the notification and makes no immediate return request. Its 700ms fallback remains pending for a normal entry. A cancelled entry has no such pending fallback.
- 0.7.8 checks the snapshot once more on the next main-queue turn and handles the activation if Sunarae now owns it. The existing return callback also checks ownership.

If another app still owns activation at the recheck, the runner leaves the outstanding entry alone. It does not poll, return to an old app, or discard an entry that may complete later. Explicit settings activation still clears pending work and the late-return record.

This proves a difference in the injected ordering, not that this exact ordering occurred in the user's app or caused the reported caret symptom.

## Checks

The full `make check` passed: 27 pinned rules, 265,593 composition/session checks, 104 focus/pointer checks, menu/Caps Lock/shortcut checks and eight packaging checks. The signed app self-check reported `composition_ok=true network_blocked=true errno=1`.

New cases cover delayed frontmost snapshots for normal and cancelled entries, a user-selected third app before the recheck, and a stale notification followed by a real activation. Existing rapid-switch and late-return tests also pass. These tests inject focus events and do not change real app focus.

The user allowed a short test in the isolated Input Probe. Under installed 0.7.7, the probe showed Sunarae selected but `rkk` entered Latin text in both native and CodeMirror fields. The CodeMirror caret was visible after the sampled switch, but the missing Korean composition makes this an invalid baseline for proving the caret fix. The probe was closed, ABC was selected, and the user was told the comparison was inconclusive. No user document was edited.

## Installation

- Preserved 0.7.7 at `build/backups/before-caret-timing.jo8o6c2e/Sunarae.app` and verified its signature.
- Installed 0.7.8 (34) while ABC was selected. Registration, enablement and strict signature verification passed.
- Installed and built executable SHA-256: `b1fb784efe3425a4f465952aff61ca47eeac3a1045d55559ac0727ee151eb85c`.
- The launch request timed out, but the installed executable was running as PID 36127. It was not launched a second time.
- The installed composition/network self-check passed. Focus refresh, Caps Lock mapping and Escape-to-ABC remain enabled.
- After installation, the user switched from English to Korean in their usual input field without pressing another key and reported: “이제 커서가 보여” (the caret is visible now). This confirms recovery for that check; it does not capture the underlying macOS event order or prove all rapid-switch cases in real apps.
