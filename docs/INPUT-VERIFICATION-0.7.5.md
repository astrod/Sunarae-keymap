# 0.7.5 verification — 2026-10-23 (Asia/Seoul)

## Scope

The user asked to use the nonactivating panel approach for Korean selection as well. Version 0.7.5 (31) removes the app activation and return used in 0.7.4.

- After a successful Sunarae selection, the enabled option briefly makes a transparent, nonactivating NSPanel key. The panel closes on its key-window notification. A 200 ms timeout closes it if that notification is missing; this is not a fixed wait on the normal path.
- English selection opens no panel and cancels any pending Korean refresh.
- The switch path does not activate Sunarae, restore another app, read pointer position, hide the pointer or replay keys. It does not fall back to an app round trip.
- Context changes, cancellation, repeated switches and calls during panel opening clean up the pending panel. An old timer cannot close a newer request.
- The saved option and its default remain unchanged. No composition rule, permission or keyboard mapping changed.

## Reference and limits

This follows the selection-and-panel pattern found in the public Noctiluca CJK manager and the static inspection of Sejong98 1.0.2 recorded in the 0.7.4 report. It uses public AppKit APIs and does not copy reference code.

The earlier P trial failed to recover input after a switch had already failed. The successful Y trial activated and returned from an app, which this version no longer does. Neither trial proves that this panel-only sequence will prevent missed switches. Actual recovery, flicker and immediate typing must be checked in the user's editors.

## Automated validation

The final `make check` passed: 27 pinned rules, 265,593 composition/session checks, menu, Caps Lock and shortcut checks, 32 panel lifecycle checks, and all eight packaging checks. The signed app self-check reported `composition_ok=true network_blocked=true errno=1`.

Panel checks cover immediate and delayed key notifications, missing notifications, rejected opening, English and external context changes, repeated switches, cancellation during opening, and stale timers. These checks inject system actions; they do not change real app focus or prove physical input behavior.

## Installation

After the user switched to ABC and requested installation, the installer completed successfully.

- The previous 0.7.4 app remains in `build/backups/before-panel-only.hDXsyT/Sunarae.app`; its signature passed verification before installation.
- Confirmed installed version 0.7.5 (31), registered and enabled at `~/Library/Input Methods/Sunarae.app`.
- Installed and built executables share SHA-256 `cf67241a7604d8b8dce3a7efb8a9ebe46b3b414ccd4149a075f0c19c7780adfd`. Strict signature verification and the installed composition/network self-check passed.
- The UI launch request timed out, but a process check confirmed a new process from the installed path (PID 11519). No second launch was attempted.
- Focus refresh, Caps Lock mapping and Escape-to-ABC remain enabled. ABC remains selected for the user's next physical switch.
- Physical Korean switching, first-character input, missed-switch recovery and flicker remain unverified for this version.
