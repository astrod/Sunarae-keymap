# 0.7.1 verification — 2026-10-21 (Asia/Seoul)

## Installed build

- Installed version: 0.7.1 (27), `~/Library/Input Methods/Sunarae.app`.
- Built and installed executable SHA-256:
  `08f7cb321aed5b2b662b3860680a5e12a62b8f979f57d1e150151c3cd733c1e4`.
- The installed bundle passed strict signature verification, and its process ran from the installed path.
- The settings window showed **한영 전환 보완 (실험)** checked without a saved choice. Existing Caps Lock switching remained enabled.
- The separate focus test app and isolated input test app were closed after testing.

## Automated checks

`make check` passed:

- 27 rules matched the pinned source.
- 265,593 composition/session assertions passed.
- Menu, shortcut and Caps Lock checks passed.
- Focus-panel checks covered both directions, disabled state, immediate cleanup after synchronous notification, asynchronous cleanup, timeout, old timers, app/source changes and reentrant cancellation.
- Preference checks covered default-on, saved false, persistence and registration failure.
- Eight packaging checks passed.
- The signed self-check reported successful composition and blocked network access.

## Live checks

The settings window fit all controls and showed the default-enabled option.
The user then used the physical language-switch key several times in their usual input field and typed immediately after switching. They confirmed:

- No visible frame flicker.
- Korean input worked.
- The first character was not lost.

The automated UI key injection produced Latin text in the isolated fixture with both Sunarae and Apple's Korean input method. It therefore did not establish whether either input method composed correctly. The physical-key report above is separate from that inconclusive automation.

## Limits

These checks do not establish the long-term rate of intermittent switch failures.
The earlier diagnostic's nonactivating panel did not recover an already failed switch; actual app activation and return did. The installed option instead opens a nonactivating panel immediately after Sunarae's own source-selection call, without an app round trip.
The feature is enabled by default and can be disabled in settings. macOS's own source-menu or system-shortcut switches do not run through this path.
