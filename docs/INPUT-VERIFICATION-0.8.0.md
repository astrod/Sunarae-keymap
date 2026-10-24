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

Installed 0.8.0 (35) after the user selected ABC and approved the settings test. The previous 0.7.8 app and preferences are backed up under `build/backups/before-switch-keys.mrw8envw/`. The installed executable matches the checked build (SHA-256 `01be717194f7177eeba5625962cef013fad7f6de0a1872327fa1fa7e8314651d`), and `make diagnose` passed the version, signature and registration checks.

The settings window retained Caps Lock and the enabled focus-refresh option after upgrade. Read-only inspection found two keyboard services, both with Caps Lock (`0x700000039`) mapped to F18 (`0x70000006d`). Recording removed that mapping from both services. Recording F19 restored both Caps Lock mappings without applying the candidate; Cancel and reopening the window showed Caps Lock again. No new privacy permission prompt appeared.

The user physically recorded right Command; the settings window displayed that choice. Apply replaced Caps Lock with right Command (`0x7000000e7`) → F18 on both keyboard services. Reopening settings retained the choice. Starting another recording and pressing Escape restored right Command on both services. Recording Caps Lock and applying it then restored Caps Lock → F18 on both services, with no right Command mapping left. The settings window was closed at the end of the test.

Caps Lock recording and Apply also migrated the old preference keys to `mappedSwitchKey=capsLock` and `switchKeyOwnsLoginItem=true`. The focus-refresh and Escape settings remained enabled. No input-source switching or composition implementation changed from 0.7.8.

The UI automation tool rejects standalone modifier key presses. Right Option and right Control have injected-event coverage, but have not been physically recorded on this Mac. The live test confirmed right Command capture and HID mapping, not physical-key language switching in each target app. Those limits are separate from the passing automated checks above.
