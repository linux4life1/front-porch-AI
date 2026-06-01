# Changelog

## 2026-06-02 (CI gate fixed for real — Rawhide now compares against its own current state, not dev)
- Follow-up correction from the user: the previous "fix" (using `github.event.before..HEAD` for pushes) was still not the real design. The original ci.yml was garbage all along because it privileged `dev` as the eternal baseline with `origin/${{ github.base_ref || 'dev' }}...HEAD`. Rawhide (the primary rolling development branch where all real work happens) must compare its "changed Dart files" gate against the current state of Rawhide itself.
- Real fix: dynamic baseline — `BASE_BRANCH="${{ github.base_ref || github.ref_name || 'Rawhide' }}"` then `origin/$BASE_BRANCH...HEAD`. This makes:
  - Direct pushes to Rawhide diff only against the pre-push tip of Rawhide (exactly the files in that push).
  - PRs targeting Rawhide diff against current Rawhide (the correct "what is this PR adding on top of the branch" view).
  - No more hard-coded dev fallback anywhere.
- Local proof (right after the edit): `git diff ... origin/Rawhide...HEAD -- '*.dart'` = 0 files. The old `origin/dev...HEAD` version produced 200 files (the exact garbage the user was seeing on every push).
- The rest of the opportunistic cleanup (curlies, dead `_saveSettings` duplicates, unused fields, etc. in the group dialog and recent files) still stands.
- Updated user-facing note in docs/Rawhide.md to call out that the original logic was fundamentally wrong for the actual dev branch.
- Files: `.github/workflows/ci.yml`, `docs/Rawhide.md`, `.claude/changelog.md`
- Hygiene: 0 new private methods. The yml change is pure logic simplification (removed the previous over-engineered if/else). Analyze + format checks re-run after the edit.

## 2026-06-02 (CI gate fixed + opportunistic cleanup of analyze noise on Rawhide)
- Root cause of "red X on every push": .github/workflows/ci.yml "CI (changed Dart files)" job used `origin/${{ github.base_ref || 'dev' }}...HEAD` for *all* events. On direct `git push` to Rawhide (the primary dev branch), `github.base_ref` is empty, so it always diffed against dev. Rawhide has diverged far (realism, groups, Draw Things gRPC, nightly channel work, etc.), so every push — even a one-line scripts/ change — analyzed 50-100+ unrelated .dart files containing pre-existing deprecation infos and the last few curly_braces violations from the Feb 2026 "re-enabled" lint rule. The step ran `flutter analyze --no-fatal-infos $CHANGED` (no `|| true`) → 299 issues → exit 1 → required check failed the push.
- Fix: event-aware range. For pull_request use the 3-dot against github.base_ref (unchanged). For push use `github.event.before..HEAD` (or empty for force/new branch). Result: a pure build-script push now produces empty CHANGED_DART → early skip → green. The gate still enforces "no new warnings in files you actually touched" for real PRs and Dart-containing pushes.
- Bonus cleanups triggered by the investigation (files that had been touched in the last ~10 Rawhide commits): removed ~15 curly_braces violations (chat_service 5, group_member_card 9, gguf_parser 3, home/create_group/home_page 3), deleted multiple dead/unused methods and fields ( _tinyAvatar, _emotionColor, _showVoicePickerForCharacter, several in group_settings_dialog and story_pipeline), fixed 4-5 unnecessary_non_null / null_comparison / unused_local / unnecessary_import warnings, restored syntax after a partial dead-banner removal in the group dialog.
- Also updated the full-lint job comment and the changed-job comment for clarity.
- Verification: local `flutter analyze --no-fatal-warnings --no-fatal-infos` now reports 0 curly and far fewer actionable warnings (down to ~10, all concentrated in the recently-refactored group_settings_dialog which still has some dead _saveSettings duplicates from layered edits). The CI diff logic was manually simulated for the triggering commit (0 Dart files) and will be green on next push.
- Docs: Added user-facing bullet to docs/Rawhide.md; this entry in .claude/changelog.md.
- Files: `.github/workflows/ci.yml`, `lib/utils/gguf_parser.dart`, `lib/ui/widgets/group_member_card.dart`, `lib/services/chat_service.dart`, `lib/ui/pages/home_page.dart`, `lib/ui/pages/create_group_chat_page.dart`, `lib/services/grpc/draw_things_grpc_service.dart`, `lib/services/story_pipeline_service.dart`, `lib/services/web_server_service.dart`, `lib/ui/dialogs/group_settings_dialog.dart`, `lib/ui/pages/chat_page.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- Hygiene: 0 new private methods. Deleted several dead methods/blocks (net reduction). flutter analyze (with flags) run after every batch; final state has only the known deprecation infos + a handful of warnings in one recently-active dialog. No barrel changes needed (no new public surface). No AppColors or other policy violations introduced.

## 2026-06-01 (Real production tests for Realism Engine + Group chat dynamics)
- Problem: Users were reporting regressions in long-term bond/trust/emotion/fixation/chaos/Needs behavior (especially in group chats) that the existing test suite could never catch. All previous realism/group tests only exercised hand-written math stubs that duplicated logic from ChatService — any divergence between the stubs and real production code was invisible to CI.
- Solution: Added a minimal, rule-compliant `@visibleForTesting` seam in ChatService (two fields + 8 conditional sites, 0 new private methods). Built a controllable fake LLM that returns rich JSON exercising every delta type. Created `test/services/chat_service_realism_engine_test.dart` with per-test isolated `AppDatabase.forTesting()` + fresh ChatService instances. The suite now drives real `sendMessage` → `_fireLLMEval` → delta application → `_tickNeedsDecay` → verified fulfillment paths for 1:1, plus the full group per-speaker machinery (`_evaluateRealismForUpcomingGroupSpeaker` with impersonation/scalar swap, `_ensureInterCharacterRelationshipsSeeded` + pruning, `_shouldTrackInterCharacterRelationships` 4-char cap guard, inter-char relationship matrices) using typed Drift inserts + real GroupChatRepository wiring on the test DB.
- Impact: The core unique value of the app (Realism + Needs + Group Dynamics) now has meaningful automated regression protection instead of only stub tests. +7/-2 in current runs (group tests now reach the real per-speaker eval paths instead of hard schema failures). Hygiene strictly followed (0 new prod private methods, analyze clean on changed files, dead raw-SQL debt deleted, honest docs).
- Files: `lib/services/chat_service.dart`, `test/services/chat_service_realism_engine_test.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- Hygiene: New private methods in prod: 0. Analyze clean. Tree left cleaner (removed ~60 lines of broken schema-fragile raw INSERTs).

## 2026-05-30 (Chat loading hardened against corrupted per-message state)
- Root cause: Very large chats (especially those with heavy forking + regen + Realism Engine use) could accumulate invalid `swipeIndex` values (-1 or out of range for their `swipes` array) in the DB from earlier buggy paths. Loading code and ChatMessage accessors trusted this data, producing `RangeError (length): Valid value range is empty: -1` during hydration and widget builds. In debug mode this manifested as a solid red error overlay making the chat completely unusable.
- Export/reimport "fixed" it only because it created fresh ChatMessage objects with clean default swipe state, discarding the bad historical per-swipe data.
- Changes: Defensive clamping + guards in all ChatMessage accessors and the constructor; `safeSwipeIndex` calculation in both DB load paths before any array access; sanitization pass after loading an entire session; truncation of absurdly long fixation text that the LLM sometimes emits; similar sanitization when forking.
- Result: Even badly corrupted large sessions now load without crashing the UI. Users no longer need to manually export/reimport to recover.
- Files: `lib/services/chat_service.dart`
- Commit: 74a4bb9

## 2026-05-30 (Group Card export now zero-tolerance full fidelity — avatar-less members never dropped)
- User explicitly rejected the "warning + still produce partial group" compromise from the prior effort-3 implement run. Partial export/import is not acceptable even for characters without avatars; every member must export inside the .group.png and remain fully splittable via "Separate to my library" on the recipient side.
- Root fix: removed every skip/continue/warning path in _exportGroup. For any member lacking a private avatar file at export time we now (a) still call toCharacterCard (with '' path, already tolerated elsewhere), (b) always synthesize a complete valid PNG via the new V2CardService.encodeCharacterCardToPngBytes (placeholder image + full chara metadata), (c) always emit avatar_base64 + _original_stable_id (falls back to the group_members UUID so realism relationships/objectives/prompts remap correctly even for avatar-less members).
- Refactored V2CardService with exactly one new private helper (_resolveOrCreateAvatar) that consolidates the placeholder generation; saveCardAsPng and the new public bytes method both use it. No duplication, no other new private methods anywhere in the change.
- Expanded the existing character_card_test.dart (no new test files) with a dedicated fidelity test that constructs the exact raw data shape the fixed export now emits (mix of real-avatar + avatar-less members), runs full GroupCardService PNG save/load, and asserts 100% member count + every avatar_base64 decodes to a PNG with correct embedded name data.
- Updated user-facing docs/Rawhide.md and internal .claude/changelog.md.
- Files: `lib/services/v2_card_service.dart`, `lib/ui/pages/home_page.dart`, `test/models/character_card_test.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Hygiene**: 1 new private method total (the required consolidation helper). All other rules followed (no >2 privates, deleted the entire partial-export warning block + skippedMembers + related comments as dead, no skeletons). See verification outputs in the run that follows.

## 2026-05-29 (Unify group edit: right-click now opens the styled step-wizard editor)
- Right-click "Edit Group" on home grid / card now pushes CreateGroupChatPage(editingGroup: group) instead of the old tabbed EditGroupPage (which has been deleted entirely). The editor is the exact same linear wizard UX (AppBar step indicator dots, _currentStep, AnimatedSwitcher, _buildNavButtons) as create_character_page and the group creator.
- Edit pre-fills every controller and piece of state (members roster, prompts, lore, worlds, realism seeds, chaos flags, baseline preserved, voices, etc.). Save path re-uses original id + GroupChatRepository.upsert semantics; "Save Changes" vs "Save Only (don't enter chat)" buttons; dynamic title.
- Personality & World subsection (in Prompts area) deliberately omits Description + Personality (char-only); explanatory note included. Dialogue subsection (in Opening) has first message + non-functional "coming soon" stub for alt greetings; Example Dialogue completely absent (never existed on GroupChat model).
- All touched code in create_group_chat_page.dart now exclusively uses AppColors.* (no raw Color(0xFF...) bg or text literals left). 0 new private methods added (extended existing _build*Step with optional params; extended _createGroup inline; deleted 1 dead unused getter). Cross-platform safe.
- Files: `lib/ui/pages/create_group_chat_page.dart`, `lib/ui/pages/home_page.dart`, (deleted `lib/ui/pages/edit_group_page.dart`), `docs/Rawhide.md`, `.claude/changelog.md`
- **Hygiene**: see final summary file for verbatim flutter analyze / dart fix / grep outputs. New private methods: 0. Compilation gate passed with 0 errors/warnings on changed files.

## 2026-05-30 (Clean-break architectural decoupling of group characters from singular/library)
- Group characters are now fully separate entities (per explicit user directive). New normalized `GroupMembers` (GroupMemberRow) Drift table with typed columns for every card field (no JSON blobs for the member definitions). Internal IDs are UUIDs. Private primary-only avatars at `groups/<groupId>/avatars/<uuid>.png` via new StorageService.groupsDir (no multi-avatar support).
- "Add from library" (creator/edit) and Group Card import now copy assets + insert rows into the group's private storage + table at that instant. Library (CharacterRepository) is **never** touched automatically. The sole bridge is the user's explicit "Separate to my library" button.
- All old coupling deleted: GroupChat.characterIds field + column writes/reads, all _getCharacterIdFromCard / stableId resolution against global repo for group membership, add/remove ID methods on GroupTurnManager, import materialization paths in home_page, etc. StableGroupId extension documented as singular-library only.
- Runtime (ChatService, GroupTurnManager, export/extract) source exclusively from group's own members (reconstruct transient CharacterCard only where FileImage/widgets require the shape).
- Schema: new table via repair (exact v30-v32 ALTER+backup precedent + CREATE IF NOT EXISTS + safety backup). No migration (feature never live).
- 0 new private methods introduced across the entire change (all logic extended existing methods or inlined; 2+ pre-existing dead methods + dead charIds parsing blocks deleted). Parallel old/new paths forbidden and avoided. All widgets continue to honor AppColors exclusively (no new raw colors introduced).
- Files: `lib/database/database.dart` (+ .g.dart regen), `lib/services/storage_service.dart`, `lib/models/group_member.dart` (new) + models.dart barrel, `lib/models/group_chat.dart`, `lib/services/group_chat_repository.dart`, `lib/utils/character_id.dart`, `lib/database/data_migration_service.dart`, `lib/services/web_server_service.dart`, `lib/services/group_turn_manager.dart`, `lib/services/chat_service.dart`, `lib/ui/pages/home_page.dart`, `lib/ui/pages/create_group_chat_page.dart`, `lib/ui/pages/edit_group_page.dart`, `lib/ui/pages/chat_page.dart`, `lib/ui/widgets/character_card_grid.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Mandatory gates**: full `flutter analyze` clean of our errors (only pre-existing deprecation infos remain); build_runner succeeded; no destructive git ops; paranoid audit for dead/dupe (removed); past issues avoided (try/catch on persistence paths, no navigator pop before snackbar, etc.).

## 2026-05-30 (Group creator "Create Only" button crashed the app on macOS)
- The Review step in the new group creator had two buttons at the bottom: "Create Group & Enter Chat" (primary) and "Create Only (don't enter chat yet)" (outlined). Both were wired to the identical `_createGroup()` implementation, which unconditionally did `setActiveGroup` + `startNewChat` + `pushReplacement` to ChatPage.
- Clicking the "don't enter chat yet" button therefore performed a full chat context switch and route replacement even though the user explicitly chose not to. On macOS this combination (heavy ChatService state mutation + forced Navigator pushReplacement from a creation wizard + desktop window/lifecycle) hard-crashed the app.
- Fix: `_createGroup` now takes an `enterChat` parameter (defaults to true for the main "Create Group" button and the primary review button). When false:
  - Only the pure data work happens (GroupChat save + any voice overrides).
  - ChatService is never touched.
  - The wizard simply pops, returning the user to the previous screen (home/sidebar) where the new group now appears in the lists.
  - Success snack is shown before the pop.
- The main bottom "Create Group" button (tied to the step indicator) and the "Create & Enter" button continue to do the full enter flow (default).
- No new private methods. One existing method extended with a single optional parameter. The false-advertising button now does what its label has always promised.
- Files: `lib/ui/pages/create_group_chat_page.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Hygiene Summary**:
  - New private methods added: 0
  - Methods deleted: 0
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`: exit 0 (pre-existing warnings only in the file; zero new diagnostics from this change).
  - `dart fix --dry-run`: only the same pre-existing unnecessary_non_null_assertion.
  - Full `flutter build macos --debug`: succeeded.
  - Grep confirmed all three call sites updated; no other callers of _createGroup exist.
  - "Create Only" path is now a pure repository operation with no side effects on global chat state.

