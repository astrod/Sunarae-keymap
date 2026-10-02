# 두벌식 순아래 0.3.1 (15) — 2026-10-02

## Change

Added the input-menu preference **Esc / Ctrl+[ 누르면 ABC로 전환**. It defaults to off and persists as one Boolean. When enabled, bare Escape and Control-[ finish composition, request ABC, and pass the original event through. Other modifier combinations and the external F18 shortcut are unchanged. The option acts on received keys in all apps; it does not detect Vim modes or restore Korean on Insert mode entry.

Successful source selection also stops queued keys from entering the Korean composer. Selection of Sunarae resumes Korean even if a client reuses its old session without an activation callback. Failed selection leaves Korean usable.

The app remains sandboxed. One local Mach lookup exception, `com.apple.tsm.portname`, lets TIS notify the focused editor. Without it, a live test reported ABC as the system source while the editor still typed Korean; macOS logged a matching sandbox denial. No network, Accessibility, Input Monitoring, file-access permission, or external helper was added.

## Automated checks

- `make check`: 27 pinned rules, signed build, **268,468 composition/session/editing checks with 0 failures**, all five packaging test methods, and the signed app's self-check passed.
- `composition_ok=true network_blocked=true errno=1`.
- Added checks cover settings persistence, off/on behavior, direct/marked commit order, modifier combinations, reentrant calls, queued keys, failed selection and resuming Korean without an activation callback.
- The additional `make test` run passed all 268,468 checks and the new IMK menu test. The menu test calls IMK's real command dispatcher and verifies both check states in an isolated executable's preference domain. It does not select or register a real input source.

## Installed input method

Final installed executable and distribution executable both have SHA-256:

`b781e965fa694467afaa89177a4f28a59bd14ae9e9958b1d0ba98b11c45883d5`

The user allowed use of the keyboard/mouse. Physical key actions went to the isolated CodeMirror/WebKit probe with Vim enabled. No user document was edited.

| Final build test | Observed result |
|---|---|
| `rkk`, Ctrl-[, then `dd` | `- 까`, then an empty document; no extra Korean insertion |
| Reselect Sunarae, `rkk`, Enter, `rk` | `- 까\n- 가` |
| Escape, then `dd` | `- 까`; the second line was deleted as a Vim command |

The last two test traces contain no composition session and no extra Korean insertion after the exit shortcut. They are saved in `build/escape-verification-final-20261002.json`. The trace file contains only fixed samples entered in the test window. The fixture exited and ABC remained selected. The preference is enabled on this Mac for use; new installs still default to off.

## Limits

The fixture uses the pinned CodeMirror Markdown and Vim extensions; it is not every browser, terminal, or the complete SilverBullet app. The menu-bar UI could not be operated by the automation tool, so the menu action and check states were verified through IMK's command dispatcher instead.

An extreme automation burst, without waiting between the shortcut and following keys, still produced a final-build web trace in which the first `d` reached the browser before Control-[ and temporarily changed `가` to `강`. The later tests waited for the shortcut's UI state before sending commands and passed. The queued-key guard cannot repair an event already processed before the exit shortcut reaches the IME; this burst case is not claimed fixed. Normal physical typing at that boundary needs further use to assess. Turn the option off if this affects use.

Repeated development reinstalls also required reselecting the source and once starting the updated background app before the fixture attached to the new IME. The final app was running for the recorded tests. Installation registration and signature checks passed.

The previous installed app is retained at `build/backups/Sunarae-0.3.0-before-escape-20261002.zip`. Temporary diagnostic code was removed; the production IME does not record key events or typed text.
