# Widget golden coverage ledger

Tracks full-app UI-regression golden coverage across `lib/ui/` (154 files: 21
pages, 25 dialogs, 36 top-level widgets, 10 sidebar sections, chat
overlays/bubbles, image studio, settings, layout). Every surface is a target,
captured in **light + dark** via `expectThemedGoldens`.

Status: ✅ covered · 🔶 in progress · ⬜ pending · 🚫 not feasible (with reason).

The infrastructure is complete and proven end-to-end on the first area; the
remaining areas are intentionally landed in reviewable batches (see the plan's
Phase 4) rather than one giant PR. Pick up the next ⬜ area, add a focused
`<area>_golden_test.dart` using `expectThemedGoldens`, generate PNGs on Linux,
and flip the row to ✅.

## Infrastructure
- ✅ `support/golden_app.dart` — `pumpGolden` / `expectThemedGoldens` (light+dark, fixed surface;
  `childBuilder` parameter for navigation tests that need a fresh StatefulWidget state per pass)
- ✅ `flutter_test_config.dart` — google_fonts fetch disabled + bundled Roboto
- ✅ `dart_test.yaml` + `@TestOn('linux')` gating + CI `--tags golden` step
- ✅ `support/creator_test_support.dart` — path_provider mock + `makeGoldenStorage`
- ✅ `support/fakes.dart` — timer-free service doubles for provider-backed goldens.
  `FakeLLMProvider` ✅. `FakeChatService` ✅ (sidebar + bubble + overlay surface;
  `realismEvalStreamTextClean` returns `''` so the "initializing" branch renders;
  `sessionGenSettings` returns `ChatGenerationSettings(bannedPhrases: [])` so
  `resolveBannedPhrases` short-circuits before reaching `storage.realismSettings`).
  `FakeTtsService` ✅. `FakeUserPersonaService` ✅. `FakeCharacterRepository` ✅.
  `FakeFolderService` ✅. `FakeGroupChatRepository` ✅. `FakeAppState` ✅.
  `FakeUpdateService` ✅ (extended with `downloadComplete`, `downloading`,
  `displayLatestVersion`, `releaseNotes`, `downloadProgress` for UpdateDialog).
- ✅ `support/fakes_services.dart` — `FakeModelManager`
  (with real `DownloadManager` for `DownloadQueuePanel`; `refreshModels()` no-ops
  so `ModelManagerPage.initState` doesn't throw), `FakeHardwareService` (seeded
  RTX 4070 hardware info).
- ✅ `support/fakes_storage.dart` — `FakeStorageService` with all build-time getters
  including `generationSettings` (for `resolveTemperature` etc.) and `backendSettings`
  (for `resolveContextSize`). Audited against BackgroundSettingsDialog,
  UiSettingsDialog, ChatSettingsDialog, ModelSettingsDialog, ModelManagerPage,
  TtsSettingsDialog (ttsEngine/Enabled/SpeechRate/Concurrency/AutoPlay/NarrateQuotedOnly/
  IgnoreAsterisks/ReplaceCurlyQuotes/VoiceModel/openaiTtsApiKey/BaseUrl/Model),
  ImageGenSettingsDialog (imageGenEnabled/Model/Size/Style/PromptParadigm/
  NegativePrompt/Backend/Seed/drawThingsGrpcHost/Port/localImageGenUrl).
- ✅ `support/fakes_services.dart` — `FakeKoboldService` (logs/isRunning/isReady/isStarting),
  `FakeVoiceManager` (catalog=[]/isLoadingCatalog/fetchCatalog no-op/listInstalledVoices=>[]),
  `FakeImageGenService` (fetchImageModels async=>[]).
- ⬜ `support/fixtures.dart` — canonical deterministic CharacterCard / chat / group / needs / lorebook

## Character Creator — `lib/ui/character_creator/`
The June-6 "Stage 4" refactor shipped a *functionally dead* creator to stable
(stubbed engine + step screens gutted to placeholders — see `.claude/changelog.md`
2026-06-21). This area is covered on two axes so neither failure can recur silently:
- ✅ **Engine behavior** — `creator/creator_engine_golden_test.dart` (behavioral,
  not pixel): `saveCharacter` persists a real card to the repo with realism seeding
  + lorebook filtering (freezes the saved JSON shape); `generateFromMode` actually
  drives the LLM and yields a model-derived card (kills the hardcoded-dummy stub).
  A pixel golden cannot catch a stubbed engine — these assert the behavior directly.
