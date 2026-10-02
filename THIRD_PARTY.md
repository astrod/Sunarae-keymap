# Sources and licenses

## libhangul

- Authors: Choe Hwanjin and libhangul contributors.
- Source: https://github.com/libhangul/libhangul
- Revision: `a34aef73378c0992316861bbf13fc914ee7577d9`
- License: LGPL-2.1-or-later, in `vendor/libhangul/COPYING`.
- Three composition C files and required headers are bundled. Dictionaries and external layout loading are not built.

## Sunarae / 2noshift

- Layout author: 꼬마집오리.
- Description: https://sites.google.com/site/tinyduckn/dubeolsig-sun-alae
- Implementation reference: https://github.com/3beol/libhangul
- Revision: `5244cb30b0f995ff2567ab2ac51dba3e9958a0d2`
- License: LGPL-2.1-or-later, the same license as libhangul.
- The combination and initial-replacement data in `spec/sunarae.json` and the generated header derive from that revision's `hangul/hangulkeyboard.h`.
- The repeated-vowel branch derives from `hangul_ic_process_jamo` in its `hangul/hangulinputcontext.c`.
- `spec/sunarae-reference.txt` copies `data/keyboards_info/2set_2noshift.txt` from that revision.
- See `vendor/libhangul/CHANGES.md` for local changes. This uses the 26-key reference, not the separate 24-key variant.

The library is linked statically. Supply the complete corresponding application/library source, build scripts, and these notices when distributing the binary, or meet the LGPL's alternative requirements. These sources can be rebuilt and relinked with a modified library.

For this project's binary releases, provide a source archive of the exact release commit alongside the app download. Include `Sources/`, `vendor/`, `spec/`, `Resources/`, `scripts/`, `Makefile`, and the license notices; a full repository archive includes these. A link to a changing `main` branch is not a substitute for that version's source. Users can edit `vendor/libhangul/` and run `make build` on macOS with Xcode Command Line Tools to rebuild and relink the app. The build uses a local ad-hoc signature and does not require the original developer's signing key. Preserve the library's LGPL terms, copyright notices, and local change notices.

## Archived Dugyeob-e data

The retired layout files in `docs/archive/dugyeob-spec` are not used by the current app.
They retain their CC BY-SA 4.0 license and attribution to Sinseiki (신세기), https://ssgi.kr,
from https://github.com/Sinseiki/Dugyeob-e_keyboard at `78191b3480c9159c046cd02148783aa243fde646`.
Their license is stored beside the archived files.

## Application and test code

The Swift application, scripts, and tests written for this project use the MIT license in `LICENSE`.
Third-party files retain their own licenses. CodeMirror and its Vim extension are used only by the optional test fixture; their package versions and licenses are recorded in `Tests/WebProbe/package-lock.json` and the installed packages.

The repository's top-level MIT license does not relicense the LGPL or CC BY-SA files listed above. The original Dukkeobi contributor notice remains in `LICENSE`; Sunarae is the renamed application.