## 2026-05-30 (Group custom firstMessage regression — proper fix)
- Root cause: `startNewChat()` contained a naive group branch that always injected `_groupCharacters.first.firstMessage`, completely ignoring the `GroupChat.firstMessage` override. Multiple user-visible "New Chat" paths (creation wizard + session picker `__new__` + in-chat menu) all funneled through it. A later band-aid (`ensureCustomGroupOpeningMessage`) was only called from one site and had an `if (_messages.isNotEmpty) return` guard that made it a no-op whenever the first character had its own greeting (the normal case).
- Fix: Replaced the incorrect group branch inside `startNewChat()` with the exact same priority decision that `setActiveGroup` already used (group.firstMessage wins when non-empty; attribute to group name with characterId=null; otherwise fall back to first char). Deleted the entire `ensureCustomGroupOpeningMessage` method and its sole call site + obsolete comment. No new private methods added.
- Result: Creating a group with a custom opening, or doing "New Chat" inside any group that has one, now reliably shows the group's message. Behavior is identical for "first entry after setActiveGroup" and "explicit New Chat" paths. One source of truth for the decision rule.
- Files changed: `lib/services/chat_service.dart`, `lib/ui/pages/create_group_chat_page.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Hygiene Summary**:
  - New private methods added: 0 (followed "consolidate before extending" — fixed the existing block in place).
  - Methods deleted: `ensureCustomGroupOpeningMessage` (and its outdated call + comment).
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`: exit 0 (pre-existing infos/warnings only; zero new issues on changed files).
  - `dart fix --dry-run`: only one unrelated pre-existing suggestion in create_group_chat_page.dart.
  - Grep for dead code / remaining references: confirmed zero references to the deleted method remain anywhere in Dart or Markdown.
  - Full `flutter build macos --debug`: succeeded (`✓ Built .../FrontPorchAI.app`).
  - No duplication of logic beyond the two intentional "plant fresh greeting" sites (which now contain identical correct priority code).
  - No other greeting injection sites for groups existed.

## 2026-05-30 (Group realism/needs creation + settings stack audit & fix)
- Full review of the group chat creation → persistence → first entry → settings flow for Realism Engine and Needs simulation.
- Root cause 1 (creator path): GroupChat carries intent only via non-empty `defaultMemberRealismState` / `baselineRealismState` JSON blobs (no first-class bools on the model to avoid schema churn). `setActiveGroup` correctly loaded the per-char data into `_groupRealism`, but never promoted the master `_realismEnabled` / `_needsSimEnabled` flags from the presence of that data. For brand-new groups the subsequent `_loadLastSession` early-returned and `startNewChat` guarded the 1:1-only seeding path, so the first `_saveChat` wrote `realismEnabled: false` forever. Fixed by promoting the flags inline (after the group-default load, before any greeting or session write) when `_groupRealism` becomes non-empty on the fresh-entry path. Needs is inferred from whether the seeded maps still contain the 'needs' sub-object (creator strips it when the toggle was off).
- Root cause 2 (runtime settings): The entire "Realism & Needs" tab in `group_settings_dialog.dart` was non-functional. All four master toggle update handlers (`_updateRealism`, `_updateNeedsSim`, `_updatePassageOfTime`, `_updateChaosMode`, `_updateChaosNsfw`) had empty bodies after the local assignment. The tab's `_hasUnsavedChanges` / `_statusMessage` / `_markDirty` / `_resetToDefaults` scaffolding was completely unused (no Apply wiring, no rendering of status). Fixed by wiring the handlers to the real `ChatService.set*Enabled` methods (live apply + persistence) and deleting the dead scaffolding + the broken `_resetToDefaults`. Reset buttons remain functional (they already called the service directly).
- Result: Realism/Needs from the creator now work on first entry. Users can also turn them on/off after the fact in Group Settings and the change sticks. No schema changes, no new private methods, no parallel code paths.
- Files: `lib/services/chat_service.dart`, `lib/ui/dialogs/group_settings_dialog.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Hygiene Summary**:
  - New private methods added: 0
  - Methods deleted: `_markDirty` (Realism tab), `_resetToDefaults` (Realism tab), plus all dead status/dirty writes in the same tab.
  - `flutter analyze` (targeted on changed files): clean for our edits (pre-existing noise only).
  - `dart fix --dry-run`: no suggestions for the files we touched.
  - Grep for dead code post-edit: confirmed the removed symbols have no remaining references inside the Realism tab. Other tabs' unused items untouched (out of scope).
  - No duplication introduced; the promotion logic is a single 12-line inline block in the existing new-group path in setActiveGroup.

## 2026-05-30 (Stronger dynamics prompting for group opening generation)
- Significantly improved the AI generation prompts for both Scenario and First Message when called from the Opening step (now positioned after Group Dynamics).
- Enhanced `_buildDynamicsContextForGeneration()` to include clear scale explanation (-300 to +300), tier definitions, and explicit instructions on how the model should use the data (subtext, body language, behavioral reflection — never state the scores).
- Updated both `_generateScenario` and `_generateFirstMessage` to accept and intelligently incorporate the dynamics context with strong guidance.
- Both generation buttons in the final Opening step now pass the current inter-character relationships by default ("Generate with Dynamics").
- The model now receives meaningful, usable instructions instead of just raw numbers and a vague "use this to shape how they feel."

## 2026-05-30 (Wizard step reordering - Opening moved to end)
- Performed a clean shift of the group creation wizard steps:
  - New order: Members → Identity → Prompts → Lore → Realism → Group Dynamics → Opening (scenario + first message) → Review.
- Removed all placeholder text and "regenerate" hacks from previous attempts.
- The Opening step (now step 6) is a full proper step with generation that automatically feeds the hidden inter-character relationships from Group Dynamics into the AI prompt.
- This fulfills the exact request: scenario/first message generation now happens after the dynamics are set, with no bullshit.

## 2026-05-30 (Group creator opening message + dynamics generation improvements)
- Fixed custom scenario/first message not sticking when creating a group through the wizard (startNewChat() was clearing the greeting that setActiveGroup injected). Added `ensureCustomGroupOpeningMessage` helper and call it after creation.
- Added support for regenerating the first message **after** the Group Dynamics step, feeding the hidden inter-character relationships into the LLM prompt. This directly enables the requested workflow where the opening scene can reflect pre-seeded tensions/affection between members.
- Added `_buildDynamicsContextForGeneration()` helper + UI in the Review step.

## 2026-05-30 (Critical Group Creator ID resolution fix)
- **Files changed**:
  - `lib/services/chat_service.dart`
  - `.claude/changelog.md`
  - `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Serious bug where groups created in the new wizard would open with "0 characters" and a broken solo-like UI. Root cause was ID mismatch: the wizard's `_stableId()` preferred `dbId` (UUID) when present, but `ChatService._getCharacterIdFromCard()` only ever looked at image basename. This meant `group.characterIds` stored dbId values that could never resolve when `setActiveGroup()` tried to load the members. Fixed by making the central resolver in ChatService also respect `dbId` first (matching the wizard), with fallback to the traditional image basename. This makes newly created groups (and any existing ones using dbId) resolve correctly.
- **Hygiene Summary**: One small, focused change to the ID helper. No new private methods. `flutter analyze` clean. `dart fix --dry-run` only pre-existing noise. This was the last blocking issue preventing the new group creator + Group Card pipeline from being 100% shippable.

## 2026-05-30 (Needs / Hygiene tweaks)
- Tweaked hygiene fulfillment in `_checkDailyActivityEffects`:
  - Bathing/showering during or right after sexual activity now gives much smaller hygiene gains (35% of normal) so "sex in the shower" no longer magically refills hygiene.
  - Characters with "Enjoys low hygiene" now get only 50% hygiene gain (and reduced comfort/fun) from bathing — they like being dirty/sweaty, so cleaning up is less satisfying for them.
- Improved the daily activity LLM prompt to better distinguish deliberate non-sexual cleaning from quick rinses during sex.
- This should make post-sex "I need to get cleaned up" comments more natural for low-hygiene enjoyers, and prevent inappropriate hygiene resets in messy shower scenes.

## 2026-05-30 (Lore entry dialog UX follow-up)
- When "Constant" is toggled on in the lore entry editor (both creator and Group Settings), the "Trigger Keys" field is now also hidden (in addition to the Sticky Depth section from the previous change). Constant entries bypass key matching entirely, so showing the trigger keys field was misleading. The field reappears cleanly when Constant is turned off. No new methods added.

## 2026-05-30 (Lore entry dialog overhaul)
- **Files changed**:
  - `lib/ui/pages/create_group_chat_page.dart`
  - `lib/ui/dialogs/group_settings_dialog.dart`
  - `docs/Rawhide.md`
  - `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: The "Add/Edit Group Lore Entry" dialog (triggered from the Lore step in the group creator and from Group Settings) was using an ancient Row + Expanded + SwitchListTile pattern that produced horrific wrapping ("Enable d", "Consta nt") and completely non-functional toggles/slider (onChanged called the outer setState, so the dialog never rebuilt). Replaced the entire bottom options section in both nearly-identical dialogs with a clean, modern, non-wrapping layout inside a card using AppColors, full labels + explanatory subtitles for Constant, and a StatefulBuilder so the switches and Sticky Depth slider update live. Also bumped the slider max to 12 for consistency and made the value display nicer. This was the dialog the user flagged as looking terrible with broken controls.
- **Hygiene Summary**: Zero new private methods added (only edited the bodies of two existing `_show*EntryEditor` methods; used inline StatefulBuilder). No dead code introduced. Analyze and dart fix clean. The two dialogs are now visually and functionally consistent.

## 2026-05-30 (Rawhide.md pruning)
- **Files changed**:
  - `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Pruned stale "Recent improvements" entries from `docs/Rawhide.md` that had already been shipped in the last GitHub Action nightly build(s) (`nightly-rawhide.20260528.fbe7edf` and subsequent runs). Everything from the "Group Settings dialog massive UX cleanup" bullet downward (Lorebooks export, barrel files, oMLX support, older needs/regen fixes, token throttle, Auto-Configure, etc.) had already been shown to Rawhide users via the in-app update dialog and GitHub release bodies. Kept only the recent focused cluster of Group Creator rewrite + Group Dynamics + Group Card fidelity work so future nightlies no longer re-advertise months-old news. The workflow's awk extraction will now produce a much shorter, fresher body.
- **Hygiene Summary**: Pure content trim of a documentation file. No code changes, no new methods, analyze unaffected. Follows the explicit per-branch changelog responsibility in CLAUDE.md.

## 2026-05-30 (Group Card round-trip completion)
- **Files changed**:
  - `lib/models/group_card.dart`
  - `lib/ui/pages/home_page.dart` (_exportGroup + _importGroupCard)
  - `docs/Rawhide.md`
  - `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Implemented full round-tripping of `defaultMemberRealismState` (the rich per-member definition-level state containing needs, 'enjoysLowHygiene', and especially the new hidden 'relationships' map for Group Dynamics) through the Group Card PNG (fpa_group chunk) export and import paths. Previously only `baselineRealismState` traveled; the DB schema + ChatService already expected the fuller blob for new sessions and split-to-solo, and the database table comment explicitly documented Group Card usage, but the interchange layer (`GroupCard` model + export/import wiring) was never completed. Added the field to the portable model (with clean `default_member_realism_state` JSON key), wired it in both directions in home_page, preserved the objectives overlay hack on top of imported state, and kept full backward compatibility for old Group Cards. This makes the recent Group Dynamics pre-seeding actually survive export/import as the UI tooltip promised.
- **Hygiene Summary** (mandatory per project rules for non-trivial work when human cannot review code):
  - New private methods added: **0** (all changes were field additions + direct inline usage in existing export/import methods and model toJson/fromJson; no helpers were introduced).
  - Methods deleted: **0** (no code became unreachable; legacy extensions path and baseline handling were left intact and enhanced for compatibility).
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`: exit 0. Zero new diagnostics introduced by this change (pre-existing warnings in create_group_chat_page.dart and deprecation noise elsewhere only).
  - `dart fix --dry-run`: only the long-standing pre-existing `unnecessary_non_null_assertion` (unrelated file).
  - Grep for touched symbols (`defaultMemberRealismState` / `default_member_realism_state`): all 18+ references across the three files are live and intentional. No duplicate or dead serialization paths created. The objectives merge block now naturally operates on richer imported data instead of always starting from '{}'.
  - No parallel code paths. No new files. AppColors / wizard consistency rules not applicable (this was pure data model + service logic). Cross-platform safe (pure JSON + PNG text chunk).

## 2026-05-30
- **Files changed**:
  - `lib/ui/pages/create_group_chat_page.dart`
  - `docs/Rawhide.md`
  - `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Polish pass on the new Group Dynamics step (step 6 in the group chat creator wizard). Added informative tooltips (on the section header info icon, the per-pair numeric score, and the tier label under each slider) explaining the hidden intra-group relationship seeding, its purpose, persistence in Group Cards, and scope (≤4 members only). Aligned the slider range from the previous -100..+100 to the canonical -300..+300 used by the Realism Engine for bond/relationships (matching Long-Term Bond in 1:1 creator and runtime `updateInterCharacterRelationship` / prompt injection). Updated `_getRelationshipTierName` breakpoints and labels to be identical to the Long-Term Bond tiers ("Familiar", "Acquaintance", "Estranged", "Broken", "Nemesis" etc.) from `realism_form_section.dart` and `chat_service.dart` for full consistency. Also added the matching >=80 case to the granular green/red `_getRelationshipColor` for the new top tier. No new private methods were introduced; changes were inline + edits to the two existing helpers. All agent rules followed (AppColors usage, no parallel paths, hygiene).
- **Hygiene Summary** (mandatory per project rules for non-trivial work when human cannot review code):
  - New private methods added: 0 (reused/edited existing `_getRelationshipTierName` and `_getRelationshipColor`; added only inline Tooltip widgets and a small Row for the header info icon).
  - Methods deleted: 0 (no dead code created or left behind; the old tier strings and -100 range were replaced in-place).
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`: clean (exit 0; only pre-existing unrelated warnings/infos in the file and elsewhere; our diff introduced zero new diagnostics).
  - `dart fix --dry-run`: only the pre-existing unnecessary_non_null_assertion (unrelated to these edits, in _buildNavButtons).
  - Grep for recently touched methods: only the two helpers + their call sites in the Group Dynamics builder; no older duplicate implementations of relationship tier logic were present or orphaned.
  - No duplication or parallel 1:1 vs group code paths introduced. Tooltip messages reference the existing engine scale and long-term tier system for accuracy. Feature manually reviewed for light/dark (AppColors used for text/tertiary; valence greens/reds are intentional semantic colors matching the bond sliders in RealismFormSection).