- ✅ **Wizard screens** — `widget/creator_steps_golden_test.dart`: `ModeSelectStep`
  (3 mode cards), `QuickConfigStep` (concept + options), `RealismStep` (full
  realism/needs form), `ReviewStep` (avatar panel + editable card fields, via
  `FakeLLMProvider` + bounded-frame pump for the cursor ticker). Light + dark.
- ✅ **Remaining wizard screens** — `widget/creator_steps_remaining_golden_test.dart`
  (10 PNGs). `SetupStep` — openRouter backend skips kobold/pseudoRemote branches;
  only `FakeLLMProvider(activeBackend: BackendType.openRouter)` needed.
  `GuidedConfigStep` — `FakeUserPersonaService` (via embedded GuidedOutputSettings →
  PersonaSelectorDropdown). `GuidedOutputSettings` — `FakeUserPersonaService`.
  `AutomatedConfigStep` — `FakeUserPersonaService`. `GeneratingStep` — no providers;
  `settle: false` (AnimationController.repeat). Light + dark.

## Leaf widgets — `lib/ui/widgets/` and `lib/ui/chat_components/widgets/`
- ✅ `needs_bar.dart` — `NeedsBar` (healthy/critical/mini) + `NeedsGrid` (full set)
- ✅ `fixation_chip.dart` — compact variant; expanded with lifespan (`leaf_widgets_golden_test.dart`)
- ✅ `realism_progress_row.dart` — positive bond "Close" tier; negative trust red
- ✅ `slider_with_input.dart` — mid-range float (Builder for context param)
- ✅ `styled_dropdown.dart` — three string options
- ✅ `nsfw_toggle.dart` — off state; on state
- ✅ `local_model_card.dart` — seeded Q4_K_M 8B model, 8 GB VRAM
- ✅ `realism_form_section.dart` — enabled state, all required params as no-ops
- ✅ `needs_form_section.dart` — enabled state, all per-need baselines set
- ✅ `log_view.dart` — static log lines; no blinking ticker (`leaf_animated_golden_test.dart`)
- ✅ `download_queue_panel.dart` — one active download task, panel expanded
- ✅ `hf_model_card.dart` — collapsed state, seeded 8B model with two quant files
- ✅ `chat_components/widgets/eval_pill.dart` — `AnimatedEvalPill` frozen at pulse 0.5
- ✅ `chat_components/widgets/settings_menu_item.dart` — icon + label
- ✅ `app_text_field.dart`, `character_name_input.dart`, `age_gender_row.dart`,
  `persona_selector_dropdown.dart` (FakeUserPersonaService), `model_selector.dart`,
  `greeting_tone_selector.dart`, `avatar_art_style_selector.dart`,
  `first_message_length_dropdown.dart`, `alternate_greetings_slider.dart`,
  `description_detail_chip_row.dart` — `leaf_widgets_remaining_golden_test.dart`
  (20 PNGs). settle:false for TextField-bearing widgets.
- 🚫 `_hoverable_card.dart` — `_HoverableCard` is a private class (leading-underscore
  class name); cannot be instantiated from outside its library file.
- 🚫 `kcpps_selector.dart` — StatefulWidget calls FilePicker platform channel in
  initState/_parseKcppsFile; not safely pumpable without a real platform channel stub.

## Chat bubbles — `lib/ui/chat_components/bubbles/`
- ✅ `message_bubble.dart` — `widget/chat_golden_test.dart`: user message, AI plain,
  AI with realism chips (bond/mood/trust row). `FakeTtsService` + `FakeUserPersonaService`
  unblocked the `Consumer2<TtsService, StorageService>` and persona consumer. Chat text
  renders as Ahem boxes (storage font family not bundled) — deterministic; layout
  regressions and chip-row regressions are caught. Light + dark.
- ✅ `styled_chat_message.dart` — rendered inside every MessageBubble golden above;
  its `Provider<StorageService>` reads (textScale, colors, font family) are covered
  by those captures.

## Sidebar sections — `lib/ui/chat_components/sidebar/` (`widget/sidebar_golden_test.dart`, FakeChatService)
- ✅ scene-time (evening/day-3 + dawn/day-1), author-note, summary, nsfw,
  chaos (enabled w/ pressure gauge), lorebook (header), objective (empty/propose),
  realism (seeded bond "Close"/long-term "Friendly"/trust "Trusting" + emotion +
  needs + decay — RelationshipService + NeedsSimulation wired into FakeChatService)
- ⬜ memory — reads `Provider<EmbeddingSidecar>` (RAG subprocess manager) +
  CharacterRepository + StorageService; needs those doubles (deferred)

