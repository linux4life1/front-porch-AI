# God File Refactoring Guide

> **Important (2026-06)**: Structural refactoring is done **first**. Full Riverpod migration happens **after** the god files have been broken apart. This separation significantly reduces risk. See the "Riverpod Migration After Refactoring" section at the bottom of this document.

## Safe Experimentation & Escape Hatches (Critical)

**Never do this work directly on your main `Rawhide` checkout.**

Recommended safe workflow:

```bash
# From the root of the repo
git worktree add ../front-porch-riverpod-refactor -b riverpod-refactor-experiment

cd ../front-porch-riverpod-refactor
# All dangerous refactoring + Riverpod conversion happens here

# When you want to throw it away completely:
cd ..
rm -rf front-porch-riverpod-refactor
git worktree prune
```

**Benefits of this approach:**
- Completely isolated working directory and IDE instance.
- You can run `flutter run -d macos`, full test suites, and `flutter analyze` without affecting your daily driver Rawhide branch.
- If things go sideways, you can nuke the entire experiment in seconds with zero risk to your main work.
- You can still push the experiment branch (`git push -u origin riverpod-refactor-experiment`) for review or CI runs without polluting Rawhide.

Alternative lighter options (if you don't want worktrees):
- Create a normal branch: `git checkout -b riverpod-refactor-experiment`
- Commit very frequently with clear messages.
- Use `git stash` aggressively before pulling latest Rawhide.

**Rule**: If a day of work on the experiment branch feels like it's making things worse, delete the worktree/branch and start fresh with smaller scope. There is no sunk cost.

## Guiding Principles

1. **Never refactor and add features simultaneously** — each PR does one thing.
2. **Extract, don't rewrite** — pure mechanical moves with no behavioral changes during the structural phase.
3. **Each stage is independently mergeable and testable** — no half-broken main.
4. **Keep imports compiling at every commit** — remove old file only after all references are updated.
5. **One god file per major stage** — keep scope manageable.
6. **Structure first, Riverpod later** — Complete the god file refactoring using the existing `ChangeNotifier` / `Provider` patterns. Full Riverpod migration is a separate effort that begins only after the major extractions are done (see final section).
7. **No file stem collides with a folder name**.
8. **Tests are mandatory and first-class** — Every extraction PR must include or significantly expand automated tests. The goal is to reach a point where the vast majority of user-facing behavior is covered by tests so manual verification is minimized or eliminated.

## Name Conflict Map

Before creating any new directory, verify there is no existing file (minus extension) with the same name in the parent directory.

| New folder | Collides with | Safe? |
|---|---|---|
| `lib/services/chat/` | `chat_service.dart` — different stem | Yes |
| `lib/ui/chat_components/` | nothing | Yes |
| `lib/ui/character_creator/` | `character_creator_page.dart` — different stem | Yes |
| `lib/ui/settings/` | `settings_page.dart` — different stem | Yes |
| `lib/services/web_server/` | `web_server_service.dart` — different stem | Yes |
| `lib/services/storage/` | `storage_service.dart` — different stem | Yes |

## Testing Requirements (Mandatory for Every Stage)

The explicit goal of the testing strategy in this plan is to reach a point where **most user-facing features do not require manual verification** after each refactoring PR.

Every PR that touches god file logic **must** add or meaningfully expand automated tests. Pure mechanical extractions with zero new test coverage are not acceptable.

### Core Testing Philosophy

- **Behavior preservation is the #1 priority.** Extracted code must behave identically to the original.
- **Focus test effort on high-value, high-risk areas first**: Realism Engine, Needs simulation, Chaos Mode, Group chat behavior, Character Creator flows, and Settings persistence.
- **Use existing test infrastructure** where it exists (especially the realism engine test suite).
- **Layered testing**: Unit tests for new services + integration tests that exercise the public surface of `ChatService` / `ChatPage`.

### Minimum Test Deliverables per Stage

**Stage 1 (Models)**
- Unit tests for `ChatMessage` serialization/deserialization and any helper methods moved with it.

**Stage 2 (UI Widgets from chat_page.dart)**
- Widget tests for every extracted major component (sidebar sections, message bubbles, overlays, etc.).
- At least some golden tests or screenshot-style verification for complex visual components (especially sidebar sections and realism-related UI).
- Tests that verify the widgets still receive the correct data when used inside the real `ChatPage`.

**Stage 3 (Domain Services from chat_service.dart) — Highest Test Priority**
- Each extracted service must have its own test file.
- **Critical areas that must have strong test coverage**:
  - Needs decay, stepping, catastrophe, and post-climax logic
  - Chaos Mode / Chance Time triggering and event selection
  - Realism evaluation paths (bond, trust, emotion, fixation, one-shot)
  - Time progression and day-of-week logic
  - Lorebook injection / keyword matching
  - Objective system
  - Summary and fact extraction
- Use the existing `chat_service_realism_engine_test.dart` pattern as a model. Extend it rather than duplicating.
- After each major service extraction, run the full realism + group chat test suites.

**Stage 4 (Character Creator)**
- End-to-end tests for all three creation modes (Quick, Guided, Automated).
- Tests covering realism baseline seeding during creation.
- Tests for the review step (especially avatar and card editing).

**Stage 5 (Settings)**
- Tests for settings persistence (read on load, write on change, survive restart).
- Per-tab behavior tests where the tab contains non-trivial logic.

**Stages 6 & 7**
- Appropriate unit tests for the extracted handlers and settings objects.

### General Rules

- New services should be easy to instantiate in tests (avoid hard global dependencies).
- Prefer constructor injection or small factory functions over `Provider.of` inside the extracted classes during the structural phase.
- Every PR description must include a "Testing" section that lists what new or updated tests were added.
- If a PR cannot include good tests for a piece of logic (rare), it must be explicitly justified and a follow-up test PR created.

**Target State**: After all seven stages, a developer should be able to make structural changes to these areas with high confidence that automated tests will catch behavioral regressions in chat, realism, needs, group chat, and creator flows. Manual testing should be limited to visual polish and brand-new features.

## Deprecation Shim Pattern

When extracting code from a god class, leave a forwarding shim so existing callers continue to compile:

```dart
// In the original god class, after extraction:
@Deprecated('Access via NeedsSimulationService directly')
Map<String, int> get needsVector => _needsSimulation.needsVector;
```

This makes extraction a **pure additive change** — nothing breaks, nothing moves. Old callers can be migrated to the new import at leisure. The shims are removed in a final cleanup PR once all references are updated.

## Extraction Priority Order (file-by-file)

The order below maximises early wins (reducing the largest files first) while keeping risk low. All stages use the existing `ChangeNotifier` / `Provider` architecture. Riverpod conversion is deliberately deferred (see final section).

| Stage | God file | ~Lines | New location | Strategy | Test Requirements |
|-------|----------|--------|--------------|----------|-------------------|
| 1 | `chat_service.dart` — enums + model | 12.6K | `lib/models/chat_message.dart` | Lift top-level declarations only | Unit tests for any serialization / logic |
| 2 | `chat_page.dart` — sidebar sections | 12K | `lib/ui/chat_components/` | One widget per file | Widget tests for extracted components (focus on sidebar sections, overlays, bubbles) |
| 3 | `chat_service.dart` — domain services | 12.6K | `lib/services/chat/` | Plain class extraction (still ChangeNotifier-based) | **High priority**: Unit + integration tests, especially realism, needs, chaos, objectives |
| 4 | `character_creator_page.dart` — steps | 8K | `lib/ui/character_creator/` | State object + step widgets | Full creator flow tests (all paths: Quick/Guided/Auto) |
| 5 | `settings_page.dart` — tabs | 6K | `lib/ui/settings/` | Tab files + dialog files | Settings persistence + tab-specific behavior tests |
| 6 | `web_server_service.dart` — route handlers | 5.8K | `lib/services/web_server/` | Handler classes per route group | Route handler unit tests |
| 7 | `storage_service.dart` — domain settings | 1.9K | `lib/services/storage/` | Plain settings classes | Settings read/write roundtrip tests |

---

## Stage 1: Lift `ChatMessage` and enums from `chat_service.dart`

**Goal:** Extract `ChatMessage`, `GenerationMode`, `GenerationPhase` into their own file.

**Why first:** Zero behavioural change. Teaches the extraction pattern on the safest possible target.

### Steps

1. Create `lib/models/chat_message.dart` containing the three declarations.
2. Add `export 'chat_message.dart';` to `lib/models/models.dart`.
3. In `chat_service.dart`, replace the three declarations with `import 'package:front_porch_ai/models/models.dart';` (or `chat_message.dart`).
4. Run `grep -rn 'ChatMessage' lib/ --include="*.dart"` to find all other files referencing `ChatMessage`. Update them to import from the barrel or the new file.
5. Delete the three declarations from `chat_service.dart`.
6. Run `flutter analyze` — zero warnings required.

### Verification

- All existing imports of `chat_service.dart` that also use `ChatMessage` must have the new import added (whether or not they already import `models.dart`).
- Session save/load and display must produce identical results.

---

## Stage 2: Extract `chat_page.dart` private widgets

**Goal:** Move each private widget class into its own public file under `lib/ui/chat_components/`.

### Directory layout after extraction

```
lib/ui/chat_components/
├── bubbles/
│   ├── message_bubble.dart         ← _MessageBubble, _MessageBubbleState
│   ├── styled_chat_message.dart    ← _StyledChatMessage
│   └── external_image_widget.dart  ← _ExternalImageWidget, _ExternalImageWidgetState
├── sidebar/
│   ├── sidebar_section.dart        ← _SidebarSection, _CollapsibleSidebarSection
│   ├── lorebook_section.dart       ← _LorebookSection, _GroupLorebookSection
│   ├── scene_time_section.dart     ← _SceneTimeSection
│   ├── author_note_section.dart    ← _AuthorNoteSection
│   ├── summary_section.dart        ← _SummarySection
│   ├── memory_section.dart         ← _MemorySection
│   ├── realism_section.dart        ← _RealismSection
│   ├── nsfw_section.dart           ← _NsfwEnhancementsSection
│   ├── chaos_mode_section.dart     ← _ChaosModeSection
│   └── objective_section.dart      ← _ObjectiveSection, _EditableTaskRow
├── overlays/
│   ├── rag_setup_dialog.dart       ← _RagSetupDialog
│   ├── realism_processing_overlay.dart  ← _RealismProcessingOverlay
│   ├── objective_check_overlay.dart     ← _ObjectiveCheckOverlay
│   └── generation_status_bar.dart       ← _GenerationStatusBar, _PulsingIcon
└── widgets/
    ├── eval_pill.dart              ← _EvalPill, _AnimatedEvalPill
    └── settings_menu_item.dart     ← _SettingsMenuItem
```

### Extraction pattern (per commit)

1. Create the new file. Copy the widget class(es) verbatim, minus the leading `_`.
2. Add whatever imports were implicitly available from `chat_page.dart`'s top-of-file.
3. In `chat_page.dart`, replace the class body with a re-export or a `typedef` alias:
   ```dart
   typedef MessageBubble = _MessageBubble; // temporary, removed in cleanup
   ```
   Alternatively, replace constructor calls with new public names and leave the old private class dead code (to be removed in the cleanup PR).
4. `flutter analyze` must pass.
5. Repeat for each widget in the order listed above, one commit each.

### Cleanup commit (2z)

After all widgets are extracted:
1. Delete all dead code from `chat_page.dart`.
2. `flutter analyze` — zero warnings.
3. Smoke-test: open a 1:1 chat and a group chat, verify all sidebar sections render, overlays appear, messages display.

---

## Stage 3: Split `chat_service.dart` into domain services (Highest Risk Structural Stage)

This is the most consequential structural stage. We are breaking apart the largest god class in the app while preserving all existing behavior.

**Important**: All work in this stage must stay within the current `ChangeNotifier` / `Provider` architecture. Riverpod conversion of these services happens **after** Stage 7 is complete (see the Riverpod section at the end of this document).

**Do not attempt this as a single PR.** Break it into multiple focused PRs.

### Critical Rule for Stage 3

Each extracted service must be a **plain Dart class** (or small set of classes). `ChatService` continues to own instances of them via private fields and delegates to them. This keeps the provider tree stable during the risky extraction phase.

### Directory layout

```
lib/services/chat/
├── needs_simulation.dart      ← needs decay, stepping, catastrophe, climax detection
├── chaos_mode_service.dart    ← chance time, pressure gauge, event pools
├── relationship_service.dart  ← affection, trust, inter-character feelings, scores
├── expression_classifier.dart ← emotion-to-expression (LLM + ONNX)
├── time_service.dart          ← time passage, nudge, day-of-week resolution
├── nsfw_service.dart          ← cooldown, arousal tier
├── lorebook_scanner.dart      ← keyword matching, depth tracking
├── prompt_injection/          ← all _get*Injection builders (8 files)
│   ├── author_note_builder.dart
│   ├── relationship_injection.dart
│   ├── emotion_injection.dart
│   ├── behavioral_injection.dart
│   ├── time_injection.dart
│   ├── nsfw_injection.dart
│   ├── chaos_injection.dart
│   └── needs_injection.dart
├── llm_eval_engine.dart       ← _fireLLMEval, JSON extractors, _stripThinkBlocks
├── needs_impact_evaluator.dart ← consolidated needs impact (LLM + Proposal A table + modifiers); sibling to needs_simulation
├── realism_evals.dart         ← 5 evaluation calls (rel, emotion, phys, narr, one-shot)
├── objective_service.dart     ← objectives CRUD, tasks, completion checking
├── summary_service.dart       ← auto-summary generation (deleted in Journal phase 1)
├── fact_extraction.dart       ← fact extraction + consolidation (deleted in Journal phase 1)
└── evolution_service.dart     ← trigger, extract, reset character evolution
```

### Recommended Sub-Stage Order + Testing Focus

Extract **leaf dependencies first** (services with the fewest internal dependencies).

| Order | File | Depends on |
|---|---|---|
| 1 | `needs_simulation.dart` | nothing |
| 2 | `chaos_mode_service.dart` | nothing |
| 3 | `relationship_service.dart` | nothing |
| 4 | `expression_classifier.dart` | nothing |
| 5 | `time_service.dart` | nothing |
| 6 | `nsfw_service.dart` | nothing |
| 7 | `lorebook_scanner.dart` | nothing |
| 8 | All `prompt_injection/*` | needs_simulation, time_service, etc. |
| 9 | `llm_eval_engine.dart` | prompt_injection (for prompt building) |
| 9b | `needs_impact_evaluator.dart` | needs_simulation (apply + context), llm_eval_engine (via fire/strip/extract cbs in god wiring); grouped under needs domain (sibling to needs_simulation) |
| 10 | `realism_evals.dart` | llm_eval_engine |
| 11 | `objective_service.dart` | llm_eval_engine |
| 12 | `summary_service.dart` | llm_eval_engine | (later deleted — replaced by the Journal, docs/design/journal-memory.md) |
| 13 | `fact_extraction.dart` | llm_eval_engine | (later deleted — replaced by the Journal) |
| 14 | `evolution_service.dart` | llm_eval_engine |
| 15 | Refactor remaining `ChatService` | all of the above | (completed: audit + pure cleanup of god orchestration/_groupRealism/core flows (no new leaf/extraction to preserve exactly 15 void _ thins+coord surface per plan/CLAUDE); dead/obsolete comment removal; thin consistency; full Step 15 record + gates in docs/refactor-god-file-modularization.md) |

For each extracted service in this stage:

1. Create the new plain class(es).
2. Add comprehensive unit + integration tests (especially for realism, needs, and chaos logic).
3. Wire the new class into `ChatService` (usually via constructor or late final).
4. Add `@Deprecated` forwarding shims on `ChatService` for any public API that moved.
5. Run the full realism engine test suite + manual smoke test of 1:1 and group chats.
6. Only then move to the next service.

**Strong recommendation**: After extracting Needs + Chaos + Relationships (the first three), pause for a serious round of integration testing and manual verification of realism and group chat behavior before continuing. Stage 3 is where most behavioral risk lives.

### Extraction pattern (per commit)

1. Create the new file. Copy all methods + private fields for that domain.
2. The constructor receives whatever state it needs (scalar values, other services). For the initial extraction, pass the whole `ChatService` as a parent reference via an interface or callback. (Granular callbacks are an acceptable implementation for the initial leaf per the Stage 3 needs_simulation precedent: they avoid import cycles, enable isolated unit tests with a small factory helper, and remain friendly to future extractions that will shrink the surface. The plan text is satisfied by documenting the choice; see docs/refactor-god-file-modularization.md Fix Round 1 and the sim header for rationale.)
3. In `ChatService`:
   ```dart
   late final _needsSimulation = NeedsSimulation(
     onNotify: notifyListeners,
     // ... other deps
   );

   // Deprecated shim
   @Deprecated('Access via NeedsSimulationService directly')
   Map<String, int> get needsVector => _needsSimulation.needsVector;
   ```
4. `flutter analyze` — zero warnings.
5. Verify: send a message in a chat with realism mode on. Needs should decay identically.

### Communication pattern

Extracted services signal back to `ChatService` via a callback function (e.g. `VoidCallback onNotify`, or specific callbacks like `Future<void> Function(String prompt) onInjectPrompt`). This keeps them testable and decoupled from the parent.

---

## Stage 4: Extract `character_creator_page.dart` steps

### Directory layout

```
lib/ui/character_creator/
├── character_creator_page.dart       ← thin shell (~200 lines)
├── creator_state.dart                ← ChangeNotifier with all 60+ shared fields
├── steps/
│   ├── setup_step.dart               ← backend/model selection
│   ├── mode_select_step.dart         ← Auto/Guided/Quick picker
│   ├── quick_config_step.dart        ← minimal config
│   ├── guided_config_step.dart       ← free-text config
│   ├── automated_config_step.dart    ← full structured form
│   ├── generating_step.dart          ← progress + streaming preview
│   ├── realism_step.dart             ← initial realism state
│   └── review_step.dart              ← avatar + editable card
└── widgets/
    ├── backend_chip.dart             ← backend selector pill
    ├── mode_card.dart                 ← mode selection card
    └── styled_text_field.dart         ← auto-saving text field wrapper
```

### Strategy

1. Extract `creator_state.dart` first — move all `_pref*` keys, `_loadSavedState`, `_saveState`, all step-index and form-field fields. This is a pure lift.
2. Extract `review_step.dart` first (largest at ~1,900 lines).
3. Extract each remaining step.
4. Main page becomes an `AnimatedSwitcher` keyed on `creatorState.currentStep`, building the appropriate step widget.

---

## Stage 5: Extract `settings_page.dart` tabs

### Directory layout

```
lib/ui/settings/
├── settings_page.dart                ← TabBar shell (~150 lines)
├── tabs/
│   ├── general_tab.dart              ← dark mode, font, colours, prompts
│   ├── generation_tab.dart           ← temperature, penalties, limits
│   ├── voice_media_tab.dart          ← TTS, STT, image gen, expressions
│   ├── backend_tab.dart              ← backend mode, API config, model select
│   └── advanced_tab.dart             ← storage, web server, GPU, launch flags
├── dialogs/
│   ├── color_picker_dialog.dart      ← _showColorPicker
│   ├── prompt_save_dialog.dart       ← _showSavePromptDialog
│   ├── prompt_delete_dialog.dart     ← _showDeletePromptDialog
│   └── model_search_dialog.dart      ← _showModelSearchDialog
└── widgets/
    ├── color_row.dart                ← _buildColorRow
    ├── vram_gauge.dart               ← VRAM bar + legend
    ├── mode_chip.dart                ← _buildModeChip
    ├── preset_chip.dart              ← _buildPresetChip
    ├── api_preset_chip.dart          ← _buildApiPresetChip
    ├── slider_setting.dart           ← _buildSlider
    └── section_header.dart           ← _buildSectionHeader
```

### Strategy

1. Extract `voice_media_tab.dart` first (largest tab at ~1,050 lines).
2. Extract helper dialogs (`color_picker_dialog.dart`).
3. Extract remaining tabs.
4. Keep `_SettingsPageState` owning shared state (controllers, currently selected model, etc.). Pass it to tabs via constructor or `Provider`.

---

## Stage 6: Extract `web_server_service.dart` route handlers

### Directory layout

```
lib/services/web_server/
├── web_server_service.dart        ← server lifecycle, middleware wiring, router setup (~400 lines)
├── middleware/
│   ├── auth_middleware.dart       ← PIN login, Bearer token validation
│   ├── cors_middleware.dart
│   └── client_tracker.dart        ← active-client state tracking
├── routes/
│   ├── auth_routes.dart
│   ├── character_routes.dart
│   ├── chat_routes.dart
│   ├── settings_routes.dart
│   ├── backend_routes.dart
│   ├── tts_routes.dart
│   ├── image_gen_routes.dart
│   ├── story_routes.dart
│   ├── cloud_sync_routes.dart
│   └── ... (per feature group)
├── sse/
│   ├── chargen_stream.dart
│   └── story_pipeline_stream.dart
└── helpers/
    ├── image_cache.dart
    ├── web_asset_server.dart
    └── route_utils.dart           ← _crc32, _basename, _normalize*, _parseUserAgent
```

### Strategy

1. Each route group becomes a class with a constructor that receives `WebServerService` (for service access) and a `Router` to register handlers.
2. The main `WebServerService.start()` constructs the router, instantiates all route classes, and passes each the router.
3. SSE streaming classes are extracted last — they're the most coupled to shared mutable state (`_chargenStatus`, etc.).

---

## Stage 7: Decompose `storage_service.dart` into domain settings

### Directory layout

```
lib/services/storage/
├── storage_service.dart           ← directory management only (~300 lines)
├── directories.dart               ← rootPath, modelsDir, chatsDir, etc.
├── settings/
│   ├── backend_settings.dart
│   ├── generation_settings.dart
│   ├── ui_settings.dart
│   ├── tts_settings.dart
│   ├── stt_settings.dart
│   ├── image_gen_settings.dart
│   ├── expression_settings.dart
│   ├── web_server_settings.dart
│   ├── cloud_sync_settings.dart
│   ├── realism_settings.dart
│   ├── memory_settings.dart       ← RAG, summary, evolution intervals
│   └── preset_settings.dart       ← system prompts, kcpps presets
```

### Strategy

1. Each settings file follows a consistent pattern — private field, public getter, `Future<void> setX(value)` that writes to `SharedPreferences` and calls `notifyListeners()`.
2. A shared `SettingsBase` mixin provides the `_prefs` reference, key prefix, and `notifyListeners`.
3. `StorageService` keeps backward-compat shims:
   ```dart
   @Deprecated('Use TtsSettings instead')
   Future<void> setTtsEnabled(bool v) => _ttsSettings.setEnabled(v);
   ```
4. Once all shims are migrated by callers, `StorageService` drops to pure directory management.

### Why not use multiple `ChangeNotifier`s here?

Same reasoning as Stage 3 — `StorageService` already notifies listeners on every setter. Widgets that need a subset of settings use `context.select`. Premature decomposition to multiple notifiers adds provider tree depth with no measurable gain. Extract as plain settings classes, consider promotion later if profiling warrants it.

---

## Rollback Plan

If a PR introduces regressions:

1. **Revert the extraction commit** — old code is intact in the parent commit.
2. Never fix forward in the same PR. Merge the revert, then re-apply with smaller scope.
3. Pure mechanical extractions never touch `.g.dart` files, database schema, or `pubspec.yaml`, so rollbacks are safe and conflict-free.

## Verification Checklist (every PR)

- [ ] `flutter analyze` — zero warnings (new or existing).
- [ ] `flutter test` — all existing tests pass (especially realism engine and group chat tests).
- [ ] New or expanded tests were added for the extracted logic.
- [ ] Manual smoke test of the affected flows (chat, realism, needs, group chat, creator).
- [ ] No new files added to `lib/services/services.dart` barrel unless they are used from 3+ locations.
- [ ] No state-management pattern change (still `ChangeNotifier`, not Riverpod).
- [ ] Old API preserved via `@Deprecated` shim where callers exist outside the extracted file.

## Lint Hygiene Pass (Stage 1 Worktree)

During the god-file refactoring on `stage1-experiment`, a dedicated cleanup eliminated all warnings (unused_*, dead_code) from group_settings_dialog.dart and chat_page.dart by removing confirmed-dead placeholder methods/fields left from 2026 UX changes. Also fixed:

- All 9 curly_braces_in_flow_control_structures (mechanical blocks added in tier color helper).
- ~23 easy `withOpacity` → `withValues(alpha:)` deprecations limited to 4 small files (stable_db_import_dialog, chance_time_overlay, app_text_field, slider_with_input) — no god-file churn.
- 12+ unintended_html_in_doc_comment via minimal &lt;/&gt; entities or {groupId} in path/type examples (database, models/chat_message + group_member, embedding_sidecar) — no prompt string changes or large diffs.
- use_null_aware_elements and Radio deprecations left as wontfix (non-straightforward or would alter structure/prompt fidelity).

Result: 138 → 85 issues (0 warnings). All changes followed "0 new private methods", barrel/AppColors rules, and were verified with analyze + model tests after each batch. This work is recorded here because it occurred inside the isolated stage1 worktree. See /tmp/grok-impl-summary-47207bb1.md for full details.

---

## Riverpod Migration After Refactoring (Post-Stage 7)

**Do not begin significant Riverpod work until the structural refactoring above is largely complete.**

### Why Separate the Efforts?

- Structural extraction is already high-risk.
- Riverpod migration on top of a still-fractured god class dramatically increases the chance of subtle bugs in realism, needs, group chat behavior, and time progression.
- It is much easier to migrate clean, focused services than it is to migrate a 12k-line `ChatService`.

### Recommended Sequence (After Stage 7)

1. **Stabilize** — Finish all seven stages + cleanup PRs. Ensure test coverage is strong.
2. **Add Riverpod to the project** — Add `flutter_riverpod` + `riverpod_annotation` (and generator if desired) without converting anything yet.
3. **Migrate leaf services first** (the ones extracted in Stage 3):
   - Convert `NeedsSimulation`, `ChaosModeService`, `RelationshipService`, etc. one at a time into `Notifier` / `AsyncNotifier`.
   - Keep `ChatService` as a `ChangeNotifier` bridge for as long as necessary.
4. **Migrate UI pieces** (widgets from Stages 2, 4, 5) to `ConsumerWidget` / `ConsumerStatefulWidget`.
5. **Migrate `ChatService` itself** (this will likely be one of the last and most complex steps).
6. **Finally**, remove the old `Provider` / `ChangeNotifierProvider` wiring from `main.dart`.

### Testing During Riverpod Migration Phase

- For every service converted to Riverpod, write tests that prove the new provider produces **identical observable behavior** to the previous implementation (using the existing realism test suite as the gold standard).
- Use `ProviderContainer` + `listen` to capture state changes and compare before/after.
- Do not remove the old `ChangeNotifier` implementation until the Riverpod version has equivalent or better test coverage.

This separation gives us the best chance of a successful, low-drama modernization of the app's architecture.