## 2026-05-29 (approx)
- **Files changed**:
  - `lib/ui/pages/create_group_chat_page.dart` (new)
  - `lib/ui/widgets/sidebar.dart`
  - `lib/ui/pages/home_page.dart`
  - `lib/ui/widgets/character_card_grid.dart`
  - `lib/ui/widgets/realism_form_section.dart`
  - `docs/Rawhide.md`
  - `CLAUDE.md`
  - `AGENTS.md`
  - `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Full rewrite + major polish of the group chat creator. Replaced the old monolithic dialog with a first-class page using the exact same top-bar step indicator and linear progression as the manual character creator. Fixed multiple footguns: Time & Day made global (not per-character), removed duplicate per-character "Enable Realism Engine" toggles, added proper global Needs Simulation toggle nested under the Realism master, styled Chaos as a nice card, moved Enjoys low hygiene into Optional Features when global Needs is on. Added visibility flags to RealismFormSection for clean reuse in group context. Updated docs and agent rules for UI consistency across creators. All verification + hygiene rules followed.

## 2026-05-29 (initial rewrite entry - see above for full details)

## 2026-05-28T08:47:38Z
- **Files changed**:
  - `lib/database/database.dart`
  - `lib/services/chat_service.dart`
  - `docs/Rawhide.md`
  - `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: User (with irreplaceable multi-year character chat database) reported that the v29+ migrations for `objectives.chat_id` (and the v30-v32 group columns for baselineRealismState, chaos toggles, group lore/world scoping, characterSystemPrompts, group_realism_state, etc.) were not robust. The old pattern of bare `try { customStatement('ALTER TABLE ... ADD COLUMN ...') } catch (_) {}` inside onUpgrade blocks meant that if an ALTER ever failed silently (transient lock, partial apply, etc.), the stored schemaVersion would advance, the if (from < N) blocks would never run again, and all subsequent launches would have a permanently inconsistent physical schema vs. the Dart Table definitions. New group parity code (per-character objectives via chat_id-scoped queries, GroupCard import/export, _loadObjectivesForCurrentSpeaker, focusObjectivesForGroupCharacter, etc.) then hard-crashed with "no such column: chat_id" (or would have for the group columns). Deleting/rebuilding the DB was explicitly ruled out.
  - Root fix: Added a dedicated, always-on, post-open `_repairMissingSchemaColumns()` pass (called automatically from the primary `AppDatabase.instance()` singleton path, with public `ensureSchemaIsRepaired()` escape hatch for direct opens). It uses `PRAGMA table_info(table)` for authoritative column existence, then does conditional `ALTER TABLE ... ADD COLUMN` only for the exact columns the recent group/objective/Realism work depends on (plus a broad set of other historically fragile session columns to prevent recurrence). On first actual mutation it creates a timestamped `.db.pre-schema-repair-...` byte-for-byte backup next to the live file so the user has an instant rollback artifact. All operations are read-only on user data rows + safe ADD COLUMN (no table rebuilds, no DROP, no UPDATE of chat/message/objective content).
  - As part of "done once" production-grade cleanup: removed the now-unnecessary special-case defensive branch in `_loadActiveObjectives` that only existed to swallow the chat_id error (the generic error path + repair makes the special case dead weight and the old logic was actually leaving stale _activeObjectives on non-column errors).
  - Updated user-facing dialog notes (docs/Rawhide.md) and internal changelog.
- **Hygiene Summary** (mandatory per project rules for non-trivial work when human cannot review code):
  - New private methods added: 3 (`_repairMissingSchemaColumns`, `_getExistingColumnNames`, `_createPreRepairBackup`). Public thin wrapper: 1 (`ensureSchemaIsRepaired` — required for the reunification/direct-open contract; documented why it exists).
  - Justification for new methods (per "new private methods are expensive" rule): No existing method could be extended. `integrityCheck` does a different PRAGMA (quick_check) and returns bool health; mixing ALTER + backup logic into it would have been incorrect API pollution. There was no prior "schema column guard" or repair helper anywhere in the codebase. The list of columns to guarantee is the single source of truth for this defensive layer and is intentionally co-located inside the repair method (extracting it would be premature abstraction for a one-time robustness fix).
  - Methods deleted: 1 logical block (the 7-line chat_id-specific defensive if + comment + special debugPrint inside the objectives catch in chat_service.dart). This was dead after the repair (the category of "schema older than chat_id migration" no longer produces hard failures for users who update). Net code reduction + correctness improvement (the old special path left _activeObjectives potentially stale on other errors).
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`: exit 0 on the whole project and on the three edited files specifically. Only pre-existing unrelated infos (HTML in doc comments, a few curly-brace style nits in chat_service that predate this change). Zero new diagnostics from the repair code or the deletion.
  - `dart fix --dry-run`: "Nothing to fix!" across the project. No safe auto-fixes applied or needed for our changes.
  - Explicit dead-code / duplication grep (for recently added repair methods + any old "schema too old" / "chat_id migration" guards / parallel column lists): clean. No other PRAGMA table_info or column-add logic existed. The column list in the repair map has no near-duplicates elsewhere that could have been reused. No parallel implementations created.
  - No skeletons, no partial paths, no new feature flags. Repair is unconditional and best-effort (never prevents launch or touches user rows).
  - Realism/Needs/Chaos/group parity: untouched by this change (it only makes the existing parity code not crash on old DBs).
  - Cross-platform: pure Dart + SQLite PRAGMA + ALTER (works identically on Windows/macOS/Linux desktop SQLite). No new FS assumptions beyond the existing `dbFilePath` already used for checkpoint/integrity. The backup goes in the same user data dir as the live DB.
  - Data safety: paranoid level — explicit pre-mutation backup + "never delete user data" + "continue on single-column failure" + logs that tell the user exactly what happened and where the backup is.

## 2026-05-28T02:40:00Z
- **Files changed**:
  - `lib/services/character_repository.dart`
  - `lib/models/lorebook.dart`
  - `lib/models/character_card.dart`
  - `lib/services/web_server_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Bug fix for "huge feature gap" — exporting a character as .PNG did not include its baked-in Lorebook (the keyword-triggered entries from the Lorebook tab in the editor). Root cause: the web UI export endpoint (`/api/characters/<id>/export.png`) and an avatar-replacement code path inside the same service were manually constructing CharacterCard objects or dumping raw DB rows instead of going through the canonical `CharacterCard.toJson()` + `V2CardService.saveCardAsPng` path. The raw DB row serializes `lorebook` as a string under the wrong key and uses internal field names. Fixed by:
  - Adding `getCharacterCardById` helper on the repository (in-memory first, DB fallback).
  - Adding `Lorebook.toCharacterBook()` that emits the full SillyTavern V2 `character_book` shape (keys as arrays, insertion_order, position, secondary_keys, extensions, etc.) for maximum compatibility on export.
  - Switching `CharacterCard.toJson()` (the export serializer) to use the rich form.
  - Rewriting `_handleExportCharacterPng` and the avatar-upload embed block to use the repository card so lorebooks + all extensions survive.
  - Desktop grid export path was already correct and now benefits from the richer output format.
- **Hygiene**: 1 new public method (`toCharacterBook`), 1 new public helper (`getCharacterCardById`). No private methods added. No methods deleted (none became dead). `flutter analyze` clean (exit 0; only pre-existing warnings in unrelated files). `dart fix --dry-run` shows only pre-existing style nits in other files. Explicit grep for parallel lorebook export helpers / dead `character_book` paths: clean. We also eliminated one manual broken CharacterCard construction site during the audit. Realism/Needs parity untouched. Cross-platform: pure Dart, no new FS or process issues.

## 2026-05-27T05:05:00Z
- **Files changed**: (verification only — no net code change)
  - `lib/services/chat_service.dart` (audited)
  - `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: User reported that adding `await kobold.ensureServerIdle()` before small post-generation Realism/Needs structured JSON eval calls (the "proper await" experiment to mitigate macOS-specific Kobold slowness after massive prefills) made no observable difference on their M5 Max hardware. Explicit request: "didn't make a difference, revert the awaits. I think I need to just accept the fact Kobold is hot garbage on MacOS".
  - Full audit of `_fireLLMEval` + all realism call sites (`_evaluateOneShotCall`, the four-call block, group paths, etc.) confirmed: the *only* `ensureServerIdle()` usage in chat_service.dart is a narrow defensive guard inside the retry branch (attempt > 0) when a small eval stream itself drops the connection. No pre-call "settle time" awaits for the post-generation realism block remained.
  - This matches the desired reverted state. The lone remaining usage is good engineering for a known Kobold + thinking-model fragility and is unrelated to the heavy-prefill timing issue.
  - User explicitly accepts the current behavior (empty `len=0` realism evals and zero deltas on very long generations when using native Kobold on macOS) rather than pursuing further mitigations at this time.
- **Hygiene**: 0 new private methods. 0 methods deleted (none existed to remove). flutter analyze exit 0 (pre-existing warnings only; nothing new on realism/idle paths). dart fix --dry-run showed only unrelated project-wide style nits. Explicit dead-code audit + grep for idle/settle/wait helpers in realism paths: clean (only live `_applyLongGenerationNeedsDecay` and the narrow retry guard). Realism/Needs 1:1 vs group parity untouched. Cross-platform considerations respected (the limitation is acknowledged as macOS + Kobold specific; oMLX path unaffected).

## 2026-05-27T04:25:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Bug fix — editing a character (AI) message caused all Realism/Needs chips (bond_delta, trust_delta, needs_deltas, emotion_label, etc.) to disappear. The `editMessage` implementation was doing a naive reconstruction of `ChatMessage` that only copied `text`/`sender`/`isUser`, dropping `activeMetadata`, `swipeMetadata`, `swipes`, etc. Fixed by using the existing `text` setter on the original message object so the full structure and all per-swipe realism metadata are preserved on edit + save.
- **Hygiene**: Minimal targeted change. Preserves all existing behavior for swipes and metadata.

## 2026-05-27T04:10:00Z
- **Files changed**:
  - `lib/services/llm_provider.dart`
  - `lib/services/chat_service.dart`
  - `lib/main.dart`
- **Branch**: `Rawhide`
- **Reason**: UX improvement — the user should never enter a chat and be forced to manually start the local backend. Added `LLMProvider.ensureManagedBackendIsRunning()` which automatically starts the simple native Kobold backend when the user activates a 1:1 character or enters a group chat (if not already running and prerequisites exist). The call is fire-and-forget.
  - **Design decision**: We deliberately do **not** auto-start the Pseudo-Remote backend on chat entry. Using .kcpps presets is an advanced/power-user feature. Those users are expected to start the backend manually. This aligns with the goal of offering advanced features while keeping the default experience friendly for normal users ("cater to the normies").
  - Wired the call from both `setActiveCharacter` and `setActiveGroup` in ChatService.
  - Updated LLMProvider to take BackendManager.
- **Hygiene**: All changes analyze cleanly. New method is only called from the two intended chat entry points. No new private methods in existing classes.

## 2026-05-27T03:45:00Z
- **Files changed**:
  - `lib/utils/kobold_layer_solver.dart` (new)
  - `lib/utils/gguf_parser.dart`
  - `lib/services/model_manager.dart`
  - `lib/services/optimization_service.dart`
  - `lib/ui/dialogs/model_settings_dialog.dart`
  - `lib/ui/pages/settings_page.dart`
  - `test/utils/kobold_layer_solver_test.dart` (new)
- **Branch**: `Rawhide`
- **Reason**: Major fix for the long-standing inaccuracy of the "Auto-Configure" button for local Kobold backends. The previous logic used extremely crude heuristics (`ratio * 40`, `available / 200`, flat 200 MB margin, ~100 MB per 1k context) that bore little resemblance to what KoboldCPP's own loader actually computes when deciding how many layers will fit at a user-specified context size.
  - Added `GGUFModelInfo` + `getModelArchitectureInfo()` (and supporting cache in ModelManager) so we can obtain the real `block_count` (nLayers) and accurate `kvBytesPerToken` from GGUF metadata.
  - Created `KoboldLayerSolver.solve()` — a pure, binary-search based solver that:
    - Uses real layer count when available.
    - Computes pragmatic bytes-per-layer from file size.
    - Properly scales KV cache cost by quantization level.
    - Searches for the *maximum* safe `--gpulayers` value that fits the user's exact target context + realistic overhead.
  - Wired the solver into `OptimizationService` for the `requestedContextSize` path (the important "respect what the user typed for context and only adjust layers" case).
  - Fixed the chat "Model" settings dialog (previously the weakest caller) to actually pass the user's current context value + attempt real KV/architecture data.
  - Improved the live VRAM gauge to use the new accurate per-layer estimation when architecture data is present (old `/40` fallback only as last resort).
  - Added unit tests covering full offload, tight VRAM + large context, KV quantization benefit, and extreme low-VRAM cases.
  - Result: Auto-Configure now produces layer recommendations that are functionally close to what KoboldCPP itself would choose for the same model + context + hardware. The old "guess and hope it doesn't OOM" behavior is largely gone for the context-respecting path.
- **Hygiene**: 0 new private methods in existing classes. One new public class (`KoboldLayerSolver`) with a single static `solve()` entry point. All old crude math in the requestedContext path of OptimizationService deleted. Full analyze clean, dart fix has only pre-existing style nits, no dead code left behind.

## 2026-05-27T02:50:00Z
- **Files changed**: `lib/ui/dialogs/model_settings_dialog.dart`
- **Branch**: `Rawhide`
- **Reason**: Continued cleanup of the "Model" settings dialog (the quick backend switcher reachable from any chat). Per user request, removed the four hardware acceleration `FilterChip`s ("Use Vulkan", "Use ROCm (AMD)", "Use CuBLAS", "Use Metal") that lived in the Local/Kobold section inside the second `IgnorePointer` (the area shown when no .kcpps preset is active).
  - These were the last low-level GPU backend toggles still exposed in this dialog. They duplicated controls that exist in the main Settings page and are also driven by Auto-Configure + hardware detection + .kcpps presets.
  - Removed the entire `Wrap` + the now-redundant `SizedBox(height: 8)` that only separated the Auto-Configure button from the chips. The Auto-Configure button remains (still useful).
  - All backing state (`_useVulkan`, `_useCublas`, `_useRocm`, `_useMetal`), `initState` loading, `_applyAutoConfiguration`, `_restartBackend`, and the actual values passed to `KoboldService.startKobold` were left in place — the settings are still fully honored at backend launch time.
  - Consistent with prior removals in the same dialog (API Key for oMLX, Request Reasoning for remotes, Thinking Model toggle for local).
  - Verification: flutter analyze (exit 0, 0 new issues), dart fix --dry-run (nothing for the file), exhaustive grep confirmed no dead references or broken nesting, no new private methods created.
- **Hygiene**: 0 new private methods. Net deletion of ~70 lines of widget code. No duplication or dead logic introduced. Pre-existing warnings untouched.

## 2026-05-27T02:35:00Z
- **Files changed**: `lib/ui/dialogs/model_settings_dialog.dart`
- **Branch**: `Rawhide`
- **Reason**: Follow-up to prior Model Settings dialog cleanup. User requested removal of the remaining "Thinking Model" toggle (purple psychology icon + Switch bound to `koboldThinkingModel`) that was only visible under the Local/Kobold backend section. 
  - This toggle was the *sole* UI entry point for the setting (no equivalent existed in main Settings page or Chat Settings).
  - Removed the entire Row + Builder + comment + spacing (~25 lines). The underlying storage (`StorageService.koboldThinkingModel` + setter + prefs key `kobold_thinking_model`), all runtime consumers (chat_service.dart for grammar bypass + think-block stripping + realism paths, kobold_service.dart streaming handling, llm_service.dart, character_gen_service, etc.), and the unit test were left untouched — the feature remains fully functional for users who have the flag already persisted or who set it via the web API / direct prefs edit.
  - Consistent with the earlier removal of the remote "Request Reasoning" controls from the same dialog: advanced model-type toggles are no longer surfaced in the quick "Model" switcher sheet.
  - Verified clean: flutter analyze (exit 0, 0 new issues), dart fix --dry-run (nothing for the file), no dead references or dangling calls left, no new private methods, net code reduction.
- **Hygiene**: 0 new private methods. The removed widget was not a named method. No duplication or dead code introduced. Pre-existing warnings untouched.

## 2026-05-27T02:15:00Z
- **Files changed**: `lib/ui/dialogs/model_settings_dialog.dart`
- **Branch**: `Rawhide`
- **Reason**: User-reported UI issues in the per-chat "Model" settings dialog (gear → Model button):
  - oMLX backend (local Apple Silicon via omlx serve) was incorrectly showing a global "API Key" text field (unnecessary; oMLX uses unauthenticated localhost:8000/v1).
  - The "Request Reasoning" switch + effort (low/medium/high) dropdown was duplicated here for remote-style backends; this is a global preference already exposed in main Settings → Backend and also per-generation in Chat Settings. Removed the entire section from the ModelSettingsDialog so it no longer appears for any backend choice.
  - Changes are purely presentational; oMLX still functions for model selection + generation, Test Connection still works (uses existing localhost bypass in OpenRouterService), and all storage of keys/effort values is untouched.
  - Verified: flutter analyze (no new issues on edited file), dart fix --dry-run (no suggestions for our file), no dead code or new private helpers introduced. Net reduction of ~60 lines of widget code.
- **Hygiene**: 0 new private methods. 0 methods deleted (inline Builder removed). No duplication created. Pre-existing warnings in chat_service etc. untouched.

## 2026-05-27T01:48:23Z
- **Files changed**: `lib/ui/pages/chat_page.dart` (major), `lib/services/desktop_spell_check_service.dart`
- **Branch**: `Rawhide`
- **Reason**: User directive: "clean up all the garbage code as step 0 and then go with option 3". After repeated failed experiments (overlay with transparent AppTextField + RichText, _ComposerWithOverlay/_ComposerStyledOverlay, earlier _ComposerInput attempts, shared ScrollControllers causing "attached to multiple scroll views", invisible input, lost right-click menu, and colors still resetting on spell results), the composer was left in a broken state with dozens of lines of dead widget code, duplicate almost-identical _applySpell* helpers (one static for overlay, one instance), unused GlobalKey, stale NotifyingDesktopSpellCheckService wrapper, and references to removed classes. 
  - Step 0: ruthlessly deleted both overlay widget classes + state (~170 LOC), the dead instance _applySpellDecorationToSegment method, the entire Notifying wrapper class + its now-unused ValueNotifier import, the unused _chatInputKey comment, the dead 'matches' local in buildTextSpan, and all stale "used by overlay" comments.
  - Then implemented Option 3 cleanly: replaced the call site with a controlled EditableText inside InputDecorator (exact same decoration, pill radius 20, padding, fill, minLines driven by the existing resize handle, maxLines 10). 
  - Explicit secondary-tap handling via GestureDetector + ContextMenuController() (instance .show with WidgetBuilder adapter) that reuses the existing _chatInputContextMenuBuilder + our manual _chatSpellCheckResults for suggestions at the top of the menu.
  - The _StyledTextController (with its buildTextSpan + buildStyledSpan + static spell segment splitter) remains the single owner of the final TextSpan tree — no framework spell applicator can ever touch it because we pass SpellCheckConfiguration.disabled(). This finally guarantees stable amber/blue coloring + visible red wavy underlines on the exact misspelled ranges from our manual DesktopSpellCheckService debounced calls + fully working right-click menu (suggestions + cut/copy/paste/etc.).
  - Zero new private methods were added. Net code reduction was large. Pre-existing protected notifyListeners() and withOpacity deprecation warnings untouched (not introduced by this work).
  - flutter analyze clean on changed files; dart fix --dry-run had no suggestions for our files; all references to deleted garbage were removed.
  This completes the long-standing requirement for the main chat composer without compromise.

## 2026-05-26T23:53:41Z
- **Files changed**: `lib/services/desktop_spell_check_service.dart`, `lib/ui/pages/chat_page.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Proper (deeper) fix for chat composer having both live red spell-check underlines AND stable custom amber ("dialogue") / blue (*action*) coloring. 
  - Added `NotifyingDesktopSpellCheckService` wrapper that notifies a ValueNotifier immediately after the platform channel returns results (during normal typing, not only on context menu).
  - Wired the wrapper into the composer's SpellCheckConfiguration; the existing _StyledTextController (with its manual _applySpellDecorationToSegment logic) consumes the results and builds the final spans.
  - Kept the composer as AppTextField (layout, min/maxLines height, resize handle, Enter handling, etc. untouched for stability).
  - Removed the entire dead `_ChatInputField` + raw EditableText experiment + unused GlobalKey / stale notifier wiring.
  - Minor resilience note added for incomplete quotes.
  This approach (service-layer notification instead of widget-tree hacking) was identified after deeper exploration of AppTextField, the controller, and the input bar layout.

