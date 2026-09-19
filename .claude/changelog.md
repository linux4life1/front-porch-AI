## 2026-09-19 — in-place import (stableId + PNG Replace) clears looks
- **Why:** explicit byaf Replace cleared looks, but web stableId reimport skipped that flag, and PNG/JSON Replace never called the helper. Gallery stayed prior ∪ new.
- **What:** `clearGalleryLooks` on the repository. Every update-in-place in `_persistImportedCharacterCard` (stableId or forceReplace) clears `isLook` rows. Byaf apply uses the same helper. Web byaf also sets `replaceExistingLooks` on a stableId hit. Desktop single-file also records the stableId dbId. Bulk still never force-replaces; persist covers a stableId match.
- **Verified:** new `import_inplace_gallery_test` red (2 leftover looks) then green; existing byaf replace/gallery/facade suites green.
- **Files:** character_repository.import/media, byaf_import_ops, character_facade.byaf, home_page_dialogs.import, import_inplace_gallery_test
- **Commit:** this tip

## 2026-09-19 — BYAF Replace drops prior gallery looks
- **Why:** Replace A (portrait+2 looks) with B (portrait+1 look) left 3 looks. `applyByafGalleryLooks` only appended; update-in-place never cleared `avatar_images`.
- **What:** shared `replaceExistingLooks` on `applyByafGalleryLooks` (desktop + web). Clears `isLook` rows via `removeAvatar`, then applies the new pack (or none if gallery is off). Keep both / fresh import unchanged.
- **Verified:** new `byaf_replace_gallery_test` red (length 3 vs 1) then green; existing byaf suites green; analyze clean.
- **Files:** byaf_import_ops, character_facade.byaf, home_page_dialogs.import, byaf_replace_gallery_test
- **Commit:** this tip

## 2026-09-19 — BYAF gallery-all-images + web import (Lufou #251 + #261)
- **Why:** `.byaf` import only kept the first image as the portrait. Web claimed to accept `.byaf` but `importBytes` ran the PNG reader, so archives never parsed. Rawhide #263 split `home_page_dialogs.dart`, which blocked rebasing #251.
- **What:** parse every archive image (`galleryImagePaths`; first = portrait). Desktop dialog shows Portrait + N looks and an opt-out. Shared `applyByafGalleryLooks` / `deleteByafTempImages` used by single, bulk, folder, and web. Web `/api/characters/import` parses `.byaf` and adds extra images as looks (defaults match desktop: gallery, chat history, sampler settings). Library menu has a dedicated Backyard item. Existing `byaf_service_test.dart` untouched (Guard).
- **Verified:** new unit/facade/vitest files; analyze + format on edited Dart. Windows E2E 5/5 failed in `model_downloader_test` after `byaf_import_dialog_test.dart` shifted shards; the new suite itself passed on Windows 3/5. Renamed to `porch_byaf_import_dialog_test.dart` so the Model Manager suite stays on its previous shard.
- **Files:** byaf_service, byaf_import_ops, byaf_import_dialog, home_page_dialogs.import, character_facade.byaf, web CharactersPage + cardMenus, tests
- **Commit:** this tip

## 2026-09-18 — CI: retarget split-moved source pins + saveState door
- **Why:** unit job on 94bc0447 failed 10 tests. Scans still read chrome / ChatTools / session_manage / world_facade shells after the residual splits. `saveState()` lived on an extension so the debounce test override never fired.
- **What:** `CreatorState.saveState()` is a class forwarder to `_saveStateImpl`. Pins now read `world_facade.import.dart`, `chat_service_session_fork.dart`, `ChatToolsRealism.tsx`, and `home_page_chrome.actions.dart`. Contracts unchanged.
- **Verified:** the ten named suites, locally.
- **Files:** creator_state + prefs; lorebook_import, audit_fix_callsite, medium_followups, home_tap_* tests
- **Commit:** this tip
# Agent changelog

This file is **not** a project history and is **not** a place to append
session notes.

History lives in `git log`. User-facing notes live in `docs/Rawhide.md`
(nightly) and `docs/main.md` (stable). Long-form release history is
`docs/release-notes.md`.

Engineering law is [CLAUDE.md](../CLAUDE.md). Do not reconstruct past work
from an agent diary.
