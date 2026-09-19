# Local changes for Sunarae

Base: libhangul `a34aef73378c0992316861bbf13fc914ee7577d9`.
Sunarae reference: 3beol/libhangul `5244cb30b0f995ff2567ab2ac51dba3e9958a0d2`, keyboard `2noshift`.

- `hangulkeyboard.c`: register a static `2noshift` keyboard using the standard two-set mapping.
- `sunarae-combinations.h`: generated from `spec/sunarae.json`. Its 22 combinations and five initial replacements come from `hangul_combination_table_default_2` and `hangul_replace_table_2_noshift` in the reference's `hangulkeyboard.h`. The `(0, initial)` entries let the existing combination lookup handle initial replacement without adding the fork's unrelated keyboard machinery.
- `hangulinputcontext.c`: port the reference's repeated-vowel branch from `hangul_ic_process_jamo`: with no final and an initial present, a vowel equal to the stack's current entry may tense that initial. Other keyboards have no `(0, initial)` entry and stay unchanged.
- `sunarae.h`: one local snapshot helper for per-key Backspace. The Swift wrapper restores a full snapshot so undoing an initial replacement also restores the prior vowel and stack. Copies share only immutable built-in tables; this app sets no callbacks or dynamic keyboards.
- `module.modulemap`: Swift module import.

The old Dugyeob tables, direct-final shortcuts, reverse-final carry patch, and context inspection/feed helpers have been removed. The three C files retain their upstream license notices. The build sets `ENABLE_EXTERNAL_KEYBOARDS=0`; it does not include dictionaries or external layout loading. No 24-key extensions are enabled.