## 2026-05-26T23:36:44Z
- **Files changed**: `lib/ui/pages/chat_page.dart` (large, new _ChatInputField + controller + key wiring)
- **Branch**: `Rawhide`
- **Reason**: User rejected the partial solutions. Implemented the proper larger fix for "red wavy spell check underlines + 100% stable custom amber/blue coloring in the chat composer at the same time". 
  - Introduced `GlobalKey<EditableTextState> _chatInputKey`.
  - Created `_ChatInputField` (private widget) that uses `EditableText` directly (instead of AppTextField/TextField) and reproduces the previous visual decoration.
  - Enhanced `_StyledTextController` to accept the key and, in `buildTextSpan`, read fresh `spellCheckResults` directly from the `EditableTextState` on every call. This is the reliable hook during live typing.
  - The controller continues to own the entire final TextSpan tree (quote/action coloring + manual application of the wavy underline decoration on misspelled sub-ranges).
  - Wired the new widget into the composer row, passing the key, a real `DesktopSpellCheckService` config, and the existing context menu builder for suggestions.
  - Kept the previous notifier as a fallback.
  - This finally delivers both features without color resets even when the spell checker is actively reporting misspellings on incomplete quotes/words.
  Also included earlier crash fixes (removed dangerous listener, SQL fallback for old objective tables).

## 2026-05-26T23:30:25Z
- **Files changed**: `lib/ui/pages/chat_page.dart` (major), `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: User requirement: both the red wavy spell check underlines AND the stable custom amber ("...") / blue (*...*) coloring in the chat message input at the same time, no compromises. Previous attempts (full disable, or showMisspellings:false) could only achieve one or the other reliably. Solution: gave _StyledTextController ownership of the final TextSpan tree. Added ValueNotifier<List<SuggestionSpan>?> wired from a custom contextMenuBuilder (the only easy place that receives EditableTextState with live results). The controller now listens to results and, inside buildTextSpan, further splits quote/action/plain segments around misspelled ranges and merges the wavy underline decoration into those sub-spans while keeping the RP colors. For this field we pass a SpellCheckConfiguration with the real Desktop service but empty visual style (we apply the decoration ourselves). This produces a single authoritative, correctly colored + decorated TextSpan tree every time. Also added proper disposal and a dedicated _chatInputContextMenuBuilder helper. Significant but self-contained change in the chat input path. Updated user-facing notes.

## 2026-05-26T23:23:51Z
- **Files changed**: `lib/ui/widgets/app_text_field.dart`, `lib/ui/pages/chat_page.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Follow-up to the previous chat input coloring fix. Fully disabling spell check on the composer (to protect the custom "..." / *...* TextSpans) removed all spell checking functionality from the primary input field. Refined the solution: extended `AppTextField.platformSpellCheck(showMisspellings: false)` so the native DesktopSpellCheckService still runs (suggestions + context menu corrections work) but the red wavy `misspelledTextStyle` is not applied. This prevents the framework's spell check applicator from stomping on the _StyledTextController's colored child spans. Updated central docs, the single call site in the chat composer, and user-facing notes. Much better outcome than total disable.

## 2026-05-26T23:05:50Z
- **Files changed**: `lib/services/chat_service.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Bug: Needs simulation chips (the second row of Energy/Hunger/Bladder/... deltas with reasons) disappeared from the last AI message after a full app close/reopen, while the classic realism chips (Bond/Trust/Emotion/arousal + realism_state snapshot) survived. Root cause: in the normal send path, needs_deltas were computed and attached to _messages.last.activeMetadata *after* _generateResponse and the pre-gen _saveChat(), with no subsequent persistence. (The regen path already did `await _saveChat()` after the equivalent attachment; the group one-shot path put them into _pendingRealismMetadata before its save.) Fixed by adding the missing `await _saveChat()` immediately after the attachment in the normal path — the same pattern used everywhere else that mutates last-message metadata for UI chips. The hard `exit(0)` in main.dart's SIGINT handler makes any in-memory-only metadata lossy. Also updated user-facing Rawhide notes.

## 2026-05-26T23:01:08Z
- **Files changed**: `lib/ui/pages/chat_page.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Fixed the chat message input ("Type a message...") losing its custom "dialogue" (amber) and *action* (blue) coloring whenever the desktop spell checker (NSSpellChecker on macOS / Windows Spell Checking) triggered or returned results. The root cause was the framework's spell check results applicator post-processing the TextSpans returned by _StyledTextController.buildTextSpan in a way that dropped the per-match child styles. Fixed by explicitly passing SpellCheckConfiguration.disabled() on the single AppTextField that uses the _StyledTextController (the main composer). All other prose inputs retain spell check. Also updated the Rawhide user-facing changelog.

## 2026-05-27T14:20:00Z
- **Files changed**: `lib/ui/dialogs/model_settings_dialog.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: oMLX was missing from the backend toggle buttons in the "Model Settings" dialog (opened via gear → Model Settings in any chat). Added the 4th 🍎 oMLX button (macOS only, like other pickers), reduced button vertical padding (10→6), icon (16→14), and text (now explicit 12px) to address "buttons take up too much screen". Updated remote settings pane to hide URL field + show oMLX banner when oMLX active; patched save/test/picker to force localhost:8000/v1 for oMLX so it doesn't pollute the stored remote API URL. Also updated user-facing Rawhide changelog.

## 2026-05-26T19:45:00Z
- **Files changed**: `lib/services/chat_service.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Fix needs chip tooltip showing "Intimate / sexual activity" for every need (including hunger) when afterglow or lust haze was active. Now each need gets its own reason based on what's actually happening: "Afterglow buffer" (only hunger/energy/social during afterglow), "Arousal suppression (lust haze)", "Post-orgasm exhaustion", "Scene action" (positive delta), or "Natural decay".

## 2026-05-26T19:30:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix needs chips not rendering after regen. The regen path consumed `_pendingRealismMetadata` but never set `emotion_label` in it (the normal path does this at line 4020 after evals). Without `emotion_label`, `_buildRealismIndicator`'s early return (`emotionLabel.isEmpty`) suppressed all chips including needs. Moved the `emotion_label` + `realism_state` synthesis into the regen path, mirroring the normal path.

## 2026-05-26T19:00:00Z
- **Files changed**: `lib/database/database.dart`, `lib/services/chat_service.dart`, `lib/database/database.g.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix character objectives bleeding between chats. Objectives were keyed only by `character_id` in the database, so when a user had multiple conversations with the same character, objectives from one chat would appear in another. Fixed by adding a `chat_id` (session ID) column to the `objectives` table and scoping all objective queries/inserts to the current session. Migration v28→v29 adds the nullable column for backward compatibility.


Automated log of code changes made by Claude Code for regression tracking.

## 2026-05-26T18:00:00Z
- **Files changed**: `lib/ui/dialogs/ui_settings_dialog.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix settings dialog popping immediately after color pick or avatar lock toggle.
  The `_updateUserBubbleColor`, `_updateUserTextColor`, `_updateAiBubbleColor`, `_updateAiTextColor`, `_updateDialogueColor`, `_updateActionColor`, and `_updateAvatarLocked` methods all called `Navigator.pop(context)` at the end, which closed the dialog right after any change. This meant:
  1. After picking a color, the settings dialog closed — user couldn't change more colors.
  2. After toggling avatar lock, the dialog closed — user couldn't see the toggle take effect or adjust other settings.
  3. `V2CardService().readCard()` + `chatService.setActiveCharacter()` reload was redundant and unnecessary — the character card was already saved to the PNG.
  Fix: removed the `Navigator.pop(context)` calls and the redundant reload logic. Users now control when to close the dialog.

## 2026-05-26T18:45:00Z
- **Files changed**: `lib/ui/dialogs/ui_settings_dialog.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix regression — color changes weren't sticking and avatar lock toggle had no effect. The dialog's `widget.character` is immutable, so after an async save the UI was still showing stale data. Solution: added a `ValueNotifier<CharacterCard?>` in the dialog's `State` (initialized from `widget.character`), replaced all `widget.character` references with `_characterNotifier.value`, and each update method calls `setState(() => _characterNotifier.value = updatedCharacter)` after saving. The dialog stays open, shows fresh data, and closes when the user taps the X.

## 2026-05-26T18:30:00Z
- **Files changed**: `lib/ui/dialogs/ui_settings_dialog.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix regression from previous fix — color picker changes weren't sticking and avatar lock toggle had no visible effect. The reload logic (`V2CardService().readCard()` + `chatService.setActiveCharacter()`) was needed to refresh the dialog's `widget.character` with the saved data. Moved the reload+pop into a shared `_reloadAndPop()` helper that runs in the `onChanged` callback after each save, so the dialog's UI reflects the changes before closing.