## Chat overlays — `lib/ui/chat_components/overlays/`
- ✅ `generation_status_bar.dart` — `widget/chat_overlays_golden_test.dart`: idle (no metrics),
  generating (50%, 32 t/s, token counter), prefilling (4200-token prompt). All `settle: false`
  (Timer.periodic blocks pumpAndSettle). Light + dark.
- ✅ `objective_check_overlay.dart` — objective engine overlay (animated orb + eval pills + body text).
  Wrapped in `SizedBox>Stack` (Positioned.fill requires Stack ancestor). `settle: false`. Light + dark.
- ✅ `realism_processing_overlay.dart` — realism eval (initializing), greeting baseline capture
  (purple accent), verifying pass 1/2. `settle: false`. `realismEvalStreamTextClean` returns `''`
  so the "initializing" text branch renders (avoids the live-eval-stream Cancel button path).
  Light + dark.
- ⬜ `rag_setup_dialog.dart` — reads `EmbeddingSidecar` (RAG subprocess manager); needs that double

## Dialogs — `lib/ui/dialogs/` (25; skip `group_settings_dialog.dart.broken`)
- ✅ `byaf_import_dialog.dart` — seeded preview (name + persona + first message) (`dialogs_golden_test.dart`)
- ✅ `stable_db_import_dialog.dart` — glassmorphic import prompt (const, no providers)
- ✅ `tag_dialog.dart` — character with two existing tags (CharacterRepository only
  called from onChanged handler, never during static golden)
- ✅ `update_dialog.dart` — prompt stage via `FakeUpdateService` in `ChangeNotifierProvider`
- ✅ `export_persona_dialog.dart` — 2 seeded UserPersonas (Casual + Professional);
  no providers needed (`dialogs_more_golden_test.dart`). Surface 520×440.
- ✅ `context_viewer_dialog.dart` — empty prompt budget; `FakeChatService` injected
  directly (not via provider). Surface 560×640.
- ✅ `background_settings_dialog.dart` — "none" background selected; `FakeStorageService`
  in `ChangeNotifierProvider<StorageService>`. Surface 600×680.
- ✅ `ui_settings_dialog.dart` — global defaults (no character override);
  `FakeStorageService`. Surface 580×960.
- ✅ `chat_settings_dialog.dart` — local backend, default gen settings; `FakeStorageService`
  + `FakeLLMProvider` + `FakeChatService`. `settle: false` (TextEditingController tickers).
  Surface 580×1020.
- ✅ `group_objectives_dialog.dart` — 2 characters (Aria Vale + Dex Marlowe), empty
  objectives list; `FakeChatService` injected directly. `settle: false` (_goalController).
  Pre-existing 6px layout overflow suppressed via `FlutterError.onError`. Surface 640×700.
- ✅ `kobold_log_dialog.dart` — kobold backend stopped; FakeLLMProvider + FakeKoboldService
  (`dialogs_remaining_golden_test.dart`)
- ✅ `model_settings_dialog.dart` — openRouter backend renders _buildRemoteSettings() only
  (avoids ModelManager/KoboldService/HardwareService); FakeLLMProvider + FakeStorageService
- ✅ `user_persona_dialog.dart` — empty persona list; FakeUserPersonaService
- ✅ `voice_browser_dialog.dart` — empty voice catalog; FakeVoiceManager.
  Pre-existing filter-chip row overflow suppressed via FlutterError.onError.
- ✅ `tts_settings_dialog.dart` — ttsEngine='disabled' hides all engine-specific sections;
  FakeStorageService + FakeTtsService + FakeVoiceManager (initState calls
  _loadInstalledVoices unconditionally via VoiceManager).
- ✅ `image_gen_settings_dialog.dart` — imageGenBackend='remote' skips local fetches in
  initState; fetchImageModels no-op; FakeStorageService + FakeImageGenService.
- ✅ `character_avatars_dialog.dart` — 0 avatars; all deps injected as constructor params
  (no Provider tree). FakeCharacterRepository + FakeStorageService.
- ✅ `edit_character_dialog.dart` — tab 0 (Details); FakeStorageService for
  _buildColorRow() globalXxxColor fallbacks. settle:false (StyledTextControllers).
- ✅ `image_crop_dialog.dart` — 64×64 grey PNG bytes generated via image package;
  no Provider tree needed.
- ✅ `group_settings_dialog.dart` — activeGroup==null renders "No active group chat"
  empty state in tab 0; FakeChatService + FakeGroupChatRepository injected as
  constructor params. settle:false (TabController).
- 🚫 `rocm_guidance_dialog.dart` — inner widget `_RocmGuidanceDialog` is private; public API
  is a function `showRocmGuidanceDialog(context, linuxDistro)`, not directly pumpable
