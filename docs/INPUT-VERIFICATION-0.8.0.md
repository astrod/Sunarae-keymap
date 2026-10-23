# 0.8.0 verification — 2026-10-24 (Asia/Seoul)

## Scope

The user requested Caps Lock, right Option, right Command and right Control as selectable switch keys, recorded through the existing settings window without new privacy permissions. Version 0.8.0 (35) adds that choice while retaining the F1–F20 and Control/Option/Command chord support.

The dedicated key maps to F18 and loses its original role, including modifier chords. The settings window explains this before Apply. Right modifiers are selected on release after a standalone press; Caps Lock uses its lock-state event. Recording temporarily suspends the saved mapping and hotkey, and restores them on completion, Escape, focus loss or close. A failed restoration remains retryable. Recording does not save the candidate.

Existing Caps Lock settings and login ownership are read on upgrade. Successful Apply stores the general key choice. Mapping changes preserve unrelated entries, reject conflicts and permission-limited mappings, and roll back failures across keyboards. The legacy uninstall flag and argument remain so older uninstall tools also clean up the new dedicated keys.

`InputSource`, `InputSourceFocusRefresh`, `GlobalHotKey`, `InputSession`, `InputController` and app entitlements are unchanged from 0.7.8. No event tap, global event monitor, privacy permission request or network code was added.

## Automated checks

The full `make check` passed: 27 pinned rules, 265,593 composition/session checks, 104 focus/pointer checks, local shortcut capture, mapping and shortcut checks, eight packaging checks, and the signed composition/network self-check. A malformed XML comment found by packaging checks was fixed before this successful run.

The new cases cover all 16 dedicated-key replacements, suspension/restoration, a conflict on the next key, multi-keyboard rollback, login ownership, upgrade from old Caps Lock preferences, failed restoration retries, stale legacy settings, modifier release, modified chords, two simultaneous modifiers, keys held before recording, repeat, Escape and unsupported keys. These tests use injected key events and fake devices; they do not alter actual mappings.

## Live checks

Pending installation and coordinated settings checks. The pre-install read-only check found two keyboard services, both with Caps Lock (`0x700000039`) mapped to F18 (`0x70000006d`). No other mappings were present.