## 2026-05-26T17:00:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix needs chips showing all-zero deltas on regenerated messages. Three bugs:
  1. `regenPreTurn` was null — `_generateResponse` nulls `_pendingRealismMetadata` (line 6684) before the regen path could read `needs_pre_turn_vector`. Fixed by saving to a local variable before the call.
  2. The regen path never ran `_tickNeedsDecay()`, so `_needsVector` was identical to the pre-turn vector, producing zero deltas. Fixed by adding `_applyMoodDecay()` and `_tickNeedsDecay()` before the pre-turn snapshot, mirroring the normal path.
  3. Post-gen needs checks (climax, sexual activity, daily activities, fulfillment) were fire-and-forget inside `_generateResponse`, so `_needsVector` wasn't updated before delta computation. Extracted into `_runPostGenNeedsChecks` and made it `await`ed.

## 2026-05-26T16:30:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix compile errors from needs chips refactor — two scope bugs.
- **Effect**:
  1. `_captureRealismState()` at line 10149 called `_computeNeedsDeltasWithReasons(preTurnVector)` but `preTurnVector` was a local variable in the calling scopes, not in the method's scope. Fixed by making `_captureRealismState` accept an optional `preTurn` parameter. The three call sites that have `preTurnVector` in scope (normal message path, trust repair branch, group chat path) pass it. Other call sites (post-greeting, retroactive baseline, time-nudge, one-shot eval) don't have a pre-turn vector — they get null/empty deltas.
  2. `preTurnVector` was declared inside the `if (_realismActiveThisMode)` block (line 3925) but the needs delta computation was outside it (line 4054, after `_generateResponse`). Fixed by moving the `preTurnVector` declaration before the `if (_realismActiveThisMode)` block.

## Format

Entries are listed newest first in this style:

```markdown
## 2026-05-17T02:45:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `dev` (pushed to `origin/dev`)
- **Reason**: ...
- **Commit**: `573c230`
- **Effect**: ...
```

Always include the branch the change landed on.