- 🚫 `lorebook_entry_dialog.dart` — inner widget `_LorebookEntryDialog` is private; public API
  is `showLorebookEntryDialog(...)`, not directly pumpable
- 🚫 `data_bank_dialog.dart` — initState calls `Provider.of<AppDatabase>.getDataBankEntriesForCharacter()`;
  AppDatabase is a Drift-generated concrete class, not practically fakeable with noSuchMethod
- 🚫 `database_cleanup_dialog.dart` — initState calls `Provider.of<AppDatabase>` then
  `DatabaseCleanup.checkOrphans(db)`; same AppDatabase constraint as above

## Navigation sidebar — `lib/ui/widgets/sidebar.dart`
- ✅ `widget/sidebar_nav_golden_test.dart`: Home selected (index 0), Settings selected (index 3),
  update-available badge shown. `FakeAppState` + `FakeUpdateService` supply both providers.
  Sidebar wrapped in `SizedBox(width: 250, height: 700)` so `Column`'s `Spacer` has a bounded
  height. Light + dark (3 × 2 = 6 PNGs).

## Pages — `lib/ui/pages/` (21; heaviest, need shared MultiProvider of fakes)
- ✅ creator wizard — see "Character Creator" above (4 user-facing steps + engine)
- ✅ **home screen — character grid** (`CharacterCardGrid` widget) —
  `widget/home_golden_test.dart`: empty library state ("This folder is empty") +
  3-character grid (cards with name labels, tag chips, placeholder avatar icons,
  grid header with sort/scale controls). `FakeCharacterRepository` +
  `FakeFolderService` + `FakeGroupChatRepository` supply the three repo
  dependencies; `CharacterCardGrid` is fully param-driven so no heavy provider
  tree is needed. Light + dark.
- ✅ `create_character_page.dart` — **all 7 steps** covered. Step 0 Identity at rest
  (`pages_golden_test.dart`); steps 1–6 (`widget/manual_creator_steps_golden_test.dart`,
  12 PNGs). Steps 1–6 navigate via `afterPump` + `childBuilder` (forces fresh State
  per brightness pass so `_currentStep` resets). Step 0→1 transition requires entering
  'Aria Vale' in the name `TextFormField` (the only TextFormField on step 0); subsequent
  steps tap "Next: {label}" buttons and pump 350ms to clear the 300ms AnimatedSwitcher.
  No providers needed (all `Provider.of` calls are inside callbacks). `settle: false`
  (TextEditingController + StyledTextController tickers). Surface 1280×900.
- ✅ `user_persona_page.dart` — empty persona list (empty-state "Add your first
  persona" UI). `FakeUserPersonaService` in `ChangeNotifierProvider`. `settle: false`
  (`AnimationController.repeat()` header glow). Surface 1280×900.
- ✅ `model_manager_page.dart` — My Models tab, empty local model list.
  `FakeModelManager` + `FakeHardwareService` + `FakeStorageService` multi-provider.
  Surface 1280×900.
- ✅ `world_management_page.dart` — empty world list (empty state). `FakeWorldRepository`
  in provider. `settle: false` (`AnimationController.repeat()` header glow). Surface 1280×900.
- ⬜ **chat page** (`chat_page.dart`, ~3800 lines) — the MessageBubble surface is
  now covered (see Chat bubbles above). Full page golden deferred: needs
  `FakeExpressionClassifierService` + a seeded `ChatService` with a message list;
  the component-by-component path (individual consumers extracted) is the route.
- ⬜ settings, character create/edit, group create/edit, story (dashboard/setup/
  writer/reader/structure), fork-to-group

### Next infrastructure step
Build `FakeExpressionClassifierService` in `support/fakes.dart` to cover the
expression/avatar panel (used on the chat page and character cards with avatars).
Also `FakeKoboldService` to cover the home page status bar widget (currently
inlined as a private method `_wrapWithStatusBar` in `HomePage` — not directly
pumpable; extract or note as ⬜). With those, the remaining pages become
component-by-component goldens like the sidebar.

The remaining ⬜ dialogs (19 of 25) and leaf widgets (12 of 36) are the logical
next batch. Dialogs that use providers beyond `UpdateService` need matching Fake
doubles before they can be pumped. Leaf widgets with heavy service deps
(model_selector, kcpps_selector, etc.) may need the same treatment.

## Image studio — `lib/ui/image_studio/`
- ⬜ main surfaces + generation options tab (extend existing `test/ui/image_studio/`)

## Settings + layout
- ⬜ `lib/ui/settings/*` panels
- ⬜ `lib/ui/layout/main_layout.dart` (shell: sidebar + content)
