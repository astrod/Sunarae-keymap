# 두벌식 순아래 0.3.0 (14) — 2026-09-13

## Change

Replaced the Dugyeob layout with the pinned 3beol `2noshift` rules. Removed the contextual I/J/K/L/U finals, reverse combinations and comma Shift state. Renamed the visible app to 두벌식 순아래 and the bundle/executable to Sunarae, keeping the registered source ID for upgrades.

Split the Swift code into key mapping, composition, session coordination, document delivery and the IMK adapter. Preserved direct text insertion/replacement, cursor/text validation, reentrancy protection, Enter passthrough and ordered deletion from 0.2.9.

## Automated checks

- `scripts/build.sh`: passed, with ad-hoc signing, strict signature verification and plist validation.
- `scripts/test.sh`: **26,680 checks, 0 failures**.
- All 11,172 modern syllables through both standard Shift keys and Shift-free Sunarae keys.
- Compound-final boundaries, repeated-vowel undo, repeated finals, Shift/Caps Lock, punctuation and repeated key events.
- Real NSTextView clients: direct and marked fallback, ordered Backspace after 1/5/30/257 repeated jamo, deletion before new text, stale selection, cleared documents, changed clients, external edits, reentrant reads/writes, paste and undo/redo.
- Enter/Space/Tab/navigation/shortcuts in direct mode finish with no added document query or write.
- `python3 scripts/generate_combinations.py --check`: all 27 rules match the pinned rules file.
- Signed app `--self-check`: `composition_ok=true network_blocked=true errno=1`.
- `scripts/test-client-calls.sh`: all fixed phrases passed. These are call counts, not screen latency measurements.

The layout file is pinned to 3beol/libhangul `5244cb30b0f995ff2567ab2ac51dba3e9958a0d2`. Expected modern syllables are computed from the Unicode syllable formula, independently of the layout's lookup table.

## Actual installed-input-method checks

User allowed keyboard/mouse use. All input went to the isolated `InputProbe.app`; no messages were sent to other apps and no live user documents were edited. Physical keys were sent through the UI tool, not pasted as Hangul and not sent through the legacy synthetic NSEvent fixture.

Installed executable SHA-256:
`0635c05eac003018d19c39a5bafa02832837ff95a0474b68e382672c55ec12ae`

Input source: `local.inputmethod.Dukkeobi`, displayed as **두벌식 순아래**, enabled.

| Test | Result |
|---|---|
| Native NSTextView, `rkk emmt rjjrr dult` | `- 까 뜻 꺾 옛` |
| CodeMirror normal, `djfuqek`, Enter, `rkk`, Enter | `- 어렵다\n- 까\n- ` |
| CodeMirror normal, five ㄹ, five Backspaces, `rkk`, Backspace, `k`, Enter | `- 까\n- ` |
| CodeMirror Vim insert mode, five ㄹ, five Backspaces, `djfuqek`, Enter, `rkk`, Enter | `- 어렵다\n- 까\n- ` |

The web snapshots reported `composing=false`, no `compositionstart` events, and Enter keydown events with `isComposing=false`. This confirms that the new Sunarae composition preserves the direct-output behavior in those tested paths.

The first attempt after moving the app to a new path produced ASCII despite selecting the source, and no Sunarae process was running. Launch Services registration was refreshed and the installed binary's server check passed; reselection then launched the IME and all above checks passed. The installer now explicitly registers the changed bundle path with `LSRegisterURL` before TIS. This observation alone does not isolate every part of macOS's registration cache.

The fixture closed after testing, its process exited, and ABC was restored. The user subsequently selected the new source. Detailed fixed-sample traces: `build/sunarae-system-test-20260913.json`. Call-count output: `build/sunarae-client-calls-20260913.json`.

## Scope and backups

The CodeMirror fixture uses the Markdown list command and Vim extension already pinned for the SilverBullet compatibility checks. This run did not edit the user's actual SilverBullet pages, test every browser/app, or measure physical-key-to-screen latency. Clients lacking document access still use marked text.

Before changes, the source and installed 0.2.9 app were backed up to:

- `build/backups/dukkeobi-0.2.9-source-20260913.tgz`
- `build/backups/Dukkeobi-0.2.9-installed-20260913.zip`

The separate NavilIME Direct project and app were not changed. The final package includes updated notices and install scripts. The installed executable is the one tested above. Updated bundled notices change the package's embedded code signature, so the signed file hashes differ; comparing temporary copies after removing signatures confirms identical executable code, SHA-256 `89398c32452196824df65e930cc1f807d824d1b72c138fc7d51b1679c264ae92`. The final package's self-check also passed. The running user's IME was not restarted just to update notice files.