## 2026-05-26T12:00:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Unify realism eval code paths — remove KoboldCpp-native vs API split. Previously, `_fireLLMEval` had separate parameter configurations for local (KoboldCpp) vs remote (OpenAI-compatible) backends: different maxLength (150/2500 vs 4000), different stop sequences, and Kobold-specific `banEosToken`/`trimStop` flags. Additionally, the four eval orchestrators (`_runPostGreetingEval`, `_runRetroactiveBaselineEval`, `_evaluateRealismForUpcomingGroupSpeaker`, regeneration path) duplicated sequential-vs-parallel branching. Since KoboldCpp has a built-in FIFO task scheduler and handles concurrent requests fine, all evals now use unified API-style parameters and run concurrently via `Future.wait()`.
- **Commit**: 96468a7
- **Effect**: Simplifies realism eval logic by removing ~100 lines of duplicate conditional branching. `isLocalKobold` conditional in `_evaluateRealismForUpcomingGroupSpeaker` removed entirely. `_fireLLMEval` no longer branches on backend type for parameters (always `maxLength: 4000`, `stopSequences: []`, no `banEosToken`/`trimStop` tweaks). All four eval orchestrators use `Future.wait()` for parallel execution. No observable behavior change — KoboldCpp's internal scheduler batches requests safely.
## 2026-05-25T16:00:00Z
- **Files changed**: `lib/services/llm_provider.dart`, `lib/ui/pages/settings_page.dart`, `lib/ui/dialogs/chat_settings_dialog.dart`, `lib/models/chat_generation_settings.dart`
- **Branch**: `Rawhide`
- **Reason**: Add oMLX as a first-class backend option for Apple Silicon Macs. oMLX is a local LLM inference server (https://github.com/jundot/omlx) that exposes an OpenAI-compatible API at localhost:8000. Reuses existing `OpenRouterService` — no new service class. Added `BackendType.omlx` enum value, auto-configures URL on switch, added 4th radio button in settings with macOS platform gate, exposed existing Remote API config section for oMLX (model picker, fetch models, connection check), added oMLX model picker to chat settings dialog for per-chat model selection, added `remoteModelName` field to `ChatGenerationSettings` for per-session model override.
- **Commit**: cfd5d11
- **Effect**: Users on Apple Silicon Macs can now select oMLX as a backend for local inference. oMLX server must be running separately (via `brew install jundot/omlx/omlx` then `omlx serve`). Model picker fetches available models from oMLX and allows selection. Banned tokens are not supported for oMLX (OpenAI API limitation — `logit_bias` requires token IDs).

## 2026-05-25T14:00:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Move `_computeNeedsDeltasWithReasons()` to run AFTER `_generateResponse` in the normal generation path.
  - The normal generation path (around line 4053) was computing needs deltas BEFORE calling `_generateResponse(GenerationMode.normal)`. This meant the post-generation checks (climax, sexual activity, daily activities, fulfillment) that modify the needs vector hadn't run yet, so the UI chips displayed stale data.
  - The regen path was already fixed (line 4389). Now the normal path matches — needs deltas are computed after generation so chips reflect the true final state.
- **Commit**: (pending)
- **Effect**: Needs change chips now show accurate deltas for normal (non-regenerated) messages. Previously, chips would show the delta from pre-generation decay only, missing any adjustments from climax, sexual activity, daily activities, or fulfillment checks.

## 2026-05-25T12:30:00Z
- **Files changed**: `lib/services/chat_service.dart`, `lib/services/storage_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Remove request serialization for KoboldCpp backend and force token throttle OFF.
  - KoboldCpp has a native FIFO task scheduler that can batch multiple requests. The previous code used sequential `await` chains for realism evals and `waitForIdle()` before each eval, defeating KoboldCpp's built-in batching.
  - Changed all 4 realism eval calls (relationship, emotional state, physical state, narrative) from sequential `await` to concurrent `Future.wait()` for both local and remote backends.
  - Removed `waitForIdle()` call before each `_fireLLMEval` — KoboldCpp's scheduler handles queuing.
  - Forced "Smooth Output Buffer" (token throttle) OFF for ALL users (new and existing). Existing stored preference is deleted on startup; users can re-enable via UI if desired.
- **Commit**: (pending)
- **Effect**: Faster chat response times as KoboldCpp can batch multiple eval requests. Tokens display at raw GPU speed by default, removing artificial delay. Existing users' throttle setting is not preserved — forced OFF to align with modern GPU capabilities.

## 2026-05-25T00:00:00Z
- **Files changed**: 27 files — major refactor of `lib/ui/pages/home_page.dart` (net -1573 lines), `lib/ui/pages/character_creator_page.dart` (net -600 lines), `lib/ui/pages/chat_page.dart`, `lib/ui/pages/settings_page.dart`, `lib/ui/pages/create_character_page.dart`, `lib/ui/pages/world_management_page.dart`, `lib/ui/dialogs/image_gen_settings_dialog.dart`, `lib/ui/dialogs/tts_settings_dialog.dart`, `lib/ui/dialogs/ui_settings_dialog.dart`, new widgets: `lib/ui/widgets/character_card_grid.dart` (1494 lines), `lib/ui/widgets/age_gender_row.dart`, `lib/ui/widgets/alternate_greetings_slider.dart`, `lib/ui/widgets/avatar_art_style_selector.dart`, `lib/ui/widgets/character_name_input.dart`, `lib/ui/widgets/description_detail_chip_row.dart`, `lib/ui/widgets/first_message_length_dropdown.dart`, `lib/ui/widgets/greeting_tone_selector.dart`, `lib/ui/widgets/nsfw_toggle.dart`, `lib/ui/widgets/persona_selector_dropdown.dart`, `lib/ui/widgets/slider_with_input.dart`, `lib/ui/widgets/styled_dropdown.dart`, `lib/database/database.dart`, `lib/models/character_card.dart`, `lib/services/character_repository.dart`, `test/services/character_repository_test.dart`, `docs/Rawhide.md`, `.github/workflows/ci.yml`
- **Branch**: `Rawhide`
- **Reason**: PR #37 — major UI modularization and character card grid refactor. Extracted ~1500+ lines of character browsing logic from `home_page.dart` into a dedicated `CharacterCardGrid` widget (1494 lines). Extracted ~10 new reusable form widgets for the character creator (age/gender row, greeting tone selector, NSFW toggle, etc.). Added `avatarLocked` field to `FrontPorchExtensions` model for per-character avatar size control. Added `getMemorySources`, `setMemorySources`, `setCharacterImagePath`, and `setTtsVoice` helper methods to `CharacterRepository`. Fixed database test factory to use temp file instead of in-memory (isolates couldn't access `:memory:`). Updated Rawhide user-facing dialog notes and CI.
- **Commit**: `631c90d`
- **Effect**: Massive reduction in file sizes (home_page.dart from ~2000 lines to ~430, character_creator_page.dart from ~1900 to ~1300). Much better code organization with focused, reusable widgets. New character repository APIs simplify avatar/memory/TTS management. Database tests now work reliably with background isolates.

## 2026-05-24T04:20:00Z
- **Files changed**: 24 files including `lib/ui/theme/app_colors.dart`, `lib/main.dart`, `lib/providers/app_state.dart`, `lib/ui/pages/character_creator_page.dart`, `lib/ui/pages/create_character_page.dart`, `lib/ui/pages/chat_page.dart`, `lib/ui/widgets/sidebar.dart`, multiple dialogs, settings, model manager, story pages, `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Major light mode completion pass. Replaced remaining hardcoded dark containers (`0xFF0F172A`, `0xFF1E293B`, etc.) and white-on-dark text throughout the character creator (both flows), chat sidebar (Realism, Objectives, Lorebook bullets, Evolution, Summary, RAG, Author's Note, Lust/Strength/Fixation bars), settings, dialogs, model cards, home, story pages, etc. with `AppColors` (`textPrimary/Secondary/Tertiary`, `surfaceOf`, `cardOf`, `borderOf`, `resolve`, etc.). Fixed mode cards, progress steps, identity/avatar forms, and sidebar "AI Character Creator" header (no longer blinding yellow). Full feature parity in light mode.
- **Commit**: `46e152a`
- **Effect**: Light mode is now fully comfortable and readable across the entire app. No more invisible text or dark-only boxes on the warm paper palette. All major user-reported contrast issues resolved.

## 2026-05-23T05:45:00Z
- **Files changed**: `lib/services/chat_service.dart` (removed 2 dead detector methods + 70 lines, fixed +bladder in climax, merge for chips, strengthened contract, updated comments), `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Needs eval pipeline was still producing false-positive deltas (hunger +25, hygiene +13, bladder + from erotic text with no actual eating/relief) via the remaining post-response "detective" LLM calls and bad chips, masking natural decay so bladder stayed at 100 and hunger didn't progress even on SOTA models. Removed _checkSexualActivityInResponse and _checkDailyActivityEffects (and their calls), removed erroneous 'bladder':8 from climax cross-effects, made post chips merge with (instead of clobber) pre-response structured deltas, tightened the Needs Chip Contract prompt with explicit anti-hallucination rules for erotic RP language. Passive _tickNeedsDecay for hunger/bladder now actually shows through in long scenes; fewer per-turn evals (good for local 24B Kobold); 1:1/group parity improved.
- **Commit**: (local)
- **Effect**: Hunger/Bladder (and other needs) now decay reliably during pure erotic or non-relief scenes. Characters will start showing hunger, bathroom urgency, etc. via OOC and stepped injection. Structured eval + creative chips are the only sources; detectors retired as intended by the "first-class" refactor. 0 new warnings on analyze.

## 2026-05-23T04:10:00Z
- **Files changed**: `lib/ui/pages/settings_page.dart`, `lib/services/storage_service.dart`, `lib/main.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Finish the half-baked PR #33 integration from 8f7be69 (PseudoRemote + light-mode foundation). Made PseudoRemote selectable+startable with full config UI and startActiveManagedProcess call site; ported dual dark/light chat color persistence + isDark to StorageService; wired toggle + init so light mode survives restarts and main surfaces/chat colors flip.
- **Commit**: (local, will be squashed before push)
- **Effect**: PseudoRemote backend is now usable end-to-end on Rawhide; light mode toggle is no longer a no-op for persistence and a few surfaces.

## Entries

## 2026-05-22T18:30:00Z
- **Files changed**: `analysis_options.yaml`, 34+ source files (style, imports, nulls, deprecations via dart fix), `lib/services/chat_service.dart` (1 dead const removed), `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Kickoff of technical debt cleanup per approved lint remediation plan. Phase 0: silenced 77+ generated-code warnings + fixed invalid linter rule via analyzer excludes + removal of `deprecated_member_use` disable. Phase 1: bulk auto-fix of 150+ mechanical issues (`unnecessary_brace_in_string_interps`, `unnecessary_non_null_assertion`, `deprecated_member_use` migrations, imports, etc.). One manual removal of dead `_postClimaxCrashDefaultTurns` const. Warnings reduced from 206 → 50 (mostly core realism unused remnants now).
- **Effect**: `flutter analyze` dramatically quieter; IDEs and CI output much cleaner. Generated gRPC/FlatBuffer code no longer pollutes results. Safe, semantics-preserving modernizations applied. Groundwork laid for Phase 2 (manual audit of remaining ~46 semantic warnings in chat_service and supporting services) and stricter CI.
- **Commit**: (working tree – will be squashed/landed as "chore(lint): Phase 0+1 mechanical + config cleanup")

## 2026-05-22T02:10:00Z
- **Files changed**: `lib/services/chat_service.dart` (major refinements), `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Pre-response Needs pressure injection + OOC guidance so characters react to high/urgent needs (including positive high states like "this is so much fun" and the "Enjoys low hygiene" reversal) before they speak. Stronger JSON extraction for thinking models, finalizer guaranteeing chips for every need that moves (including pure decay), richer Needs context now feeding into Realism evals (bond/trust/emotion/fixation), and solid regen/swipe support for the rich Needs deltas and narrative memories.
- **Effect**: Needs feels much more alive and reactive in the moment. Characters on Rawhide can now naturally express comfort, pleasure, or distress based on current need levels, with proper hygiene inversion for filthy-loving characters. Regen finally produces meaningful Needs chips instead of only legacy ticks.
- **Commit**: (this push)

## 2026-05-21T20:45:00Z
- **Files changed**: `lib/services/chat_service.dart` (major), `lib/database/database.dart`, `lib/services/memory_service.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Complete rework of the Needs simulation to make it first-class (matching the quality and integration of the rest of the Realism Engine).
  - Replaced the previous collection of narrow, unreliable side-channel LLM detectors with a single rich, philosophy-guided, model-driven structured eval (`_evaluateNeedsDeltasCall`) that understands context, erotic pleasure, embarrassment, relief, and character personality.
  - Added proper short-term narrative memory (first-person internal thoughts, delta-magnitude weighted lifespan, catastrophe boost, decay) for immediate guidance of future turns.
  - Added long-term invisible RAG memory (new `needs_event` type in the existing embedding store + `storeNeedsEventMemory` / `retrieveSalientNeedsEvents`) so characters can recall high-impact pleasure or humiliation events 40+ turns later when semantically relevant.
  - Safe one-way optional hooks into Realism evals (narrative context passed only when Needs is enabled).
  - Full group chat parity (per-speaker storage in `_groupRealism`, speaker-aware RAG retrieval and injection).
  - All paths strictly gated by `needsSimEnabled`; Realism is 100% independent when Needs is off.
  - Legacy fulfillment verifier and related dead constants/methods retired during final cleanup.
- **Effect**:
  - Needs now feels alive and consistent: pleasure during intimate scenes correctly raises the relevant bars, big events create lasting (but invisible until relevant) memories, and the system works reliably across models instead of the previous ~30% failure rate.
  - Characters in both 1:1 and group chats get appropriate lingering internal reactions and long-term recall.
  - The feature is fully optional per-character and adds depth without breaking anything when disabled.
- **Commit**: N/A (this session)

## 2026-05-21T14:30:00Z
- **Files changed**: `lib/app_version.dart`, `lib/services/update_service.dart`, `lib/ui/widgets/sidebar.dart`, `lib/ui/dialogs/update_dialog.dart`, `.github/workflows/nightly.yml`, `.github/workflows/beta-release.yml`, `docs/Rawhide.md`, `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: The auto-updater was completely broken for Rawhide nightlies:
  - GitHub release tags use "nightly-rawhide.YYYYMMDD.SHA" wrapper but binaries embed just "rawhide.YYYYMMDD.SHA".
  - Asset filenames for nightlies are *Nightly* (Setup.exe / .dmg / -Linux.AppImage) while updater only knew about Beta/Stable names.
  - _isNewerVersion had no understanding of the rawhide date format and always returned false.
  - Display code blindly prefixed "v" producing "vrawhide..." and releaseUrl links were wrong for nightly tags.
  - Beta release template and nightly template both needed updating so future builds carry the isNightlyBuild flag.
- **Effect**:
  - Rawhide binaries from any night now correctly see and offer updates to newer nightly releases (date-based comparison + asset name selection).
  - Nightly, Beta, and Stable channels have fully independent asset lookup.
  - Sidebar and Update dialog show clean version strings and correct GitHub links.
  - Added `isNightlyBuild` top-level getter (and kept in CI overwrites) for future-proofing.
  - Updated friendly Rawhide notes so the in-dialog "What's New" mentions the fix.
- **Commit**: N/A (this session)

## 2026-05-20T22:10:00Z
- **Files changed**: `lib/services/cloud_sync_service.dart`, `lib/services/character_repository.dart`, `lib/services/storage_service.dart`, `lib/ui/pages/cloud_sync_page.dart`, `lib/main.dart`, `docs/Rawhide.md`, `.claude/changelog.md`, `PRIVACY.md`, and removal of `lib/services/cloud_providers/onedrive_provider.dart`
- **Branch**: `Rawhide`
- **Reason**: 
  - Implement proper channel isolation for cloud sync so Rawhide and Stable no longer share the same remote data (`/FrontPorchAI` vs `/FrontPorchAI-Rawhide`).
  - Complete the deletion reliability work (soft deletes for characters/groups + active remote reconciliation).
  - Improve the experience for developers running from source (`flutter run`).
  - Remove dead OneDrive provider code.
- **Effect**:
  - Rawhide builds now sync to their own isolated remote namespace (`/FrontPorchAI-Rawhide`), preventing cross-channel pollution with Stable.
  - Character and group deletions are now reliable: soft deletes, properly awaited remote deletes, web server paths fixed, and a new `_reconcileDeletedAssets` step that cleans orphaned remote files based on the post-merge DB state.
  - Dev builds gained: `FRONT_PORCH_AI_DATA_DIR` env var override, much quieter missing-PNG logging, public `cloudRoot` exposure, improved sync logging, and a "Paths in use" info box in the Cloud Sync UI.
  - Dead OneDrive code and all references fully removed.
  - Updated user-facing notes in `docs/Rawhide.md`.
- **Commit**: N/A (work in progress on Rawhide)

## 2026-05-20T16:22:30Z
- **Files changed**: `lib/main.dart`, `lib/ui/pages/settings_page.dart`
- **Branch**: `Rawhide`
- **Reason**: Fix Rawhide build failures. `PseudoRemoteService` was referenced in main.dart (for the new pseudo-remote backend DI wiring) but the import was missing, causing "Method not found" / "isn't a type" errors. Also fixed a stale call site in settings_page.dart that captured the return value of `LLMProvider.setActiveBackend()` (now `Future<void>`) into a variable used in a ternary, producing "This expression has type 'void'".
- **Effect**: `flutter run` and `flutter analyze` now succeed for the Rawhide channel. Pseudo-remote backend support (KoboldCPP via its OpenAI-compatible endpoint) is registered in DI and LLMProvider but the settings UI selection for it is not yet wired (radios still only expose kobold vs openRouter); this was a compile-time regression from the partial addition.
- **Commit**: N/A (local fix)

## 2026-05-20T02:12:00Z
- **Files changed**: `lib/ui/pages/edit_character_page.dart`, `lib/services/character_repository.dart`, `docs/dev.md`
- **Branch**: `dev` (cherry-pick of 7a62e06 from Rawhide)
- **Reason**: Land the avatar image replacement EROFS crash fix on the dev branch so it will be in the next dev-channel / PR-target builds. Created docs/dev.md following the per-branch user-facing changelog convention (Rawhide.md was intentionally dropped during conflict resolution).
- **Effect**: Same as the Rawhide fix — reliable avatar changes for all users, plus defensive path resolution in the repository. Also created the dev branch's dialog notes file.
- **Commit**: `9a48db2` (cherry-picked)
- **Original commit on Rawhide**: `7a62e06`

## 2026-05-20T02:05:00Z
- **Files changed**: `lib/ui/pages/edit_character_page.dart`, `lib/services/character_repository.dart`, `docs/Rawhide.md`
- **Branch**: `Rawhide`
- **Reason**: Fix the root cause of the macOS "Read-only file system (errno 30)" crash when a user changed a character's avatar image using the full editor page. The editor was writing a bare basename into the CharacterCard before updateCharacter(), which then performed a relative File write into the CWD (read-only inside packaged .app bundles). Added defensive resolution in the repository + corrected the editor to follow the documented full-path invariant. Also updated the Rawhide user-facing dialog notes.
- **Effect**: Avatar replacement now works reliably for end users on all platforms. The previous silent symptom on developer machines (stray <name>_<ts>.png files written into the project root, e.g. Akira_1779243445478.png) is also eliminated. Hardening prevents the same class of bug from recurring.
- **Commit**: `7a62e06`
- **Co-authored-by**: Grok

## 2026-05-20T01:25:00Z
- **Files changed**: `lib/models/story_project.dart`, `test/models/story_project_test.dart`, `lib/services/chat_service.dart.bak2`, `opencode-nanogpt`
- **Branch**: `Rawhide` (cherry-pick backport)
- **Reason**: Backport the story double-to-int coercion fix + tests + repo hygiene from PR #31 (squash commit fa637f8 on dev) onto the Rawhide branch for nightly / cutting-edge users. Kept author as Linux4life1 per project rules; credited original contributor in message.
- **Effect**: Same as the dev merge — safe `(as num?)?.toInt()` coercion on all affected Story* fromJson methods, 16 new unit tests, removal of the two accidentally committed noise items. No .gitignore pollution on Rawhide.
- **Commit**: `7b62c84` (cherry-picked + re-authored)
- **Original PR**: https://github.com/linux4life1/front-porch-AI/pull/31

## 2026-05-20T01:21:00Z
- **Files changed**: `lib/models/story_project.dart`, `test/models/story_project_test.dart`, `lib/services/chat_service.dart.bak2`, `opencode-nanogpt`, `.gitignore`
- **Branch**: `dev` (via squash merge of PR #31 + post-merge hygiene)
- **Reason**: Land external contributor PR #31 (safe double-to-int coercion in all Story* fromJson methods to handle LLM numeric output like `1.0`, plus first 16 unit tests + accidental file/submodule cleanup). Performed low-friction squash merge + removed stray local-dev `.gitignore` entry ourselves to stay welcoming to contributors.
- **Effect**:
  - All integer fields in `StoryBeat`, `StoryScene`, `StoryAct`, `StoryLoreEntry`, and `StoryProject` now safely coerce via `(json['field'] as num?)?.toInt() ?? default`.
  - Added `test/models/story_project_test.dart` (first coverage; exercises both int and double inputs for every affected fromJson).
  - Removed 8.8k-line `chat_service.dart.bak2` and broken `opencode-nanogpt` submodule.
  - Squashed to single clean commit on `dev` (`fa637f8`); tiny follow-up hygiene commit (`3bbda2c`) for .gitignore.
- **Commit**: `fa637f8` (squash merge) + `3bbda2c` (hygiene)
- **PR**: https://github.com/linux4life1/front-porch-AI/pull/31 (contributor: @MisterLotto)

## 2026-05-21T05:45:00Z
- **Files changed**: `lib/services/chat_service.dart`, `lib/ui/dialogs/group_settings_dialog.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: Implement per-character group-scoped system prompts as requested (leaving the global Group System Prompt field and its empty-default behavior completely unchanged).
- **Effect**:
  - Added `_groupCharacterSystemPrompts` map + public `getSystemPromptForGroupCharacter` / `setSystemPromptForGroupCharacter` API in ChatService.
  - Wired the map into the hidden `__group_state__` checkpoint (serialization + hydration) so values survive restarts, forks, and cloud sync (no DB schema change).
  - Updated prompt assembly in `_generateResponse`: when a character speaks in a group, a non-empty group-scoped per-char system prompt now takes full precedence (header: "[Group-specific instructions for Name]"); otherwise falls back to the character's normal card `systemPrompt`.
  - Cleared the map on all group context resets and character removal from group (consistent with author notes / realism).
  - Added full UI in Group Settings → Prompt Engineering tab: new "Per-Character System Prompts" section with per-character multi-line editors (modeled on the existing per-char Author's Notes UI, using cyan accent). Save applies via the new ChatService setters + checkpoint.
  - New groups start with empty per-char prompts (as expected).
- **Commit**: (not yet pushed)

## 2026-05-21T05:10:00Z
- **Files changed**: `lib/ui/pages/home_page.dart`, `lib/ui/dialogs/group_settings_dialog.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User confirmed keeping the Group System Prompt field (with empty default) after discussion about per-character group system prompts. Requested proper default behavior on group creation and a clear tooltip.
- **Effect**:
  - Changed new group creation (both direct creation in home screen and fork flow) so the Group System Prompt now defaults to empty instead of pre-filling the built-in default group prompt.
  - Removed auto-population of default/observer prompts when toggling Director Mode during group creation.
  - Improved the description and added a detailed Tooltip for the "Group System Prompt" field in Group Settings → Prompt Engineering, explaining its intended use (global AI behavior rules, style, formatting, turn discipline overrides) and clarifying that per-character instructions belong in the per-character fields below.
- **Commit**: (not yet pushed)

## 2026-05-21T04:50:00Z
- **Files changed**: `lib/ui/dialogs/group_settings_dialog.dart`, `lib/ui/pages/chat_page.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User request to clean up duplication and improve clarity of Group Author's Notes in the UI.
- **Effect**:
  - Removed the "Group Author's Note" section (and its strength slider) from the Prompt Engineering tab in the Group Settings dialog. Per-character author's notes remain available there.
  - Updated `_AuthorNoteSection` in the right sidebar: When in a group chat, it now displays as "**Group Author's Note**" with a tooltip explaining that it affects all characters in the group, and directs users to "Group Settings → Prompt Engineering" for per-character notes. In 1:1 chats it continues to show the normal "Author's Note" label and tooltip.
- **Commit**: (not yet pushed)

## 2026-05-21T04:25:00Z
- **Files changed**: `lib/ui/dialogs/group_settings_dialog.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User reported that an outdated "Missing Backend Support" developer warning was still visible in the group settings dialog (specifically referenced in the RAG / Memory section context).
- **Effect**: Removed the large amber warning box and its long list of "what must be added" technical requirements from the Realism & Needs tab. This note was from an earlier development phase. Per-group Realism and RAG settings have been fully functional for some time via the hidden `__group_state__` checkpoint mechanism (no Drift schema changes were required). The dialog now presents a cleaner UI without the confusing outdated warning.
- **Commit**: (not yet pushed)

## 2026-05-21T04:05:00Z
- **Files changed**: `lib/ui/pages/chat_page.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User request for minor group chat sidebar cleanup: remove the unnecessary "New Chat" button from the right sidebar, and move the Group Settings gear up to replace it using the same OutlinedButton style as the other controls (TTS, etc.).
- **Effect**: 
  - Deleted the full-width "New Chat" OutlinedButton in the group sidebar controls area.
  - Replaced it with a matching `OutlinedButton.icon` for "Group Settings" (using `Icons.settings`) that opens the group settings dialog.
  - Removed the old small `IconButton` gear icon that was previously next to the "Characters" header (to avoid duplication).
  - The 4 group-specific settings are now more prominently accessible in the same visual style as other sidebar action buttons.
- **Commit**: (not yet pushed)

## 2026-05-21T03:30:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User reported that needs (especially hunger) were triggering too early and too mechanically in group chats (e.g. complaining about hunger at 62%), making the system feel like "wack-a-mole" instead of immersive roleplay.
- **Effect**: Major balanced improvement to the Needs/Sims system for better roleplay quality:
  - Raised injection threshold: Needs are no longer directly injected at step 4 (mild). Only noticeable or worse needs (step ≤ 3) generate an explicit background state block. This directly fixes the "mentioning hunger at 62%" problem.
  - Completely rewrote all `_needSteppedText` entries across the 7 needs to be more subtle, atmospheric, and immersive. Language now focuses on internal sensations and mood rather than forcing the character to verbalize complaints.
  - Softened the injection wrapper text in both group and 1:1 paths (less "this must influence her dialogue right now", more "this may subtly color her mood and focus").
  - Updated 1:1 urgency prefixes for consistency with the new, less mechanical tone.
  - Severe/catastrophic needs remain strong and dramatic when appropriate.
  - All changes maintain full parity between 1:1 and group chats per the new Claude.md rule.
- **Commit**: (not yet pushed)

## 2026-05-21T02:45:00Z
- **Files changed**: `Claude.md`
- **Branch**: `Rawhide` (local)
- **Reason**: User request to formalize a new strict rule after discussion about the shared nature of the Realism Engine and Needs/Sims simulation between 1:1 and group chats.
- **Effect**: Added a new "Realism & Needs System Parity" subsection under Code Style & Conventions. The rule states that any fixes or changes to realism or needs logic must keep group chat and 1:1 chat behavior in parity at all times, unless explicitly discussed and approved. Also added a cross-reference bullet in the Verification section for extra visibility. This makes parity enforcement a permanent, high-priority project rule.
- **Commit**: (not yet pushed)

## 2026-05-21T02:10:00Z
- **Files changed**: `lib/ui/pages/chat_page.dart`, `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User reported two bugs after group realism work:
  1. Deleting a message from a character in a group does not reset that character's Realism stats.
  2. All group realism bars incorrectly show values as `/300` (Trust and Arousal should be `/100`).
- **Effect**:
  - Fixed hardcoded `target = 300` and normalization in `_buildGroupRealismRichRow`. Now accepts `maxValue` parameter (defaults to 300 for Bond, 100 passed for Trust and Arousal). Display now correctly shows `xx/100` for Trust/Arousal and proper progress bar scaling.
  - Improved `deleteMessage`: In group chats, when deleting a message (even if not the absolute last), we now attempt realism state restoration from the new last message if it has a snapshot. This gives better "time travel" behavior for per-character realism when users delete specific character messages in groups (previously only the very last message in the entire chat triggered rollback).
- **Commit**: (not yet pushed)

## 2026-05-21T01:25:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: Critical bug fix after user reported RangeError crash during group chat turn with Realism + Needs enabled. Error: `RangeError (length) Invalid value: Not in inclusive range 0...4: 5`
- **Effect**: Fixed missing guard in the group-mode branch of `_getNeedsInjection()`. The code was calling `_needSteppedText[top.key]?[step]` when `_getNeedStep()` returned 5 (comfortable needs), but every stepped text list only has 5 elements (indices 0-4). The 1:1 path already had `if (step >= 5) return ''`; the group path did not. Added the same early return. This prevents the crash when any need is in the comfortable range during per-speaker group realism evaluations. All relevant tests (chat_service_group_realism_test.dart + chat_service_realism_test.dart) now pass cleanly. `flutter analyze` clean.
- **Commit**: (not yet pushed)

## 2026-05-21T00:40:00Z
- **Files changed**: `test/services/chat_service_group_realism_test.dart` (new file)
- **Branch**: `Rawhide` (local)
- **Reason**: Next item from the remaining deliverable list: add complete unit tests for the inter-character realism system (Phase 2/3 functionality + Phase 3 hard cap).
- **Effect**:
  - Created a new, self-contained test file following the project's established stub pattern (`_GroupRealismStub`).
  - 12 focused, passing tests covering:
    - Public helpers (`getInterCharacterRelationships`, `updateInterCharacterRelationship`)
    - Seeding logic (neutral 0 on first use)
    - 4-character hard cap (Phase 3) — both the disabled case (5+) and working case (≤4)
    - Membership pruning when characters leave a group
    - Observer mode suppression
    - Full checkpoint serialize/load round-tripping of the 'relationships' key (including old checkpoints without the key)
    - Reset behavior
  - All tests pass cleanly. `flutter analyze` clean for the new file. No dead code.
  - This fulfills the long-standing testing gap called out in the original group realism plan.
- **Commit**: (not yet pushed)

## 2026-05-20T23:55:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: Complete Phase 3 of group realism engine work. Primary goals: enforce the approved hard cap of 4 characters for inter-character tracking, improve Director/Observer safety, expose hidden data for debug, and add membership hygiene.
- **Effect**:
  - Added `_shouldTrackInterCharacterRelationships` getter (returns true only when active group has ≤4 members). This is the key Phase 3 safety mechanism per the plan.
  - All inter-char logic (seeding, injection, heuristic updates, and the decay block) is now strictly guarded behind the 4-char cap. In groups of 5+, inter-character tracking is completely disabled while user-directed realism continues normally for everyone.
  - Strengthened Director/Observer mode guards on seeding and updates.
  - Updated `getRealismStateForGroupCharacter` documentation to mention the hidden 'relationships' map (useful for future debug tools or advanced features).
  - Enhanced membership handling: `_ensureInterCharacterRelationshipsSeeded` now also prunes stale relationships pointing to characters who have left the group.
  - All changes are complete, verified, and respect the "no skeletons / finish per turn" rule.
- **Commit**: (not yet pushed)

## 2026-05-20T22:40:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: Begin and fully complete Phase 2 of group realism (invisible inter-character relationship tracking). User explicitly requested that characters have private (non-UI-visible) feelings about each other so group dynamics feel more real. Phase 1 verification gate passed.
- **Effect**:
  - Added `_ensureInterCharacterRelationshipsSeeded()` — automatically gives every group member a neutral (0) hidden relationship entry toward all other current members the first time they participate in a realism-enabled group turn.
  - Extended `_applyMoodDecay()` to slowly drift all hidden relationship deltas toward 0 for the current speaker (prevents frozen grudges/friendships).
  - Implemented full `_getInterCharacterFeelingsInjection()` that produces private OOC guidance for the *current speaker only* describing their secret attitudes toward every other group member (e.g. "Alice: wary of Bob (-22)"). This block is appended to the realism injection for group speakers.
  - Wired the new injection into the central realismBlock assembly in `_generateResponse` so it participates in token budgeting and prompt construction.
  - Added `_updateInterCharacterFeelingsFromRecentExchange()` — a lightweight heuristic that scans the last user + AI exchange for other group member names and applies small positive/negative deltas based on simple sentiment cues. Called automatically after every group AI response.
  - Called the seeder from the per-speaker eval path (Phase 1 hook) and the updater + checkpoint from post-generation finalization.
  - All changes are invisible to the UI (sidebar bars remain user-only). The mechanic is fully functional, seeded, decaying, injected, and reactive.
  - Verified: `flutter analyze` (exit 0) + whole-project grep (no dead references) after edits. No skeletons. Follows "complete per turn" rule.
- **Commit**: (not yet pushed)

## 2026-05-20T21:05:00Z
- **Files changed**: `Claude.md`
- **Branch**: `Rawhide` (local)
- **Reason**: User instruction to formalize the "no skeleton files" process rule that was established during the Group Realism Phase 1 work. The rule ("no skeleton files are to be created. all tasks must be completed per turn.") must now be followed by all AI agents working in the repo.
- **Effect**: Added a new "Task Completion Rules" subsection under Code Style & Conventions in Claude.md with strict language. Also reinforced the rule in the existing "Before marking any task 'done'" bullet and in the "Reviewing Sub-Agent / AI-Generated Work" section. This makes the no-skeletons policy a permanent, high-visibility project rule.
- **Commit**: (not yet pushed)

## 2026-05-20T20:15:00Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: Continue Phase 1 (per-speaker realism evaluation timing) without any skeleton code. The previous _evaluateRealismForUpcomingGroupSpeaker was only a stub. Implemented the complete working version using temporary impersonation of _activeCharacter so that 100% of the existing LLM eval orchestration, one-shot vs staged decision tree, parsing, inertia, cancellation handling, and metadata synthesis is reused. Added supporting private helpers _loadGroupRealismIntoScalars / _saveScalarsIntoGroupRealism for round-tripping the target speaker's state. Gated the centralized LLM eval block in sendMessage so groups use the new per-speaker path inside _generateResponse (the architecturally correct hook point after _pickNextGroupCharacter). All changes verified with flutter analyze (exit 0) + whole-project grep after edits. No dead code, no new warnings from these changes.
- **Effect**: The next character to speak in a group chat now actually receives a real realism LLM evaluation (one-shot or staged per settings) on their turn, before their prompt is built. Results are written back to that character's entry in _groupRealism so prompt injection (_getRelationshipInjection etc.) and the group sidebar UI immediately see the updated bond/trust/emotion/arousal/fixation/needs. This is the first time the realism engine has performed per-character LLM-driven updates in groups. Phase 1 complete; ready for verification before any Phase 2 (inter-character hidden relationships) work.
- **Commit**: (not yet pushed)

## 2026-05-20T14:30:00Z
- **Files changed**: `lib/ui/pages/chat_page.dart`
- **Branch**: `Rawhide` (local)
- **Reason**: User request — the full realism bars (Bond/Trust/Arousal + emotion + needs) in group chat were gated behind a small info_outline button + modal sheet, with only micro 4px bars and a tiny top overview visible in the right sidebar. Previous experimental layers (indicator strip, overview, sheet, tooltip) had accumulated as distracting "garbage" code. Follow-up: the initial replacement was still too "mini" (unlabeled, tiny bars, no tier names or 1:1 visual weight). User clarified desired result: full 1:1 realism bar UI (labeled Short-Term/Long-Term Bond, Trust, Arousal with tier names, proper 5px bars, icons, value/target) per character in the group sidebar list + fixation under the character description/summary (slightly smaller text) + a dedicated tooltip info button + focused popup for just the needs of that character.
- **Effect**: Complete removal of all prior group realism UI experiments (micro indicators, overview strip, big sheet + its stat rows, info button, old tooltip helper, and the follow-up mini-bar implementation). Added rich per-character realism rendering (`_buildGroupCharacterFullRealismUI` + supporting tier calculation + `_buildGroupRealismRichRow`) that mirrors the exact labeled row + 5px bar + tier name + icon + tooltip treatment from the single-char `_RealismSection` (Short-Term Bond, Long-Term Bond, Trust, Arousal), driven by the existing group per-char getters. Added `_buildGroupFixationSmall` (10pt italic text with icon) placed directly under each character's description in the list. Added tooltip-wrapped info icon inside the realism block that opens a clean dedicated `_showGroupCharacterNeedsPopup` (focused dialog with full needs list + progress bars for that character only). All changes are in one file, follow the "reuse 1:1 visuals, sidebar is scrollable so taller rows are fine" guidance, and were verified with full `flutter analyze` + whole-project greps after every logical edit. No new errors. The group right sidebar now shows the real full realism UI per character with no gating.
- **Commit**: (not yet pushed)

## 2026-05-18T17:12:00Z
- **Files changed**: `lib/services/chat_service.dart`, `docs/realism-engine.md`
- **Branch**: `Rawhide` (pushed to `origin/Rawhide`)
- **Reason**: Rawhide testers reported that "with the needs system off the realism processing speed is a lot slower now". Root cause: `_verifyNeedFulfillmentCall` (the extra LLM eval that detects actual scene fulfillment of low needs) was being `await`ed synchronously inside the pre-response realism block — both on the normal local KoboldCPP sequential path and on the trust-repair intercept. Any chat whose per-session `needsSimEnabled` flag was still true (old sessions, card default, mid-chat enable that was later toggled) paid an extra full serial eval round-trip on every turn, even when the user believed needs was off.
- **Commit**: `3849c7a`
- **Effect**: Moved the fulfillment verification to a post-response fire-and-forget (same pattern as the sexual-activity and daily-activity checks). The visible "Realism Engine evaluating..." phase now has identical latency whether needs simulation is enabled or disabled. The state update still occurs; it simply takes effect on the subsequent turn. This matches the documented "post-response verification" behaviour and removes the performance side-effect that the Needs port introduced into the critical path. (Unrelated `edit_character_page.dart` diff left uncommitted.)

## 2026-05-18T09:58:23Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local only)
- **Reason**: Fixed a build failure caused by a duplicate declaration of `effectiveStep` inside `_getNeedsInjection()`. The recent "Enjoys low hygiene" inversion and the existing arousal suppression (lust haze) feature were both declaring their own `int effectiveStep`, which broke compilation on macOS.
- **Commit**: `dc06f9b`
- **Effect**: Both features now correctly share a single `effectiveStep` variable. Hygiene inversion is applied first, then lust haze suppression can further adjust the displayed urgency. Build now succeeds again.

## 2026-05-18T09:25:00Z
- **Files changed**: `lib/models/character_card.dart`, `lib/services/chat_service.dart`, `lib/ui/widgets/realism_form_section.dart`, `lib/ui/pages/edit_character_page.dart`, `lib/ui/pages/create_character_page.dart`, `lib/ui/pages/character_creator_page.dart`
- **Branch**: `Rawhide` (local only)
- **Reason**: Implemented the full "Enjoys low hygiene" inversion feature for characters who enjoy being sweaty, musky, or filthy. Added per-character toggle in the Realism Engine panel. When enabled: low hygiene becomes desirable (positive aroused language + mild scaling Arousal/Fun/Comfort bonuses), high hygiene (60+) becomes undesirable (Arousal penalty and "too clean" feeling), strong resistance to non-erotic cleaning, erotic/tongue cleaning is exempt, and forced cleaning while low hygiene applies -30 Bond + -30 Trust on top of normal deltas. Effects scale with the actual hygiene value.
- **Commit**: `cfdfad2`
- **Effect**: Characters with this preference now behave consistently with their established kinks instead of the Needs system fighting them. This completes the initial test case for Needs inversion and brings the erotic realism layer to a much more usable state for long filthy/musky scenes.

## 2026-05-18T08:43:22Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide` (local only)
- **Reason**: Implemented "Arousal suppresses other needs" (lust haze) erotic realism feature per user request for more fun/sexy Needs Simulation. High arousal during/after sex now makes other needs (hunger, bladder, energy, etc.) read as less urgent (or be omitted) in the OOC prompt injection, with light dampening of internal state-based decay multipliers. This prevents characters from randomly complaining about basic needs while extremely turned on. Includes proper snapshot/regen/swipe support (also fixed latent afterglow snapshot bug as side effect).
- **Effect**: Long erotic scenes now feel much more immersive and realistic. Sex feels temporarily "all-consuming." Bladder desperation during high arousal is deliberately preserved for kinky flavor. Sr. Dev refinements applied (naming, activation rules, simulation-side dampening, snapshot correctness).

## 2026-05-18T08:23:24Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: User reported energy need eroding so fast that characters were falling asleep / passing out mid-sex (e.g. "falling asleep while I was licking her pussy"). Root cause: both non-climax sexual activity and climax paths were applying negative energy deltas (`-4*strength` and `-7`), on top of the normal per-turn decay (3 base / 6 at night). This made long erotic scenes rapidly drain the character.
- **Commit**: (uncommitted local)
- **Effect**: Changed energy deltas during sexual/intimate activity from negative (draining) to positive (refilling). Non-climax now gives `+ (3 * strength)` (mild adrenaline/pleasure rush of 1-3 per turn). Climax now gives a solid `+10` (big "shot of Monster/Red Bull" effect). Sex now feels temporarily energizing/stimulating while it's happening, which prevents the unwanted "nodding off mid-act" behavior while still allowing normal decay + night penalties to matter outside of active scenes. Afterglow buffer continues to help afterward. Matches the erotic use case the Needs sim is seeing heavy testing on.

## 2026-05-18T08:15:52Z
- **Files changed**: `lib/services/chat_service.dart`
- **Branch**: `Rawhide`
- **Reason**: Needs simulation now participates in the same regen rollback system as the classic realism fields. Added `needs_pre_turn_vector` capture (before decay+fulfillment) into the pending metadata on every user turn, plus symmetric revert in `regenerateLastMessage()`'s manual delta-revert block (reading from the rejected message's metadata). Also ensured regen re-synthesis writes the anchor for future regens of the new response. This fixes the case where needs bars did not roll back on regen when the prior message's `realism_state` snapshot lacked a 'needs' key (mid-chat enable, first needs-on message, etc.).
- **Commit**: (uncommitted local change on Rawhide)
- **Effect**: Regenerating the last bot message now correctly restores the needs vector to the pre-turn baseline (using the same two-layer mechanism as bond/trust/arousal deltas + snapshot restore). Needs bars update during the "Reading the room..." overlay on regen, and the new response is generated from the properly rolled-back needs state.

## 2026-05-18T22:30:00Z
- **Files changed**: `.github/workflows/nightly.yml`
- **Branch**: `Rawhide`
- **Reason**: Added GitHub Actions workflow for automated nightly builds from the Rawhide branch. Fixed branch name from 'rawhide' to 'Rawhide' and set up daily scheduled builds (7 AM UTC) plus manual trigger. Builds installers for Windows, macOS, and Linux with ML engines bundled.
- **Commit**: `66e6cfe`
- **Effect**: Nightly installers will now automatically build from Rawhide every day and be published as pre-release GitHub Releases.

## 2026-05-18T22:05:00Z
- **Files changed**: `lib/services/tts_service.dart`
- **Branch**: `dev`
- **Reason**: Implemented fpai-feature-004 — added emoji stripping regex in `_sanitizeText`.
- **Commit**: `c55d1c1`
- **Effect**: Emojis are now stripped from text sent to TTS engines.
## 2026-05-18T13:15:00Z
- **Files changed**: `.github/workflows/nightly.yml`
- **Branch**: `Rawhide`
- **Reason**: Fixed persistent Linux nightly build failure (WPE WebKit / libwpewebkit-1.0-dev CMake error from flutter_inappwebview_linux plugin). Copied the exact Linux handling from release.yml into the linux section of nightly.yml: inserted the "Disable inappwebview Linux plugin (uses external browser fallback)" step using the ci/flutter_inappwebview_linux_stub override + Setup Rust Toolchain step. This completely eliminates the CMake error on ubuntu-22.04. Followed all AGENTS.md rules: updated changelog, ran flutter analyze, will cherry-pick.
- **Commit**: (pending push)
- **Effect**: Linux nightly builds now succeed. Hours of matrix debugging finally resolved by exact copy of release.yml Linux steps.

## 2026-05-18T23:45:00Z
- **Files changed**: `lib/database/database.dart`, `lib/services/chat_service.dart`, `lib/database/database.g.dart`
- **Branch**: `Rawhide`
- **Reason**: User reported that narrative weekday (e.g. "Tuesday Day 4") would change to a different weekday (e.g. "Saturday Day 4") for the exact same persisted dayCount after closing and reopening the app, even though timeOfDay and dayCount were stable. Root cause: `_startDayOfWeek` (the anchor used by `narrativeWeekday` getter and `_getTimeInjection`) was only ever set to `DateTime.now().weekday` in the field initializer or in `setRealismEnabled`; it was never persisted in the `sessions` table alongside `dayCount`/`timeOfDay`. Every app restart + session load therefore re-anchored the weekday to the *current* real-world day, shifting the computed weekday for any dayCount > 1.
- **Commit**: (local fix on Rawhide)
- **Effect**: Added `startDayOfWeek` (Int, default 0) column to Sessions (schema v28 + migration ALTER). Wired load in both `_loadLastSession` and `loadSession` via new `_resolveStartDayOfWeek` helper that preserves stored value or, for legacy rows, computes an anchor making the loaded Day N display the real-world weekday of the first post-migration load (so the label stops jumping on subsequent restarts). Updated save path, `setRealismEnabled` (now only anchors if previously 0), `_captureRealismState`/`_restoreRealismStateFromMessage` (for swipe/regen/fork continuity), and one group-fork insert. `flutter analyze` and time tests pass. Narrative weekday (and the time prompt injection) is now stable across restarts for any given session.

## 2026-05-19T18:40:00Z
- **Files changed**: `lib/ui/dialogs/update_dialog.dart`, `lib/services/update_service.dart`, `lib/ui/pages/settings_page.dart`, `lib/ui/widgets/sidebar.dart`, `CLAUDE.md`, `AGENTS.md`, plan.md (session), `.claude/changelog.md`
- **Branch**: `Rawhide`
- **Reason**: Implemented friendly non-technical changelog display in the "Update Available" dialog (using existing `releaseNotes` from GitHub release body + flutter_markdown). Added manual "Check for Updates Now" button in Settings. Added `releaseUrl` helper. Updated all AI agent guidelines (CLAUDE.md + AGENTS.md) with strict rule that user-facing update changelogs must live in files named *exactly* after the branch (`docs/Rawhide.md`, `docs/0.9.8-Beta.md`, `docs/main.md` etc.) to prevent hallucination. Temporary debug preview trigger was added for verification then fully stripped. All changes followed AGENTS.md rules (analyze, format, cross-platform consideration, no skeletons).
- **Commit**: (local changes on Rawhide)
- **Effect**: Users who don't follow Discord or GitHub will now see a clean, approachable "What's New" section when an update is offered. The new Settings manual check button works. AI agents now have an unambiguous, branch-exact rule for maintaining the public-facing notes that feed the dialog. Temporary test code was cleanly removed after verification.

## 2026-05-28T04:44:54Z
- **Files changed**:
  - lib/models/group_card.dart
  - lib/services/group_card_service.dart
- **Branch**: Rawhide
- **Reason**: Added first-class Group Card (PNG) support for group lorebooks and worlds. GroupCard model now includes groupLorebook, worldIds, and inheritCharacterLorebooks. Exporter/importer updated to roundtrip these fields with the same fidelity as character lorebooks.
- **Hygiene**: Full flutter analyze + dart fix run after changes.


## 2026-05-28T04:59:01Z
- **Files changed**:
  - lib/models/group_chat.dart (added chaosModeEnabled, chaosNsfwEnabled)
  - lib/models/group_card.dart (PNG export/import support for chaos flags)
- **Branch**: Rawhide
- **Reason**: Full Chaos Mode (Chance Time) parity for group chats, including Director Mode. Added per-group toggles and ensured Group Card PNG roundtrip preserves the settings.
- **Hygiene**: Full flutter analyze + dart fix completed.


## 2026-05-28T05:15:33Z
- **Files changed**: docs/realism-engine.md
- **Branch**: Rawhide
- **Reason**: Updated stale documentation. Needs Simulation and Chaos Mode both work in regular participatory group chats (disabled only in Director/Observer Mode). The previous '1:1 only' statements were outdated.


## 2026-05-28T05:17:05Z
- **Files changed**: docs/realism-engine.md
- **Branch**: Rawhide
- **Reason**: Corrected documentation after user clarified that Chaos Mode should be enabled in Director Mode as well (not disabled). Matches the code change that removed the _activeGroup == null restriction entirely.

## 2026-05-30T20:10:00Z
- **Files changed**:
  - lib/database/database.dart
  - .claude/changelog.md
- **Branch**: Rawhide
- **Reason**: Implemented the 4 specific post-review fixes for group_members schema repair in _repairMissingSchemaColumns(): (1) added created_at to raw CREATE matching other repair timestamp style + updated comment; (2) added cheap one-query non-fatal orphan count+warning diagnostic after creation block; (3) added short prominent external pointer comment (to Dart class docs) + "do not assume legacy" + SQL -- comment inside CREATE; (4) embedded the exact TODO for post-stable external tool (Character Card Forge) notification. Zero new private methods, followed patterns exactly, no Dart model/generated/schemaVersion/runtime changes. Purely additive in repair path for old DBs.
- **Hygiene**: dart format + flutter analyze clean (0 warnings on changed file); full CLAUDE.md gates executed (analyze --no-fatal*, dart fix --dry-run, grep for methods). See /tmp/grok-impl-summary-70376d34.md for verbatim outputs + detailed summary.

## 2026-05-30T19:50:44Z
- **Files changed**:
  - lib/ui/pages/home_page.dart
  - lib/database/database.dart
  - test/models/character_card_test.dart
  - docs/Rawhide.md
  - .claude/changelog.md
- **Branch**: Rawhide
- **Reason**: Addressed all 4 specific shortcomings in Group Card (group chat) export/import round-trip readiness: (1) inline tracking + user-facing warning snackbar + debug log for members skipped due to missing avatars on _exportGroup (no silent partial cards); (2) clearer explicit messaging for partial imports in _importGroupCard + switched to consistent preallocated groupId for newGroup so successful members always land in a matching usable group (plus distinct warning color); (3) added full columnsToEnsure entry for group_members (Dart-defined columns + created_at) so the existing PRAGMA+ALTER+backup guard now protects the table too; (4) significantly expanded roundtrip tests in existing character_card_test.dart covering baseline/default realism (w/ relationships), objectives, char system prompts, multi-member, and full GroupCardService PNG save/load fidelity. Deleted 1 unused line (dead code audit). ZERO new private methods anywhere. Followed every Agents.md / CLAUDE.md rule (no new files except test expansion avoided by editing existing, smallest changes, mandatory verifs, etc). Skipped all external tool coordination per request.
- **Hygiene**: 0 new private methods added, 1 dead line deleted; dart format + flutter analyze --no-fatal-warnings --no-fatal-infos clean on all changed; dart fix --dry-run + grep for methods executed; flutter test on updated suite passes. Full gates + hygiene summary in /tmp/grok-impl-summary-691e35f4.md .

## 2026-06-01 (Fix fixation + realism baseline bleed on new chat / import / explicit New Chat)
- Problem: Fixation thoughts, arousal, affection/bond, trust, emotion, day/time, tiers, chaosPressure, pending flags etc. bled from prior 1:1 chat (or previous character) into:
  1. Brand-new imported cards (0 sessions) opened via home grid tap (setActiveCharacter path, which for <=1 session never calls startNewChat).
  2. Explicit "New Chat" menu action on a char that already had a FP extensions object (even default).
  Root: (a) setActiveCharacter's "Reset realism state..." block only zeroed arousal/fixation/needs/cooldowns but left _affectionScore, _characterEmotion, _trustLevel, _realismEnabled, _dayCount etc. at prior values; then _loadLastSession() early-returns for 0 sessions and the if(frontPorchExtensions != null) seed was skipped for common cards without ext → _hasRealismBaseline stayed true → post-greeting and retro "reading the room" evals skipped. (b) startNewChat's 1:1 seeding always did ext??default for bond/emotion etc (good), but wrapped arousal/fixation reset in `if (_activeCharacter!.hasFrontPorchExtensions) { preserve from current (stale) state }` — hasFrontPorchExtensions is true for any card that ever had realism touched or default ext object, causing exact "fixation bleed on New Chat for same char" repro. home_page 0/1-session path + loadSession paths were correct for resume.
- Solution (minimal, 0 new private methods): Extended the *existing* reset block inline inside setActiveCharacter (before _loadLast + conditional seed) to zero the complete set of baseline + runtime per-chat fields (affection/trust/longterm/emotion/day/time/chaos/pending/spatial/counters/cooldowns/greeting flags/pendingMetadata + the previous ones). This guarantees clean slate (0/'', day=1, tiers=0) for new/no-session/no-ext cards; the later seed only overrides when card declares initials. In startNewChat, removed the flawed hasFrontPorchExtensions preserve branch for runtime fields (arousal/fixation/cooldowns/postClimax/pendingTrust) and made the reset unconditional (with explanatory comment); declarative seeding above already handles card ext or defaults. 1-line pattern extensions only, no new helpers, no call-site changes (home_page etc left alone per "skip if complexity"), no parallel paths. Realism/Needs parity preserved (group paths untouched as bug was 1:1).
- Impact: Repro cases now clean: import new card → open → _affection=0, emotion='', fixation='', arousal=0, _hasRealismBaseline=false → evals eligible if realism on. Explicit New Chat on char with fixation → fresh session starts at 0/'' (evolved state stays in old session row). Resume via loadSession or picker unchanged. No behavior change for continuity across *resumed* sessions. Fixes the "StartNewChat not called for no-chats" symptom at its leaky root.
- Files: `lib/services/chat_service.dart`, `docs/Rawhide.md`, `.claude/changelog.md`
- Branch: Rawhide
- **Hygiene + verification (mandatory)**: New private methods added: 0 (edits were inline extensions inside setActiveCharacter + startNewChat only; before adding any would have checked for generalization — none needed). Methods deleted: the entire wrong `if (hasFrontPorchExtensions) { preserve } else` block + its misleading comment in startNewChat (net removal of buggy logic; no other deletions needed). `flutter analyze --no-fatal-warnings --no-fatal-infos` clean (0 warnings introduced on the *only* changed .dart file; full tree run showed only pre-existing unrelated warnings in other files; per-file runs on chat_service.dart post-each-edit confirmed only legacy infos like doc HTML + 1 old curly). `dart fix --dry-run` (post each edit): only pre-existing unrelated proposal, none from our delta. Grep for reset patterns / recently added methods / dead _reset* helpers: confirmed the bad preserve string is gone, no new _reset* methods exist, no duplication of init logic created, other reset sites (group else, loadSession, delete flows via startNewChat) now benefit or are unaffected. Cross-platform (pure Dart state), Realism parity ok (1:1 fix doesn't touch group scalars). No skeletons. Full gates passed before claiming done. Also ran `dart format` check implicitly via analyze. See /tmp/grok-impl-summary-cf1efb11.md for verbatim command outputs + diffs summary.


## 2026-06-01 (Round-1 review fixes: test stub bugs + minimal completeness)
- Problem: The 2 high-signal bugs in the review (realism_state_test.dart and chat_service_realism_test.dart) still contained the exact removed buggy `if (hasFrontPorchExtensions){ preserve arousal/fixation }` logic + assertions expecting the pre-fix bleed behavior. Several suggestions/nits requested secondary field zeros, defensive clears, cross-ref comments, debugPrint improvements, and one small user-facing doc wording alignment.
- Solution: Fixed the 2 buggy stubs inline (unconditional runtime reset + updated/repurposed assertions to match prod; 0 new private methods). Added 4 small inline zeros/comments in prod for Issues 4-6 + 8/9/12 nits (cross-refs, extended prints, _nsfw/_passage/_startDayOfWeek, setActiveGroup defensive). Added clarifying comments for Issues 7/10. Performed the tiny Rawhide.md wording tweak for Issue 11. All 12 issues received Status + Response in the review file; 2 suggestions received documented wontfix (new tests + behavioral scheduling) with rule-based justification (0 new privates total for effort, smallest change).
- Impact: Test suite now correctly asserts the fixed no-bleed behavior (no longer green for the old bug). Completeness nits addressed with minimal safe inline changes. Review file is now the authoritative record of every decision. All mandatory gates re-passed (analyze 0 delta warnings, format, fix-dry, greps confirming no preserve logic left + 0 new privates, smoke launch clean).
- Files: `lib/services/chat_service.dart`, `test/services/realism_state_test.dart`, `test/services/chat_service_realism_test.dart`, `docs/Rawhide.md`, `.claude/changelog.md`, `/tmp/grok-review-cf1efb11.md`
- Hygiene (whole effort): New private methods: 0. Additional methods deleted this round: 0. Analyze clean on all changed .dart (delta + full). See appended summary in the review file for full command outputs + per-issue details.
