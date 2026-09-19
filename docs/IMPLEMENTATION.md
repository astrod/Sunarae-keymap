# Sunarae 0.3.0 architecture

The application keeps the registered input-source ID `local.inputmethod.Dukkeobi` for upgrades, while the app path, executable, controller class, visible name and icon now use Sunarae / 두벌식 순아래. The source directory remains `dukkeobi` so existing workspace paths stay valid.

`KeyMap` maps macOS physical key positions to QWERTY ASCII. `Composer` sends those keys to the pinned `2noshift` engine. It keeps snapshots only for the current syllable's per-key undo and releases them on commit/reset. It has no comma state, contextual final mappings, timers, device checks, or external settings.

`InputSession` guards the entire operation against reentrant IMK calls. It coordinates composition with `TextDelivery`, which owns the document range and text from this session. Before any replacement/deletion, delivery checks the client identity, caret and exact text. A mismatch drops the old state. The first insertion and append use the client's current selection; later replacements use a verified range. Text remains ordinary document text in the direct path, and finishing that path performs no client query or write.

The ordered-deletion behavior from 0.2.9 stays in `TextDelivery.removeLast`. The IMK adapter deletes a verified owned range through an empty `setMarkedText` replacement. This prevents the last native Backspace from reaching a web editor after the next IMK insertion. Deleting previous app-owned content still belongs to the app. Clients without document access use marked text as before.

The C vendor contains only the former upstream base plus the Sunarae table, repeated-vowel branch, and one snapshot helper. The old direct-final and reverse-order patches are gone. The reference data and engine source revisions are pinned in `spec/sources.json`; normal builds are offline.

Installation stages a signed bundle, checks the old bundle identity, stops only the exact old executable, moves the bundle, and registers its new location with Launch Services before TIS. Registration failures restore the previous bundle path. Successful registration with an empty source list keeps the new bundle and explains how to add it after logging in again. This pending state is a successful helper exit, so installation does not roll it back. The helper reads enabled state again after enabling a source. It does not change the selected input source or grant macOS input-method approval.

Builds prepare the entire distribution in a temporary directory beside `dist`. They compile and verify both the input method and registration helper before replacing `dist`. Publication failure restores the previous directory; failed restoration preserves the backup and reports its path. Each successful build starts with an empty distribution, so removed resources do not survive in later builds. Packaging checks use isolated directories and stub registration, never the user's real input-source settings.
