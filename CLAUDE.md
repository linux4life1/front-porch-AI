# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Front Porch AI is a Flutter desktop application (Windows/Linux/macOS) for AI-powered character chat using local LLMs via KoboldCpp. It features a "Realism Engine" for emotion/trust/relationship tracking, RAG memory via ONNX embeddings, TTS/STT, a novel generator, **The Stoop** (a built-in, opt-in community character hub — see its section below), and a companion **web/mobile UI** (`web_ui/`). (Cloud Sync has been removed; automatic local backups are its replacement.)

**License:** AGPL-3.0 (v0.9.0+), GPLv3 (earlier)
**State management:** Provider (migrating to Riverpod for new code)
**Database:** SQLite via Drift ORM

## Key Commands

```bash
# Setup
flutter pub get
dart run build_runner build --delete-conflicting-outputs
                                     # Codegen — required after a Drift schema change
                                     #   (regenerates database.g.dart) and after adding
                                     #   any @riverpod provider.

# Development
flutter run                          # Debug run
flutter analyze                      # Lint (0 warnings on active rules; CI runs on changed .dart files for PRs + full scheduled job)
dart format path/to/file.dart        # Tall-style nibble: ONLY files you already
                                     #   edited. NEVER `dart format .` — see
                                     #   "Verification". NOT `flutter format`.

# Tests
flutter test --concurrency=4 --exclude-tags golden
                                     # What CI actually runs. Was pinned to
                                     #   --concurrency=1 to protect the
                                     #   realism-engine integration tests — but
                                     #   those were DELETED (see
                                     #   chat_service_realism_engine_test.dart,
                                     #   now a one-line placeholder whose header
                                     #   says the flaky dynamic/group tests were
                                     #   removed). The pin outlived its reason and
                                     #   was costing ~3.2x on every run: 578s → 180s
                                     #   over 2929 tests. Changed 2026-08-07 on the
                                     #   maintainer's instruction after 5 green
                                     #   unit runs + 3 green golden runs at 4.
                                     #   If flakes ever reappear, drop back to
                                     #   --concurrency=1 and find the racy FILE
                                     #   rather than re-slowing all 2929 tests.
flutter test --coverage              # With coverage
flutter test test/path/to/file.dart  # Single test file
flutter test -n "test name"          # Run specific test by name

# The Linux-gated gate — MANDATORY before pushing
./scripts/ci-local.sh                # Runs the pixel goldens in the fpai-golden
                                     #   linux/amd64 container. 18 golden files are
                                     #   @TestOn('linux'), so a green macOS run never
                                     #   executes them — that is exactly how a red-CI
                                     #   commit once reached Rawhide.
                                     #   Also: ci-local.sh test | all | update-goldens

# E2E (integration_test/) — one invocation PER FILE
#
# macOS host gotcha (2026-08-11): any presence of MallocStackLogging* env vars
# (including the common mistaken `export MallocStackLogging=0`) makes every
# process print MSL lines to stderr. That corrupts Flutter's isolate JSON
# stream → "Unexpected character" at load, and local E2E is dead. Fix:
#   unset MallocStackLogging MallocStackLoggingNoCompact MallocStackLoggingLite
# and DELETE any export of those from ~/.zshrc (do not re-export as 0). Then
# open a new terminal. Optional local helper (gitignored under scripts/):
#   ./scripts/e2e-local.sh app_smoke_test
flutter test integration_test/app_smoke_test.dart -d macos
                                     # Never `flutter test integration_test/` — a single
                                     #   invocation launches a second app while the first
                                     #   still holds the device, and the second file dies
                                     #   at "loading" with no stack. CI loops per file.

# WebUI (web_ui/ — the React PWA; desktop parity is mandatory)
cd web_ui && npm ci                  # Setup
cd web_ui && npm run dev             # Vite dev server
cd web_ui && npm run lint && npm test  # What the `web-tests` CI job runs (tsc + vitest)
cd web_ui && npm run build           # REQUIRED after ANY web_ui change: vite writes to
                                     #   ../assets/web_app, which is the bundle the Flutter
                                     #   app serves. No build = your change ships nothing.

# Release builds
flutter build linux                  # Linux
flutter build windows                # Windows
./scripts/build-macos.sh             # macOS (signs + packages + notarizes)
```

## Architecture

### Directory Structure

```
lib/
├── main.dart                    # Entry point — a 5-phase shell (signal handlers → prefs heal →
│                                #   guarded DB open → window → runApp); phase bodies live in
│                                #   main.{startup,providers,lifecycle,recovery,migration,reunification}.dart parts
├── app_version.dart             # Version constant + isPreRelease flag
├── database/
│   ├── database.dart            # Drift library SHELL (annotation, ctor, schemaVersion, migration stub).
│   │                            #   Tables/ladder/queries live in database.*.dart parts — see "Database" below
│   ├── database.g.dart          # Generated Drift code
│   ├── database_cleanup.dart    # Database cleanup helpers
│   └── data_migration_service.dart # Data migrations between schemas
├── models/                      # Data models (character_card.dart, lorebook.dart, world.dart, etc.)
├── providers/
│   └── app_state.dart           # Global app state (ChangeNotifier)
├── services/                    # Business logic (~50 services)
│   ├── chat/                    # Domain subservices for chat mechanics (extracted from chat_service.dart)
│   │   ├── needs_simulation.dart        # Sims-style needs (decay, buffers, apply/compute deltas)
│   │   ├── needs_impact_evaluator.dart  # Needs impact eval (LLM JSON + activity table + modifiers pipeline)
│   │   ├── chaos_mode_service.dart      # Chaos Mode / Chance Time event simulation
│   │   ├── relationship_service.dart    # Bond/trust/fixation/spatial/inter-char tracking
│   │   ├── expression_classifier.dart   # ExpressionService wrapper used inside ChatService
│   │   ├── llm_eval_engine.dart         # Shared LLM eval plumbing (fire, strip think-blocks, extract JSON)
│   │   ├── realism_evals.dart           # The 5 realism evaluation calls + prompts + parse
│   │   ├── objective_proposal.dart      # Objective proposal + task generation + completion checks
│   │   ├── journal_maintenance.dart     # The Journal: one periodic pass → memory cards + recap
│   │   ├── journal_store.dart           # Journal card persistence (per-chat, per-character)
│   │   ├── journal_ops.dart             # Journal XML transport parsing (pure functions)
│   │   ├── journal_physics.dart         # Journal emotional physics: heat/flashbulb decay, mood recall, event salience (pure)
│   │   ├── journal_prompt.dart          # Journal maintenance prompt builder (XML + tools variants, salience annotations)
│   │   ├── journal_review.dart          # Journal proposals + the ONE applier; review-first parking (apply/discard)
│   │   ├── growth_service.dart          # Growth Rings — character evolution (replaced the
│   │   │                                #   DELETED evolution_service.dart; + growth_store/_ops)
│   │   ├── time_service.dart            # Story clock — CONTINUOUS per-turn advance (no 6-turn gate)
│   │   └── story_clock.dart             # Clock math: periods, dayCount, weekday, per-turn clamps
│   │   ├── prompt_injection/    # prompt-injection builders (author_note, relationship, emotion,
│   │                            #   behavioral, time, nsfw, chaos, needs, realism_state, journal)
│   ├── grpc/                    # gRPC-generated code and services (e.g. Draw Things)
│   ├── story/                   # Porch Stories pure leaves (StoryJson/Archetypes/Prompts/Context + story.dart barrel)
│   ├── image/                   # Image-gen pure leaves (types, model_family, edit profiles + image.dart barrel)
│   ├── chat_service.dart        # The hub SHELL (<1,000 lines): state fields, fake-pinned members,
│   │                            #   _groupRealism map. Behavior lives in ~46 chat/chat_service_*.dart
│   │                            #   parts (wiring_*, generation phases, send/turn_flow/message_ops/
│   │                            #   guest_flow, accessors, defaults) — see notes below
│   ├── kobold_service.dart      # KoboldCpp API client
│   ├── llm_provider.dart        # Abstraction over Kobold/OpenRouter/external APIs
│   ├── character_repository.dart # Character CRUD via Drift
│   ├── storage_service.dart     # File system paths, nightly/stable data dir isolation
│   ├── embedding_service.dart   # In-process RAG embeddings (nomic via onnxruntime)
│   ├── memory_service.dart      # RAG memory extraction and retrieval
│   ├── tts_service.dart         # TTS orchestration (Kokoro, ElevenLabs, OpenAI, Piper)
│   ├── stt_service.dart         # Whisper STT via in-process sherpa-onnx
│   ├── backup_service.dart      # Automatic local DB backups + restore
│   ├── hardware_service.dart    # GPU detection, VRAM estimation
│   ├── backend_manager.dart     # KoboldCpp lifecycle (start/stop/restart)
│   ├── services.dart            # Curated public barrel (high-frequency surface; does NOT re-export chat/ leaves)
│   └── ... (40+ other top-level service files)
├── ui/
│   ├── chat_components/         # Componentized chat UI elements
│   │   ├── chat_components.dart # Main barrel for chat components
│   │   ├── bubbles/             # Chat bubbles (message bubbles, styled message content)
│   │   ├── overlays/            # Overlays (RAG setup, generation status, realism processing)
│   │   ├── sidebar/             # Chat sidebar tab sections (memory, realism, chaos, nsfw, scene time)
│   │   └── widgets/             # Granular interactive chat buttons and pills
│   ├── layout/main_layout.dart  # Main shell with sidebar + content area
│   ├── pages/                   # Screen pages (chat_page, home_page, etc.)
│   │   ├── settings_page.dart          # Settings shell only (~400 LOC): tab scaffold, state,
│   │   │                               #   `rebuildState(fn)` public setState bridge for the parts
│   │   ├── settings_page.controls.dart # `part of` — generation/sampler control builders
│   │   ├── settings_page.advanced.dart # `part of` — advanced/experimental settings
│   │   ├── settings_page.hardware.dart # `part of` — hardware/VRAM detection UI
│   │   ├── settings_page.gpu.dart      # `part of` — GPU layer/offload UI
│   │   └── settings_page.launch.dart   # `part of` — backend launch/args UI
│   ├── settings/                # Settings screen, extracted from the old god file (all < 500 LOC
│   │   │                        #   except voice_media_tab; extend these, don't regrow settings_page)
│   │   ├── tabs/                # One file per Settings tab: general_tab, generation_tab,
│   │   │   │                    #   backend_tab, voice_media_tab
│   │   │   └── backend/         # Backend tab sections: backend_mode_selector, remote_api_section,
│   │   │                        #   omlx_section, managed_backend_section
│   │   ├── dialogs/             # Settings-local dialogs: color_picker, model_search, prompt_save/delete
│   │   └── widgets/             # Settings-local widgets: section_header, slider_setting, color_row,
│   │                            #   api_preset_chip, image_gen_enable_section, photo_understanding_card,
│   │                            #   web_login_section
│   ├── dialogs/                 # Modal dialogs
│   ├── theme/app_colors.dart    # Central theme + warm-porch palette (porchAmber/formMasterAccent/
│   │                            #   onChaosAccent/porchAmberOf); dark/light color helpers
│   └── widgets/                 # Reusable layout widgets (inputs, cards, sliders, dropdowns, etc.)
└── utils/                       # Helpers (emotion_labels, vram_estimator, gguf_parser, etc.)
```

### Critical Services

- **ChatService** (`lib/services/chat_service.dart`): The orchestration hub. **It is a `part`-file library**: 36 `part 'chat/chat_service_*.dart';` directives (re-count with `grep -c "^part 'chat/" lib/services/chat_service.dart` rather than trusting this number — it drifts every split round) mean a great deal of "ChatService" code lives in `chat/` files that can touch its privates directly — when hunting a method, grep `lib/services/chat/` too, not just this file. Builds context windows, handles message streaming, coordinates Realism Engine evaluations and post-generation needs/climax/sexual/daily checks, owns the `_groupRealism` map and load/save scalars for per-character group state, attaches chip deltas to messages, and wires all cross-service callbacks. The domain logic lives in the `chat/` leaf services below; ChatService stays the thin coordinator. **Post-campaign (2026-08-07) the shell is under 1,000 lines and the ratchet forbids ANY lib/ file from reaching 1,000 — extract cohesive logic into new `chat/` leaves/parts instead of growing it.** Conventions that keep it small: giant `late final` constructions live as `_buildX()` builders in the four `chat_service_wiring_*.dart` parts; fake-pinned members stay on the class as 1-line forwarders to `_xImpl` extension bodies (the golden fakes override the class member — moving it outright breaks their dispatch); the default prompts/thresholds are top-level consts in `chat_service_defaults.dart`.
- **NeedsSimulation** (`lib/services/chat/needs_simulation.dart`): Sims-style needs (hunger, bladder, energy, social, fun, hygiene, comfort) — decay, post-climax arousal suppression/afterglow buffers, catastrophe narrative triggers, `applyNeedsDeltas`, `applySceneImpact`, `computeNeedsDeltasWithReasons`, and context helpers. Pure class; all cross-state (group, time, arousal) via callbacks.
- **NeedsImpactEvaluator** (`lib/services/chat/needs_impact_evaluator.dart`): Post-gen needs impact layer (LLM "needs_impact" JSON + declarative activity table + ordered modifiers pipeline for romance/stance/enjoys). Produces a `NeedsImpact` and applies it via the simulation.
- **ChaosModeService** (`lib/services/chat/chaos_mode_service.dart`): Chaos Mode pressure growth, Chance Time random event selection, custom event prompt injection.
- **RelationshipService** (`lib/services/chat/relationship_service.dart`): Bond/trust/fixation/spatial stance/inter-character feelings.
- **ExpressionClassifier** (`lib/services/chat/expression_classifier.dart`): ONNX + LLM emotion classification and reclassification (inertia, manual overrides, avatar selection). The core classifier impls still live in the legacy `lib/services/expression_classifier.dart`; the `chat/` version delegates to it.
- **LlmEvalEngine** (`lib/services/chat/llm_eval_engine.dart`): Shared eval plumbing — streaming LLM fire with retry/cancel, central think-block stripping, JSON extraction. Used by `realism_evals`, `objective_proposal`, and others.
- **RealismEvals** (`lib/services/chat/realism_evals.dart`): The 5 realism evaluation calls (relationship, emotional state, physical state, narrative, one-shot) plus their prompt builders, orchestration, and parse (bond/trust/emotion/arousal/fixation/spatial/time deltas + pending chip metadata).
- **ObjectiveProposal** (`lib/services/chat/objective_proposal.dart`): Objective proposal handling (autonomous "none" vs value, dedup, auto task-gen for autonomous), `generateObjectiveTasks`, and background task-completion checks.
- **The Journal** (`lib/services/chat/journal_maintenance.dart` + `journal_store.dart` + `journal_ops.dart` + `journal_physics.dart` + `prompt_injection/journal_injection.dart`): the unified emotional memory system. One periodic maintenance pass per diary owner produces (a) per-chat, per-character **memory cards** (with emotion label + intensity stamped deterministically from the message metadata the Realism Engine already wrote) and (b) the per-chat **"Where we are" recap**, which reuses the old summary scalars/column (`_summary`, `Sessions.summary`, `summaryLastIndex` as the pass cursor) so EvolutionService, the sidebar, and the web facade surface kept working. Cards are strictly session-scoped — **no memory ever crosses chats** — and are deleted with the chat. XML-tag transport parsed forgivingly (local-model floor); reasoning off + think-strip via LlmEvalEngine. Replaced the deleted `SummaryService` + `FactExtraction` (and the persona learned-facts feature; `Personas.learnedFacts` column is dormant). **Emotional physics** (phase 2, all constants/math in `journal_physics.dart`, pure + deterministic): cards carry heat that cools one step per pass with flashbulb resistance (strong feelings barely fade; pinned never), cold cards (heat < 0.35) leave the always-injected hot set but resurface via cosine search against the recent turn (re-warmed to 0.75 + access recorded), hot-set ordering gets a mood-congruence boost (emotion families via `EmotionLabels.nuancedToStandard`, read from the same `_characterEmotion` scalar the group pre-gen load sets per speaker — parity), cap trims the coldest unpinned card, salient events (|bond/trust delta| ≥ 12, trust repair, Chance Time, objective completion via `ObjectiveProposal.onObjectiveCompleted` → `eventKickPending`) trigger an immediate pass from `_maybeRunJournalPass`, and a virgin journal on a long chat reads only the trailing 50 messages. Card embeddings ride `MemoryService.embedText` and are strictly optional (no-RAG floor: hot/pinned injection never needs the sidecar). **Item-memory cards (2026-08-11):** `kind:'item'` diary lines ("I set my car keys down — on the hallway table.") written DETERMINISTICALLY from applied pocket events — `applyPocketOps` emits `PocketEvent`s with canonical names, `pocket_journal_cards.dart` is the pure salience mapper (setdown/give/drop + outfit-change get cards; undressing and dressing alone stay silent), and `ChatService._writeItemCards` stores them (gated on pockets AND journal switches — the features' intersection, neither core rides the other; one live card per item — a new placement retires the old). They cool at the full base rate (no flashbulb) and resurface through a **keyword floor** in `journal_injection.dart` (`JournalPhysics.itemCardMentioned`, token-intersection via the shared `itemNameTokens` rule — no embeddings, so "where are my keys?" works on every install) with cosine as the oblique-reference upgrade; card receipts enroll them in the existing timeline invalidation. **UI** (phase 3): sidebar peek `ui/chat_components/sidebar/journal_memory/journal_panel.dart` (follows the focused participant — `ChatParticipant.id` IS the cards' storage key) + full diary `ui/dialogs/journal_dialog.dart` + shared plant/edit editor `ui/dialogs/journal_card_editor.dart`; the UI mutates `ChatService.journalStore` directly and the injection builder re-reads the DB each turn, so edits need no extra plumbing. Receipts quote the cited lines AND tap-to-jump: `ui/chat_components/widgets/message_jump.dart` seeks the chat's reverse `ListView.builder` (bubbles keyed by PAGE-OWNED GlobalKeys — `_bubbleKeys` identity map in chat_page.dart, looked up via the `keyOf` callback; a bare `GlobalObjectKey(msg)` is app-global and crashed with duplicate-key storms when two chat routes were alive in one frame, maintainer repro 2026-08-10) by proportional hop + viewport paging until the target key materializes, then `ensureVisible` + a brief `JumpFlash` tint. **Phase 4** — two transports, ONE applier (`journal_review.dart`): the pass (`_runExchange`) probes `LLMService.generateWithTools` once per backend identity per run (`kJournalTools` schemas + `parseJournalToolCalls` in journal_ops; OpenRouterService implements over its shared `_chatPayload`; KoboldCpp + PseudoRemote implement via the shared `postOpenAiChatWithTools` in openai_chat_stream.dart — Qwen3-class local models call tools fine, per user decision 2026-07-03), salvages tags from text-only replies, and remembers XML-only backends per backend+model identity (remote model name AND local model path ride the key). **Review-first mode** (`journal_review_first`, default off, toggle in the recap gear): the pass resolves ops into id-addressed `JournalProposedOp`s and parks a session-guarded `JournalReviewBatch` (blocks further auto passes; cursor moves only on Apply/Discard); sidebar banner → `journal_review_dialog.dart` checkboxes → Apply routes through the same `applyOwnerProposals` normal mode uses. Prompt building lives in `journal_prompt.dart` (XML + tools closing sections over an identical body).
- **Growth Rings** (`lib/services/chat/growth_service.dart` + `growth_store.dart` + `growth_ops.dart`): character evolution. NOTE: the old `EvolutionService` and `chat/evolution_service.dart` were DELETED — only tombstone comments remain. Scenario evolution was retired with it. Do not reference either name.
- **KoboldService** (`lib/services/kobold_service.dart`): HTTP client for KoboldCpp (`/api/v1/generate`, `/api/extras/abort`, etc.).
- **StorageService** (`lib/services/storage_service.dart`): Data directories. Nightly / Rawhide builds use `FrontPorchAI-Beta/` (historical folder name) with `beta_` prefixed SharedPreferences keys.
- **EmbeddingService** (`lib/services/embedding_service.dart`): In-process RAG embeddings — nomic-embed-text-v1.5 via onnxruntime in a persistent worker isolate (`embedding/native_embedding_engine.dart`), golden-pinned to the retired Rust server's exact vectors so stored embeddings stay valid. Owns the model download/setup flow the RAG consent dialog drives.

### Native Engines (no sidecars at all)

Every sidecar was retired in 2026-07. TTS (Kokoro/Piper via sherpa-onnx), STT (Whisper via sherpa-onnx), expression classification (onnxruntime), RAG embeddings (nomic via onnxruntime, golden-pinned to the old Rust server's vectors), and Draw Things (pure-Dart gRPC + fpzip FFI) all run **in-process** — the app spawns no helper processes. Engine successes/failures report to `EngineHealth` (`lib/services/engine_health.dart`); pre-release builds surface the first unexpected failure loudly. Do not reintroduce sidecar processes.

### Database

Drift ORM with SQLite. The schema library is `lib/database/database.dart` (shell: @DriftDatabase annotation with the `tables:` list, constructor/singleton, `schemaVersion`, migration stub) plus `part` files: `database.tables.core.dart` + `database.tables.features.dart` (table classes — DECLARATION ORDER IS LOAD-BEARING for codegen), `database.migrations.dart` (the v2→v44 onUpgrade ladder — byte-verbatim discipline; a mistake here corrupts user data silently), `database.migrations.data.dart`, `database.repair.dart`, and five `database.queries.*.dart` parts. Run `dart run build_runner build` after schema changes to regenerate `database.g.dart` — and after any LAYOUT change to the database library, verify the regenerated `database.g.dart` is BYTE-IDENTICAL (`git diff` empty); a non-empty diff from a pure file-move means declaration order or the tables: list changed and must be fixed, not committed.

Key tables (REAL SQL names — verify against `database.g.dart`, not memory): `characters`, `sessions`, `messages`, `groups`, `group_members`, `folders`, `personas`, `worlds`, `chat_worlds`, `chat_biome_spans`, `message_embeddings`, `objectives`, `data_bank_entries`, `avatar_images`, `journal_memories`, `sync_meta`. 21 tables in total. UUID primary keys for merge compatibility.

**Schema v45 (2026-08-07)**: `sessions.objectives_enabled` (BoolColumn, `DEFAULT 1`) — the per-chat half of the Objectives switch. The default is load-bearing: objectives ran unconditionally before v45, so `0` would silently stop quests across the whole installed base on upgrade. The Table definition, the `onUpgrade` ladder and `database.repair.dart` must all keep saying 1; `test/database/objectives_enabled_migration_test.dart` asserts they agree. Deliberately NO matching card extension — a per-character default would change the card JSON shape, which ripples to The Stoop and every external reader.

**Identity gotcha that has already caused data loss:** `objectives`, `message_embeddings` and `data_bank_entries` key their `character_id` by the character's **stableGroupId** (the portable image-filename basename, e.g. `Jennifer_1782587668376`), NOT by the `characters.id` UUID. `avatar_images` DOES use the UUID. Joining the former against `characters.id` matches nothing and marks every row an orphan — that shipped in Database Cleanup and would have deleted 107/107 objectives and 68/68 RAG embeddings on a real library. Resolve identities via `stableGroupIdFrom()` in `lib/utils/character_id.dart`.

**External direct writers**: none. (Character Card Forge, a community app that wrote raw SQL into these files, is abandonware — maintainer ruling 2026-08-04. Schema changes no longer need to accommodate it.)

### Realism Engine

A multi-component system spanning `chat_service.dart` (orchestration, `_groupRealism`, post-gen hooks, message metadata), the `chat/` domain services, and the LLM provider:
- Emotion tracking with inertia between turns (ExpressionClassifier)
- Bond/trust relationship scoring (bond clamped to ±300, arousal ±100) (RelationshipService)
- Time progression — `lib/services/chat/time_service.dart` (`TimeService`) + `story_clock.dart`. Announce-then-decide (2026-08-18): OOC skip lands first, the prompt says "It is currently …", they write at that time, then a post-reply `minutes_elapsed` decide sets the clock the NEXT speaker is told (group bucket brigade, Scene Guests included). Continue does not tick. Clamped by `StoryClock.maxMinutesPerTurn`, with `StoryClock.failureDriftMinutes` as the deterministic floor when the eval fails and a `stallBackstopTurns` backstop so time can never freeze. Chevrons are ±30 minutes; specific time is the Story Calendar's existing **Set date & time** analog picker. **The old 6-turn gate and its `hold_time` veto are GONE** — do not reason about a turn counter.

  **PASSAGE OF TIME IS DECOUPLED FROM THE ENGINE (2026-08-06).** This AMENDS
  the 2026-08-02 "cannot be decoupled" ruling, which rested on reading the
  maintainer's "passage of time requires the model usage" as requiring the
  *engine*. It requires a MODEL CALL; it does not require bond/trust/emotion.
  The four old reasons, re-audited: (1) accuracy IS an LLM eval — still true,
  and it is the reason the clock fires a call at all; `failureDriftMinutes`
  remains a FAILURE cushion, never a mode, never surfaced; (2) fused with
  posture — a cost, not a barrier: TimeService already shipped a posture-only
  branch, and `timeOnly` mirrors it (and since 2026-08-08 the fusion is gone
  outright — posture is its own post-generation pass); (3) one-shot has no time call to extract —
  true and irrelevant, since with the engine off there is no fused JSON, so the
  paths never intersect; (4) "`realism_state` means a migration" — WRONG: the
  clock's store of record is the session row (`sessions.story_clock` /
  `story_start_date`), written and read unconditionally; `realism_state` is the
  swipe/regen rewind snapshot.
  How it works now: `standaloneClockEnabled` (default OFF, opt-in — Passage of
  Time already defaults on and could not be treated as consent for a per-turn
  call) makes `evaluatePhysicalStateCall(timeOnly: true)` fire AFTER each
  spoken reply from `_maybeAdvanceStoryClockAfterReply` (same helper as the
  engine path — group follow-ups, `/speak`, auto-play, and Scene Guests
  included). Everything after the call is SHARED (clamp, failure floor,
  `new_day` corroboration, OOC-skip ownership) — that sharing is the parity
  guarantee, pinned by `test/services/chat/standalone_clock_test.dart`. Weather
  and Dreams now gate on `_clockRunning` (either driver), not the engine.
  COROLLARY: the time PROMPT FRAGMENT gates on `_clockRunning`, never on
  `passageOfTimeEnabled` alone — that flag defaults on and is inert without a
  driver. Regen/swipe rewind from the rejected reply's `story_clock_before`
  stamp, then the post-reply decide runs again — engine, standalone, and
  guests share that receipt. One-shot must NOT apply minutes (would double).
- Spatial stance / posture — **POST-generation since 2026-08-08.** It is NOT
  part of the pre-generation judges and is not fused with the scene-time eval
  any more. `_evaluatePhysicalStateCall(postureOnly: true)` fires from
  `chat/chat_service_generation_postgen.dart`, beside `_runClimaxPass` and
  `_runPocketsPass`, for the identical reason: it reads the reply that was just
  written. On Continue it re-runs with them on the NEW text only (2026-08-12 —
  see the post-gen note below); persisted per-speaker by
  `_saveScalarsIntoGroupRealism`; re-stamped into the message's `realism_state`
  by `_restampRealismSnapshotPostGen` so regen/swipe rewind it honestly. The
  INJECTION ("Position: X — ground actions in this",
  `prompt_injection/behavioral_injection.dart`) stays pre-generation on the
  NEXT turn — that is the anti-teleport mechanism, and the reason the eval had
  to move. Neither the fused clock call nor the one-shot call asks for
  `posture` any longer; do not re-add it to either.
  **Fused transport (2026-08-10):** when two or more of the three post-gen
  bookkeeping passes (climax, pockets, posture) are live, ONE composed call
  (`ReplyFactsEval` + the `_prefetchReplyFacts` carrier in
  `chat_service_reply_facts.dart`) answers all of them — transport only:
  every feature keeps its own gate (fire = OR of gates, prompt sections +
  required tool fields = AND per feature), and each pass consumes its slice
  through its own unchanged parser/applier. Fewer than two live = each pass
  fires standalone, byte-for-byte. A fused call that fired and failed parks
  an EMPTY carrier (all three skip — their own floors) vs null = no fusion.
  This re-opened the 2026-08-07 "rides no other feature's pass" ruling WITH
  its rationale satisfied (no feature's switch appears in another's gate) —
  amendments on the ClimaxEval/PocketsEval class docs.
  Guards: `test/services/chat/posture_after_reply_test.dart`,
  `test/services/chat/reply_facts_fusion_test.dart` (fragment parity +
  composed schema + one-call-at-two-features), and the phase-placement pins
  in `test/services/chat/realism_shared_prefix_test.dart` ("no evals can
  change from pre to post" — maintainer, 2026-08-10).
- Fixation engine (emotional obsessions)
- Character evolution (trait development) (EvolutionService)
- Chaos Mode / "Chance Time" random events (ChaosModeService) — **filed here for location
  only; NOT a realism dependency.** The 2026-08-07 audit
  confirmed Chaos runs fully with the engine off.
  It has BOTH a per-chat switch in the chat sidebar and, since 2026-08-08, a global
  default in Porch Life (`realismSettings.chaosModeDefault`, OR-override, default false).
  The global is seeded in **three** places — `chat_service_chat_entry.dart`,
  `chat_service_session_manage.dart` and `chat_service_group_entry.dart`, one per way a
  conversation can begin; wire fewer and the switch is silently 1:1-only.
  `test/ui/settings/chaos_global_toggle_test.dart` reads all three call sites.
- **DECAY OWNS DEPLETION, BUT AN EVENT MUST BEAT A TURN (maintainer, 2026-08-08).**
  A need falling is slow and ambient and `tickDecay` models it; the scene eval
  may take an extra bite only for something explicitly described as costing them.
  BUT that bite has to READ as an event — "drinking a soda would cause bladder
  to drop… more than on a standard turn" — so every entry in
  `NeedsSimulation.sceneDepletionAt1x` is at least 2x (usually 3x) that need's
  `needDecay` rate: hunger 12, bladder 18, energy 12, social 10, fun 10,
  hygiene 15, comfort 12, scaling `base + 2 per strength notch` to a maximum of
  26 (under the old fixed −30, so no setting regressed).
  **Restoration is deliberately NOT bounded** — a meal really does fill you in
  one go, and the eval prompt spends a paragraph fighting models that lowball it.
  The bound lives in ONE helper (`NeedsImpactEvaluator._boundDeltas`) shared by
  both eval paths, replacing two byte-identical call-site clamps; do not add a
  third. It is deliberately NOT in `applySceneImpact`, which is a pure mutator —
  putting it there bounds the whole vector and breaks callers that use it to
  arrange state. The Director (opt-in, default off) is exempt.
  WHY ANY OF THIS: the eval reads the character's OWN REPLY, which was written
  FROM the needs, so narrating "sharp, gnawing hunger cramps" was scored as
  BECOMING hungrier — a feedback loop producing 35–40-point single-turn drops.
  The prompt now states outright that describing a state is not changing it.
  Same principle already pinned for the Realism Engine ("the eval scores the
  USER's message, never the character's own reply"), finally applied to Needs.
  Guard: `test/services/chat/needs_depletion_cap_test.dart`.
- Sims-style Needs Simulation (NeedsSimulation): straight per-turn decay ticks (needDecay plus exactly six `decayModifiers` — four cross-boosts `low_energy_hunger_boost` / `low_energy_comfort_boost` / `low_fun_social_boost` / `low_bladder_comfort_boost`, and two weather ones `weather_rough_comfort` / `weather_clear_fun` that vanish when weather is off. **There is no time-of-day decay term** — earlier wording here claimed one), scene deltas, stepped descriptions, hygiene inversion for "enjoys low hygiene". **The afterglow / lust-haze / post-climax-crash / arousal-suppression BUFFERS were removed** (see the class doc in `needs_simulation.dart`) — do not reason about buffer state.
- Escape hatch: `cancelRealismEval()` aborts in-flight evals via `_isCancellingRealismEval` + `abortGeneration()`

**Known gotcha**: GBNF grammar constraints cause many KoboldCPP models to return empty eval responses. Evals use stop sequences + regex parsing (no grammar). Remote APIs work fine without grammar. **Tools transport (2026-07-06)**: every flat-JSON eval — the 4 realism evals (relationship, emotional, narrative, one-shot), the needs-impact eval, the scene-time eval, the posture pass, the climax and pockets passes, the fused reply-facts call, the expression reclassifier, and the cast detector — tries native tool calls first (`realism_tools.dart` schemas + the ONE shared negotiation `fireStructuredEval` in `pass_support.dart`, same probe-and-fallback as Journal/Growth via the shared `ToolTransportProbe`); a successful call is converted to the canonical flat-JSON text and flows through the UNCHANGED verifier/parse/apply pipeline, so parity holds by construction. The regex text path remains the floor and the sole path for tool-less backends. Deliberately text-only: the Director/verifier critique output, the AI character creator, and the story pipeline (streaming live-preview + their own repair machinery). The three prefix-sharing judges MUST send the same `kJudgeEvalTools` list (named `tool_choice` selects the function) — do not "simplify" back to per-eval one-tool lists; that silently defeats the KV-cache on Kobold jinja.

**The eval scores the USER's message, never the character's own reply. Settled
2026-08-02 — do not re-propose post-generation evaluation.** Evals fire BEFORE
generation (`_evaluateRealismForUpcomingSpeaker`), so realism deliberately lags
one exchange. That is the design, not an oversight: bond/trust/emotion answer
"how does this character feel about what the user just did". If the eval scored
the reply instead, the character's mood would be set by whichever words the
model happened to pick for them — so **rerolling a line would reroll their
feelings**, turning bond and trust into a slot machine the user pulls by
pressing Regenerate. COROLLARY: **a regen is SUPPOSED to reproduce the same
deltas.** Its input (the user's message + the pre-turn state) is identical, and
evals run at temperature 0.1 (`llm_eval_engine.dart`), so an identical prompt
must give an identical answer. Two regens disagreeing is a **rewind bug** — some
state the turn changed was not put back — not the engine being lifelike. The
non-scalar state that regen must rewind lives in `captureCadenceAndFeelings` /
`restoreFromMessageState` (`relationship_service.dart`); anything new that feeds
an eval prompt and is NOT a scalar must join that pair.

**One-shot vs Normal Path Parity (strict)**: One-shot is a TRI-STATE since 2026-08-10 — `realismSettings.oneShotMode` (`OneShotMode.auto` default / `on` / `off`), resolved per turn by the ONE `_oneShotActive` getter via the pure `resolveOneShotMode` (pass_support.dart): `on` always fuses, `off` never, `auto` fuses only on a REMOTE backend whose `ToolTransportProbe` verdict is `supported` this run (local backends always stay multi-call — small models struggle with the fused prompt length, the reason the old bool defaulted off). The legacy `realismOneShotEval` bool surface remains as a shim (a toggle maps to on/off, never auto, and keeps writing the old pref key). Whenever one-shot is active, `_evaluateOneShotCall` **must** produce 1:1 equivalent outputs for Bond/Trust/Emotion/Arousal/Fixation/Spatial Stance/Time/Needs deltas as the normal multi-call path (relationship + emotional-state + physical-state + narrative calls). The one-shot path exists purely for token/latency optimization — it must not change observable Realism or Needs behavior. All three judges + one-shot open with the byte-identical `RealismPromptBuilder.judgePrefix` (2026-08-10, KV-cache reuse across the back-to-back calls; scene-time deliberately dispatches LAST so it cannot evict the shared prefill between two judges) — guards in `test/services/chat/realism_shared_prefix_test.dart` and `one_shot_mode_test.dart`.

**Realism & Needs Parity (1:1 vs Group)**: Observable behavior (bond/trust deltas, emotion inertia, needs decay + scene rewards + buffers + catastrophes, time advance every 6, climax refractory, etc.) must be identical whether a character is in a 1:1 chat or a group (per-speaker). Orchestration differs (scalar fields vs `_groupRealism` map + load/save + speaker impersonation), but the simulation results and UI must not diverge. Any change touching these areas requires auditing both paths and the "keep reset blocks in sync" sites in `chat_service.dart`.

### Tracing Realism/Needs/Group Post-Generation, Chips, Sidebar & Climax Checks

Because core simulation lives in the `chat/` leaves while orchestration, the `_groupRealism` map, message metadata, UI attachment, and cross-speaker coordination stay in `chat_service.dart`, tracing post-turn bugs means following a few specific execution paths. Use this when you see:
- Needs chips/sidebar not updating or showing stale values (especially in groups)
- A climax/sexual/daily LLM eval firing twice for one response
- Group members not reflecting scene rewards (fun/social/hygiene) or decay
- Chips showing cross-character deltas or all "X 0"

**Where the pieces live:**
- **Orchestration + group state + chip attachment** — `chat_service.dart`:
  - Pre-turn capture (in `sendMessage`): `preTurnVector` (`chat_service.dart:~3699`) before `tickDecay`. (There is no `groupSpeakerPreDecayNeeds` — that symbol was removed.)
  - Group per-speaker pre-gen: **`_evaluateRealismForUpcomingSpeaker`** (no "Group" in the name; `chat_service.dart:2782` + the `chat/chat_service_realism_dance.dart` part) — `_loadGroupRealismIntoScalars` → run evals under impersonation → `_saveScalarsIntoGroupRealism` → stamp `realism_state` metadata on the new message.
  - Post-gen finalization — `chat/chat_service_generation_postgen.dart` (`_finalizeGenerationTurn`, the last of `_generateResponse`'s six phases; see `chat/chat_service_generation.dart` for the phase pipeline + the `_GenTurn` per-turn carrier): temporarily re-set `_activeCharacter` + `_loadGroupRealismIntoScalars` so checks see the right character, then (2026-08-10 shape) `Future.wait([_runPostGenNeedsChecks(scoredReply), staggered _prefetchReplyFacts(scoredReply)])` — the needs eval and the fused reply-facts fetch are independent and run CONCURRENTLY — then the three consumers in order: `_runClimaxPass` → `_runPocketsPass` → posture (each reads its slice of the `_replyFactsRaw` carrier when fused, fires its own standalone call when not), then the carrier is cleared. **Continue scores the NEW text only (2026-08-12, maintainer-directed):** `scoredReply` is the full reply on a normal turn and the continuation's `newPart` on `continue_` — the family used to be skipped outright on Continue (the old full-reply re-read double-applied the first half's deltas), which left "they set the keys down" arriving via Continue permanently unbookkept since every pass only ever reads the newest reply. Incremental scoring makes a double-apply impossible by construction; the evals keep context via `recentExchange()` (the full continued reply is already written back). Consequences kept in sync: chips re-attach on continue (the helper measures live-vector minus `needs_pre_turn_vector`, so the recomputed chip IS the merged whole-turn delta), the phase persist runs on continue when the pass ran, `_runPocketsPass(asContinuation: true)` preserves the message's original `pockets_before` (unions new transfer recipients, appends receipts) so regen/tail-delete rewind to the turn base, and the climax metadata guard keeps the FIRST reading's `pre_climax_arousal`. Inter-character feelings, promise/debt, and periodic evals stay new-turn-only (delta heuristics with no stamp). Guards: `test/services/chat/continue_postgen_test.dart` + the reversed Continue pin in `posture_after_reply_test.dart` — then **`_saveScalarsIntoGroupRealism`** (the critical persist — without it scene deltas never reach `_groupRealism`).
  - Chip delta computation/attach (after `_generateResponse` in the `sendMessage` caller): the `if (_needsSimEnabled && _messages.isNotEmpty)` block; 1:1 uses `preTurnVector`, group uses the pre-decay snapshot. Sets `metadata['needs_deltas']`.
  - Group helpers: `_getGroupNeeds`/`_setGroupNeeds`, `_loadGroupRealismIntoScalars`/`_saveScalarsIntoGroupRealism`, `getNeedsForGroupCharacter`, `_getCurrentSpeakerIdForRealism`, `nextCharacter`.
- **Domain simulation** — `chat/needs_simulation.dart`: `applyNeedsDeltas`, `applySceneImpact`, `computeNeedsDeltasWithReasons` (feeds the chips), `tickDecay` (has the explicit group vs 1:1 branch), buffer state (afterglow, postClimaxCrash, arousalSuppression, pendingCatastrophe), `initializeFresh`.
- **Needs impact eval** — `chat/needs_impact_evaluator.dart`: `evaluateAndApply(responseText)` is the single post-gen entry; activity table + modifiers pipeline; decoupled from the god via callbacks.
- **Display consumers**:
  - Per-message chips: `lib/ui/chat_components/bubbles/message_bubble.dart` `_buildRealismIndicator` reads `metadata['needs_deltas']` (skips zero-delta needs).
  - Sidebar levels/bars: `lib/ui/chat_components/sidebar/character_state/` (`bond_bars.dart`, `character_state_group.dart`, …) reads **`chat.needsSimulation.vector`** and the per-member getters `getNeedsForGroupCharacter` / `getAffectionForGroupCharacter` / `getTrustForGroupCharacter`. (There is no `realism_section.dart`, and `needsVector` is a DB column, not a ChatService getter.)
  - Group member cards: `lib/ui/widgets/group_member_card.dart` → `getNeedsForGroupCharacter` → `NeedsGrid`.
  - Bar/grid widgets: `lib/ui/widgets/needs_bar.dart`.

**Tracing recipe:**
1. Reproduce with logging on (`[Realism:Needs]`, `[Realism:Climax]`, `[Realism:RawEval]`).
2. At the post-gen block, print `_activeCharacter?.name` and the speaker of the message being finalized.
3. Confirm `_saveScalarsIntoGroupRealism` ran for the right sid.
4. For chips, print the pre-vector passed to `computeNeedsDeltasWithReasons` and the resulting map.
5. For sidebar/cards, compare `getNeedsForGroupCharacter` against `_needsSimulation.vector`.
6. In group, walk: load → tick (on map) → per-speaker load (sets scalar) → gen → post apply (on scalar) → saveScalars (writes map).
7. The impersonation dance is only for the *checks* (so prompts name the right character); the scalars are already the right speaker's when post runs.

When you touch any of the above you **must**: keep 1:1 and group producing equivalent observable behavior; run the dead-code audit + analyze/format/build gates; update this section if the tracing surface changes; and consider whether new logic belongs in an extracted leaf rather than the god file.

### Story Pipeline (Porch Stories)

`StoryPipelineService` is created via `ChangeNotifierProxyProvider2` in `main.dart`. The `update` function recreates the service **when — and only when — a binding it froze at construction actually changed**: `llmProvider.activeService` identity (a real Kobold ↔ OpenRouter/Nano-GPT switch) or the live `AppDatabase` (backup restore / storage move). AMENDED 2026-08-15 (1.3 sweep): the old rule ("must NOT return previous early — recreate each time") made every KoboldService stdout line mint a new pipeline and dispose the one a story run was streaming into (overlay vanished, Generate re-enabled, orphan kept writing). oMLX ↔ Remote deliberately does NOT recreate — that switch reconfigures the SAME OpenRouterService in place and the running pipeline picks it up. The WebServerHost proxy re-points its pipeline reference whenever the story proxy mints a new one.

## The Stoop (Community Character Hub) & Its Backend

**The Stoop** is the built-in, opt-in, account-gated, strictly-18+ community hub for sharing character and group cards (browse/search, upload, download, upvotes, follow creators, and mod↔user messaging). It is served by a **companion backend API** (an independent service) that the app talks to over HTTPS. The Dart client lives in **`lib/services/backporch/`** — auth, browse/search, upload, downloads, messaging (+ a WebSocket for live messages/typing), and models such as `StoopCard` / `StoopCardDetail`. Everything else in the app remains local-first; The Stoop and any remote APIs are opt-in.

**The backend's source, hosting, and deployment are maintained privately and are NOT part of this repository.** Do not add operational details (hosts, IPs, deploy steps, buckets, credentials) to this file or the repo.

**There is a SECOND Stoop client, and parity work must update it too.** The PWA never
calls the backend directly: `web_ui/src/stoop/` (`stoopApi.ts`, `StoopContext.tsx`,
`stoopTypes.ts`, `pages/stoop/*`, `components/stoop/*`) talks to the Dart server's
**`/api/stoop/*` relay** — `lib/services/web/routes/stoop_routes.dart` plus
`facade/stoop_facade.dart`, which wrap `BackporchApi` and proxy the messaging
WebSocket. A new Stoop endpoint or field therefore needs three edits: the Dart client,
the relay route/facade, and the TS client. The web side authenticates with its own
`X-Stoop-Token` from browser localStorage — deliberately separate from the desktop
`AuthState` session.

### API backward-compatibility (non-negotiable)
The backend is deployed independently and **far more frequently** than the app, and users update the app slowly — so the live fleet is **always a mix of app versions**. A backend change must never break an already-installed app:
- **Responses are additive-only.** Never remove, rename, or change the type/meaning of a field an app reads. New response fields are **optional/nullable**.
- Never make a previously-optional **request** field required, and never tighten validation to reject payloads older apps send. Prefer computing derived values **server-side** over demanding new client inputs (e.g. a card's token count is computed on the server from the card the app already uploads).
- **DB migrations stay additive** (nullable columns / defaults) so a mixed fleet — and a rollback — stay safe.
- The Dart client must **parse defensively**: null-safe casts with defaults; tolerate missing *and* unknown fields.
- A genuinely breaking change ships as a **new endpoint** (e.g. `/v2/…`), never by mutating an existing one, and keeps the old one alive until the fleet ages out.

There is no app-version gating in the backend, and there must not be — the contract above is what keeps old and new apps interoperable.

## Branch Workflow

Two branches. That is the whole model.

| Change Type                                | Target Branch |
|--------------------------------------------|---------------|
| All work (features, fixes, experiments)    | `Rawhide`     |
| Tagged stable releases                     | `main`        |

- **Rawhide** — the only development line. Features, fixes, refactors, experiments.
- **main** — tagged stable releases. Direct PRs to `main` are almost never accepted.

There is no `dev` branch and no beta series. Cutting a third line and asking users to keep three installs was more process than it was worth.

**Cron gotcha:** GitHub evaluates `schedule:` triggers ONLY from workflow files on the
repository's DEFAULT branch. `nightly.yml` therefore runs `main`'s copy — any change to
it must be synced to `main` or the nightly silently keeps using the old version.
The same applies to `test-integrity.yml`: `pull_request_target` runs the BASE branch's
copy, so it protects only branches that actually carry the file.

## Important Constraints

- Nightly / Rawhide builds MUST isolate data: `FrontPorchAI-Beta/` directory (historical folder name) and `beta_` prefixed SharedPreferences keys, so they never touch a stable library.
- All AI processing is local/offline by default; cloud APIs (ElevenLabs, OpenRouter) are opt-in.
- Character cards follow V2/V2.5 spec (PNG/JSON with embedded metadata).
- Drift database uses UUID primary keys for cloud sync merge compatibility.

## Files Requiring Discussion Before Changes

### Never touch without discussion
- `lib/database/database.dart` (the Drift schema + its `onUpgrade` migration ladder; there is NO `database/migrations/` directory) — schema changes require migration planning and direct maintainer confirmation for anything breaking (removed/renamed columns, structural changes).
- `lib/main.dart` — service initialization order is delicate.
- `pubspec.yaml` — **do not edit unless directly instructed.** CI/CD normalizes the release version. Local dev uses standard semver (e.g. `0.9.8+1`).
- `analysis_options.yaml` — linting rules.
- `scripts/` — release/build scripts.

### Sensitive areas (extra caution)
- Authentication and API key handling
- Database queries (performance)
- UI layout changes (affect all three desktop platforms)
- Network request patterns
- File system operations

### Require architecture review
- New services or major refactors
- State management changes
- External API integrations
- Performance-critical code paths

## Rules When the Human Cannot Review Code

The user has **no ability to read or evaluate Dart code**. The following rules are **non-negotiable** and take precedence over normal task execution:

- **You are the only line of defense.** Be a paranoid, hostile reviewer of your own output. Do not assume your changes are clean.
- **Hostile self-review is mandatory before "done" / ship / push-for-users** (maintainer directive 2026-08-11 — non-negotiable). The maintainer gets excited when the suite is green and will want to ship; **green analyze + green tests are not a second look.** You must run a hostile pass on your *own* change (same job an independent reviewer does) and report it **before** claiming completion or asking to cut a Rawhide build. A one-line "looks good" is not a review.

  **When it applies:** any non-trivial change — bugfix, feature, audit item, CI unblock, multi-file patch. Skip only pure docs/typos with no executable effect (and still say "hostile review N/A: docs only").

  **How to run it (mechanisms, not vibes):**
  1. **Re-read the full call path** you touched end-to-end (not the bullet you closed). Name callers, order of ops, what runs *after* your restore/patch (e.g. re-decay after rewind).
  2. **Sibling / twin surfaces:** 1:1 vs group, Continue vs regen, Journal vs Growth, desktop vs web vs relay, every GET that must forward query params. Grep the twin; if you didn't change it, say why it's safe.
  3. **Shared-pipeline gates:** if you open a set (`sourceIds`, source lists), check the paired filter (`sessionScopedCharacterIds`, session isolation, etc.). Opening without scoping is a half-fix.
  4. **Arithmetic / ordering:** stamps vs re-apply (capture then decay vs overlay then decay). Prove with a small timeline table if realism/needs/cadence is involved.
  5. **Tests that can go red for the product:** would deleting the *call site* (not just the pure helper) still leave tests green? If yes, the guard is decoration — say so, or fix the test. Prefer pure helpers *and* call-site pin; prove one guard red before claiming it.
  6. **CI surfaces you can trip:** god-file 1000-line ratchet, unused imports on *new* files, `flutter analyze` on every touched path.
  7. **Comments vs code:** if a comment claims behaviour the code contradicts, fix code or comment in the same change.

  **Output required in the completion response** (under a heading `### Hostile self-review`):
  - What you tried to break (2–6 concrete attacks).
  - What held / what failed.
  - Residual risk you are *not* fixing (or "none material").
  - Explicit: **do not treat green suite as ship-ready until this section exists.**

  **Canonical misses this rule exists to stop** (audit stack 2026-08-11): god-file over 1000 after class-pin; Stoop TS without relay query forward; group RAG `sourceIds` without session-scope; feelings overlay without checking whether cadence is a true twin under re-decay; tests that assert "second restore wins" or re-implement a formula instead of calling the real helper/call site.
- **Path-complete chat work is mandatory** for anything touching generation, Continue, regen/swipe/delete, Realism/Needs, Journal, Growth, Pockets, RAG, or group orchestration. Fill the matrices in [`docs/design/path-complete-chat-work.md`](docs/design/path-complete-chat-work.md) in your completion summary (or mark N/A with a one-line why). **Sibling-path law (incident-backed, full-codebase audit 2026-08-11):** fixing history think-strip without Continue, Journal rewrite without Growth, or 1:1 pockets without group speaker restore is incomplete work — grep the twin and update it. Continue is not “regen lite”: it has its own finalize, partial builder, and state-zone strip list; raw `.text` / unstripped think / uncleared `porch_night` are known failure modes.
- **Maintainer is systems/hardware, not a Dart reader.** Prefer poke scripts, plain-English residual risk, and path-complete checklists over code dumps. How the human drives agents: [`docs/maintainer-agent-playbook.md`](docs/maintainer-agent-playbook.md).
- **Deletion is part of the task.** Any time you implement or modify behavior, audit the files you touch for dead code, duplicate logic, or obsolete methods and delete them.
- **New private methods are expensive.** Before creating one, check whether an existing method can be extended, generalized, or refactored. New methods are a last resort.
- **Method proliferation is forbidden.** If you introduce more than **two** new private methods in a piece of work, stop and either consolidate existing logic or explicitly justify why deletion was not possible.
- **Parallel implementations are banned** unless the user explicitly approves. Do not create separate code paths for 1:1 vs group, or old vs new systems, without first attempting to unify them. **(Exception: UX — see the addendum directly below.)**
- **WebUI ↔ Desktop parity is mandatory (non-negotiable) — "UX" means EVERYTHING the user can see, tap, or configure.** Every feature and every UX change shipped in the Flutter desktop app MUST land in the web/mobile UI (`web_ui/`) as part of the same body of work — same capabilities and the same visual language (the warm-porch theme), adapted to each form factor (adaptation is expected; omission is not — see the desktop-vs-mobile layout addendum below). To remove all ambiguity, parity explicitly covers:
  - **Theming and visual design** — per-chat themes, presets, palette/design-language changes, backgrounds, fonts. The per-chat Themes feature is the canonical example: desktop AND web shipped together, including the preset picker and color customization.
  - **Settings, toggles, and editors** — a feature whose configuration surface exists only in desktop Settings is a parity violation *even when the feature's effect already reaches web users* (canonical example: the Output Sanitizer + auto-start settings from PR #162 — desktop-only at review time; deferral required explicit maintainer approval, granted 2026-07-25).
  - **Dialogs, wizards, sidebars/chat tools, buttons, indicators** — any new user-visible affordance or state display.
  A desktop feature or UX change is NOT "done" until its web counterpart ships, or the maintainer has explicitly approved a deferral for that specific item in the current conversation. Silent deferrals documented only in design docs do not count. When in doubt, assume parity is required and ask.
- **UX takes priority over de-duplication (addendum).** When proper UX/UI genuinely requires it, separate or duplicated implementations are acceptable and expected — correct user experience outweighs the anti-duplication rules in this section. The canonical case is **distinct desktop vs. mobile layouts** in the web UI (`web_ui/`): do **not** force a single responsive layout, component tree, or CSS path to serve both form factors when that degrades either one. Build separate desktop and mobile shells/styles (e.g. branch on `useLayout()` `wide`/`isPhone` and scope CSS so the two can't bleed into each other), duplicating as needed for a genuinely good experience on each. This exception covers **presentation/UX only** — it is not a license for duplicated business logic, services, data access, or Realism/Needs engine code, where consolidation still strictly applies.
- **Overlapping / redundant features — offer deprecation or removal** (mandatory). When a request overlaps with or makes an existing feature redundant, proactively offer to deprecate and/or fully remove the now-useless feature as part of the same work. Do not leave dead enum values, old UI surfaces, parallel paths, orphaned tests, or stale docs. Document the rationale in your response, the relevant `docs/Rawhide.md` entry, and any changelog. Ask for confirmation if the removal scope is large, but default to offering the cleanup. (The Image Studio "Visualize N-slider vs. old Message Illustration" work is the canonical precedent.)
- **Mandatory commands at the end of non-trivial work** (run and report results):
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`
  - `dart fix --dry-run` (apply safe fixes where appropriate)
  - Grep/search recently added methods to verify older similar methods are not now dead.
- **UI consistency for creation wizards** (mandatory): All "Create X" flows must use the **same top-bar step indicator pattern** and linear progression as `create_character_page.dart` (horizontal step dots + labels + connecting lines in the AppBar, `AnimatedSwitcher` driven by a `_currentStep` int, `_buildNavButtons` at the bottom). Do not invent side menus, tab bars, or free-jumping section lists for wizards.
- **Compilation gate after any structural change or major refactor** (non-negotiable): After deleting methods, large refactors, or changes to `home_page.dart`/`main.dart`/service init/widget trees, run a full `flutter analyze` (and ideally `flutter build macos` or `flutter run -d macos`) **before** claiming completion. "It looks good" is not sufficient. Leave the tree in a runnable state.
- **All widgets, dialogs, menus, toggles, cards, and surfaces must honor the AppColors system** (non-negotiable): Use `AppColors` from `lib/ui/theme/app_colors.dart` exclusively. Prefer helpers — `backgroundOf/cardOf/surfaceOf/surfaceContainerOf(context)`, `textPrimary/Secondary/Tertiary(context)`, `iconPrimary/Secondary(context)`, `borderOf(context)`, and `AppColors.resolve(context, dark, light)` for custom accents. Hard-coded `Color(0xFF...)` or raw `Colors.whiteXX`/`Colors.blackXX` are forbidden in new or refactored UI (except the few semantic accent constants that already have light variants in AppColors).
- **Warm-porch accent standard for every new widget, button, icon, border, spinner, and surface** (non-negotiable, CI-enforced): The app has ONE warm-porch accent palette. Any new or refactored chrome accent MUST use `AppColors.formMasterAccent` (the const primary amber) or `AppColors.porchAmberOf(context)` (brightness-aware), with `AppColors.onChaosAccent` (near-black ink) as the foreground on any solid amber fill (white-on-amber is unreadable). **Raw `Colors.blueAccent` is banned** — the whole ~225-site cool-blue chrome set was retired to porch amber (see `.claude/changelog.md` "blueAccent → porch amber sweep" clusters 1–4). Do not reintroduce cool-blue (or any other off-palette) chrome for new buttons/toggles/cards/menus. **Verification (mandatory):** the `theme-lint` CI job (`.github/workflows/ci.yml`) fails any PR that *adds* a raw `Colors.blueAccent` line under `lib/**/*.dart`; after adding UI, also grep your diff for stray `Colors.blueAccent`/`Colors.blue`/off-palette hex. **Only exception:** a genuinely *semantic* color (a status/indicator/legend hue whose meaning depends on being non-amber — e.g. Realism trust chips, live-call status colors, the lorebook "always-on vs enabled" 2-state markers) may stay off-palette **only when the maintainer explicitly requests/approves it in the current conversation**, and it MUST carry a trailing `// theme-keep: <reason>` comment (the CI gate's allow-list marker). Absent explicit approval, warm it.
- **GlobalKeys must be owner-scoped — never derived from a model object alone** (non-negotiable, incident-backed): a `GlobalObjectKey(model)` makes the model's key app-global, and any two widgets showing the same object in the same frame are a duplicate-key crash. That is not hypothetical: chat bubbles keyed `GlobalObjectKey(msg)` crashed the app on every chat switch, because two ChatPage routes are alive during navigation and both rebuild from the same ChatService (2026-08-10 maintainer repro; fix + regression harness in `message_key_scope_test.dart`). Pattern: the owning State holds an identity map of plain `GlobalKey`s (`_bubbleKeys` in chat_page.dart) and exposes lookups (`keyOf`) to consumers. If you need to find a widget from outside, thread the owner's lookup — do not mint a global key from the model.
- **Every user-visible change ships with a manual smoke script, and a sandbox cannot self-certify** (non-negotiable): the completion rules above demand "compile and launch, manually verified" — a remote sandbox without a display CANNOT meet that bar, and a green suite is not a substitute (the chat-switch crash shipped through analyze + 3,500 unit tests + 94 goldens, because no test had ever switched chats). When working where the app cannot be launched: (1) say so explicitly in the summary — never imply manual verification happened; (2) end the summary with a 2-3 step "poke at this" script naming the exact interactions the change could plausibly break, so the maintainer's ten seconds of clicking covers what CI cannot; (3) any change touching navigation, routes, widget identity/keys, controllers, or lifecycle gets an interaction test (widget or `integration_test/`) in the same change — the class, not just the instance.
- **Destructive git operations on files are forbidden without explicit approval** (data loss risk): **Never** run `git checkout -- <file>`, `git restore <file>`, `git checkout HEAD -- <file>`, `git checkout <commit> -- <file>`, or anything that discards uncommitted local changes. Work is frequently done to files without immediate commits; these commands silently destroy it. Allowed only if the human explicitly authorizes the exact command in the current conversation. Prefer `git diff`, saving a patch (`git diff > /tmp/backup.patch`), or `git stash push -m "temp" -- <file>` (only when confirmed safe). If a file seems to need a destructive checkout to recover, **stop and ask** instead of acting.

**Hygiene Summary Requirement**: At the end of any response involving non-trivial changes, include a short "Hygiene Summary" covering:
- New private methods added (list them)
- Methods deleted (list them)
- Whether `flutter analyze` is clean
- Any duplication or dead code you chose not to remove and why
- **Barrels + boilerplate + tall style on every file touched**: confirm each
  edited Dart file was left on barrel imports (or that its remaining direct
  imports are all on the exemption list, naming which), that you ran
  `dart format` on *those paths only* (or "already tall / generated / existing
  test I must not touch"), and what repetition you collapsed while you were in
  there. "None found" is a valid answer; silence is not.
- **Hostile self-review done?** Point at the `### Hostile self-review` section
  in the same response (or "N/A: docs only"). Silence here means the work is
  incomplete — green tests are not a substitute.

## Code Style & Conventions

### Code File Size Limits & Single Responsibility

To prevent "God files" (historically some `.dart` files exceeded 9,000 lines):
- **Do One Thing and Do It Well**: Every class, widget, or service has exactly one primary purpose. Extract complex sub-domains into distinct, focused files rather than piling them into existing god files.
- **Strict File Size Cap**: Every Dart source file (excluding generated `.g.dart` and third-party code) **must be kept under 500 lines**.
- **Action on Existing Files**: If modifying a file that already exceeds 500 lines (such as `chat_service.dart`), do not grow it. Extract cohesive chunks into new, focused classes under 500 lines.
- **The 1,000-line ratchet is CI-enforced** (maintainer-set 2026-08-02): `test/hygiene/god_file_ratchet_test.dart` + `test/baselines/god_files.json` make the god-file count monotonically decreasing. **The campaign COMPLETED 2026-08-07: the baseline is `{}` and stays empty — NO lib/ file may ever reach 1,000 lines.** Adding a baseline entry requires the maintainer's `approved-test-change` label and should never happen. The 500 cap above remains the target for new and extracted files; the ratchet sits at 1,000 so routine fixes to mid-size files never fight CI.

### Reuse Existing Code
- **Prefer existing variables and scaffolds** — do not add complexity when unnecessary.
- **Utilize existing functions whenever possible** — reuse patterns that already work.
- **Cost-audit every reuse in its NEW call context** (mandatory): a function that is correct and cheap where it was written can be a regression where you call it. Before reusing, ask: how often does the new call site run (once per event? per message? per widget build/frame during streaming?), and what does the function actually cost (disk I/O, DB query, process spawn, large allocation)? State the answer to "will this slow down or speed up the app?" in your response for any reuse in a hot path. **Synchronous I/O (`existsSync`, `readAs*Sync`, `lengthSync`, `Process.runSync`, DB queries) is banned in widget `build` paths and per-frame/per-token code** — resolve it once and cache/memoize (invalidate on the events that change the answer), or move it off the UI thread. **Verification (mandatory):** the `io-lint` CI job (`.github/workflows/ci.yml`) fails any PR that *adds* a synchronous I/O call under `lib/ui/**`; a line that genuinely cannot run in a build/frame path may carry a trailing `// io-ok: <reason>` comment (the allow-list marker). Canonical incident: `coverImageFileFor` (one `existsSync`, written for once-per-event surfaces) was reused per message bubble per rebuild — invisible on macOS/APFS, 10–100x slower on Windows under Defender, shipped as the 20260716-nightly "app is sluggish / replies don't appear" regression. Cheap-on-the-dev-Mac is not cheap everywhere; platform-asymmetric cost is part of the cross-platform verification duty.
- **Avoid over-engineering** — simpler solutions are better when they achieve the same goal.
- **Leverage shared state** (e.g., `StorageService`) as the single source of truth.
- **Consolidate before extending**: In complex areas (Realism Engine, Needs, group chat), first try to generalize or extend existing methods rather than creating new ones. Parallel helpers for similar functionality are not acceptable. (Presentation exception: distinct desktop vs. mobile UI layouts may be duplicated where UX requires it — see "UX takes priority over de-duplication" above. This applies to layout/CSS only, not logic.)

### Verification
- **ALWAYS run `flutter analyze` after making code changes** — the project is at 0 warnings on the active rule set. New code must not introduce warnings. Never claim changes are "verified" without running it. Variables declared inside `try` blocks are not accessible outside — declare them before the `try` with defaults.
- **Tall style is nibble-as-you-go (same law as barrels / Riverpod).** If you already edited a Dart file, leave it on the current SDK's `dart format` output: `dart format path/to/that_file.dart` (one path, or the handful you touched). New files get formatted before you call them done. **NEVER** `dart format .`, never a directory, never "and these siblings while I'm here." A tree-wide format is still a dedicated, intentional commit — and `test/` in that commit needs `approved-test-change`. Do **not** format an existing test you did not otherwise have to change (test-integrity). After a per-file format, fix any lint the wrap just created (`if (x) return;` split → `curly_braces_in_flow_control_structures`). Do not format generated `*.g.dart`. Language version is still 3.10 (`sdk: ^3.10.8`); do not "upgrade" format rules or install the primary-constructors skill as part of touching a file.
- **Cross-platform verification is mandatory.** Front Porch AI is a Windows + macOS + Linux desktop app. Every non-trivial change must be checked (or have an explicit plan) so it does not regress on any platform — especially file paths, process spawning, native libraries (sherpa-onnx, onnxruntime, libfpzip), and anything touching `dart:io` or native binaries.
- **Realism & Needs parity is mandatory** (see the dedicated section). Any change to the Realism Engine or Needs simulation must keep 1:1 and group behavior consistent unless explicitly approved otherwise.
- **Because the user cannot review code**, treat every change as if it will be accepted without scrutiny. Leave the codebase strictly cleaner (or at minimum no worse) than you found it.

### Task Completion Rules
- **No skeleton or partial implementations.** Never create stub files, placeholder methods with only TODOs, incomplete classes, or "skeleton" functionality to finish later.
- **All tasks must be completed in full during the turn they are started.** If a request cannot be fully implemented, pass `flutter analyze` (0 errors on changed files), be grepped for dead code, **actually compile and launch** (`flutter run -d macos` or equivalent with no red startup exceptions), and be manually verified — all within a single interaction — do not begin writing the code. Ask the user to clarify scope or break the work into smaller pieces instead.
- This rule takes precedence over "getting something started." Partial progress that leaves the codebase broken or misleading is not acceptable.
- Only mark a task complete after it is fully functional and all verification steps (analyze + grep + manual review + **hostile self-review**) have passed.
- **Green suite ≠ ship.** Do not say "ready to ship", "all green", or ask for a Rawhide nightly until the hostile self-review section is present and any blocking findings from it are fixed or explicitly deferred by the maintainer.

**Mandatory Cleanup Requirements (especially when the user cannot review code):**
- Delete any code no longer reachable or needed as part of completing the task.
- Consolidate duplicate or near-duplicate logic instead of leaving parallel implementations.
- Remove any new private methods that became dead or obsolete during the work.
- "It works" is not sufficient — the codebase must be measurably cleaner (or at least not worse) than when you started.

### Realism & Needs System Parity
- The Realism Engine (Bond/Trust/Emotion/Arousal/Fixation) and especially the **Needs/Sims simulation** must maintain full functional parity between 1:1 and group chats at all times.
- Any fix, refactor, behavioral change, new feature, or tuning **must** treat both modes equivalently, unless explicitly discussed and approved as group-only or 1:1-only.
- Core simulation logic (decay rules, step thresholds, catastrophe text, erotic buffers) is intentionally shared. When editing it, you are responsible for ensuring group per-character behavior does not regress or diverge.
- Storage and per-turn orchestration already branch (`_groupRealism` vs scalar fields, group vs 1:1 paths). Orchestration may differ, but the *observable simulation behavior* for a character must feel consistent across modes. When in doubt, default to parity — breaking it without discussion is a regression.

**Anti-Accumulation Rules for Realism/Needs (critical):** This area has historically been the largest source of dead code and duplicated helpers. Any work touching realism, needs, bond, trust, emotion, fixation, group state, or time progression **requires** an explicit dead-code audit of the affected methods in `chat_service.dart`. Actively look for and delete obsolete helper methods. Creating a new private method with "Group", "Needs", "Realism", or "Decay" in the name triggers a requirement to justify why existing methods could not be reused or deleted.

### Cross-Platform Compatibility (critical)
- **Never hardcode Unix paths** (`/tmp`, `/Users/`, `~/`). Use `Directory.systemTemp`, `getApplicationDocumentsDirectory()`, `StorageService.rootPath`, or `path_provider` + `package:path/path.dart` with `p.join()`.
- **Native libraries** (sherpa-onnx, onnxruntime, libfpzip): the sherpa/ort libs ship inside their pub packages for all three platforms; libfpzip is macOS-only (Draw Things is macOS-only software). Never assume a dylib/so/dll path — resolve via the existing helpers (`sherpa_runtime.dart`, `dt_fpzip.dart`).
- **Process management** (KoboldCpp and other external tools): use `Process.start(..., includeParentEnvironment: true)`; expect `process.kill()` differences (Unix SIGTERM vs Windows TerminateProcess).
- **Before marking a task "done"**, either run the affected feature on at least two platforms, or explicitly document the platform-specific limitation + mitigation.

### Dart conventions
- Follow `flutter_lints` rules (see `analysis_options.yaml`).
- camelCase for variables/methods, PascalCase for classes.
- Prefix private members with `_`. Prefer `final` over `var`.
- One class per file (except small related classes). snake_case file names.
- Use barrel files for new or refactored code to reduce import boilerplate.

### Import order
1. Dart SDK (`dart:*`)
2. Packages (`package:*`)
3. Local imports (`../`, `./`)

### Barrel files and import hygiene (policy)
Barrel files reduce repetitive intra-package imports. **17 exist today** — run
`find lib -name '*.dart' | awk -F/ '$NF==$(NF-1)".dart"'` for the live list rather
than trusting this one. The high-frequency ones:
- `package:front_porch_ai/models/models.dart`
- `package:front_porch_ai/utils/utils.dart`
- `package:front_porch_ai/services/services.dart` (curated — only the high-frequency public surface)
- `package:front_porch_ai/services/chat/chat.dart` (the chat domain leaves; `services.dart` deliberately does NOT re-export them)
- `package:front_porch_ai/services/capability/capability.dart`
- `package:front_porch_ai/services/image_prompt/image_prompt.dart`
- `package:front_porch_ai/services/web/util/util.dart`
- `package:front_porch_ai/services/web/tunnels/tunnels.dart`
- `package:front_porch_ai/services/backporch/backporch.dart`
- `package:front_porch_ai/ui/widgets/widgets.dart`
- `package:front_porch_ai/ui/chat_components/chat_components.dart`
- `package:front_porch_ai/ui/dialogs/dialogs.dart`
- `package:front_porch_ai/ui/pages/pages.dart`
- `package:front_porch_ai/ui/pages/repository/repository.dart`
- `package:front_porch_ai/ui/character_creator/character_creator.dart` (+ `widgets/widgets.dart`)
- `package:front_porch_ai/ui/settings/widgets/widgets.dart`
- `package:front_porch_ai/ui/image_studio/image_studio.dart`

**Barrel imports are the required style — solo single-file imports are no
longer "legal forever" (maintainer directive, 2026-08-01).** The previous
wording blessed direct imports as a permanent, acceptable state for
"internal-only or one-off modules"; that clause is REVOKED and is why the
boilerplate accumulated. If a barrel covers the file, you import the barrel.
Converting the stragglers is mandatory ongoing work, not a nice-to-have.

**If no barrel covers it, create one (self-extending rule).** Converting alone
can never finish the job: 1,101 solo imports live in directories that have no
barrel at all. So when you find yourself importing **2+ siblings from the same
un-barrelled directory**, add a barrel for that directory in the same change
and use it. **All seven directories previously listed here as "most needing
one" now HAVE a barrel** (added 2026-08-01, 263 solo imports collapsed across 72
files) — `services/chat`, `services/web/util`, `ui/pages/repository`,
`ui/character_creator`, `ui/dialogs`, `ui/pages`, `services/capability`, plus
`services/image_prompt`, `services/web/tunnels`, `ui/character_creator/widgets`
and `ui/settings/widgets`. Do NOT re-derive that stale list; re-measure before
claiming a directory needs one.

`services/chat` keeps its OWN `chat/chat.dart` barrel — the curated
`services.dart` deliberately does not re-export the chat leaves, and that stays
true. Note `chat.dart` exports only the 59 non-`part` files: the 28
`chat_service_*.dart` part files belong to `chat_service.dart` and must never be
exported.

**The one place a solo import is still right:** a directory where every
importer only ever needs ONE file from it (11 such directories today). Wrapping
a single import in a barrel is ceremony, not hygiene. Don't.

**Migration status: the one-time sweep is DONE (2026-08-01, maintainer-directed).**
Every convertible single-file import in `lib/` was converted to its barrel in
one commit. The rules previously forbade exactly this ("no dedicated import
cleanup effort", "mass automated find/replace ... is forbidden"); the
maintainer overrode them to clear the backlog in one pass rather than bleed it
out opportunistically forever. That override was for the sweep itself and is
now spent — **do not run another mass import rewrite.** Keeping it clean is
now a per-file duty:

**Every file you touch, you leave on barrels (mandatory).** Opening a file for
ANY reason — a one-line bug fix, a feature, a rename — obliges you to convert
its convertible single-file imports to the barrel *in that same change*. This
is no longer "opportunistic" and it is not optional. The codebase accumulated
hundreds of hand-written import lines precisely because "convert it if you
happen to be in there" had no teeth. **A diff that edits a file and leaves a
convertible import block behind is incomplete work.**

**Every Dart file you touch, you leave on tall style (mandatory).** Same visit,
same teeth: `dart format path/to/file.dart` on the files you already edited.
Not the directory. Not the tree. Not a test you were not already changing.
Fix lints the wrap introduces in the same change. A heroic `dart format .`
is still forbidden — this nibble is how the 856-file backlog dies without
one.

**Same visit, same rule for boilerplate (mandatory).** While you are in that
file, collapse the repetition you find: an identical widget / `ListTile` /
`PopupMenuItem` shape pasted N times becomes one helper; a copy-pasted guard
becomes one function; three private copies of the same filter become one
shared function. Two precedents that set this rule — `homeCardMenuItem()`
replaced ~14 copies of an 18-line `PopupMenuItem`/`ListTile` block across two
card files (and brought `character_grid_card.dart` back *under* the 500-line
cap while ADDING a menu entry), and `buildFolderPickView()` replaced three
private copies of the same folder-filtering logic. **Extraction that shrinks
the file always beats adding to it.**

**When you add a service/model/widget used from 3+ locations** and not purely
internal, add the export to the appropriate barrel **in the same PR**. The
sweep found `picker_prefs.dart` (24 importers), `model_manager.dart` (11),
`engine_health.dart`, `expression_pack_service.dart`, `model_fetch.dart` and
`realism_form_section.dart` all missing from their barrels — every one of
those absences forced N callers to hand-write a single-file import. This is
the rule that actually prevents a repeat; the sweep only cleared the symptom.

**The only exemptions** are the cases below. If a file you touched still has
direct imports afterwards, they must ALL be from this list — and say so in your
Hygiene Summary rather than leaving it unexplained.

**The only structural exemptions** (everything else must be converted):
- A file that lives in its own barrel's directory — it would self-import.
  `lib/services/foo.dart` importing `lib/services/bar.dart` is correct and
  unavoidable.
- Part files (`part of`), which cannot carry imports at all.
- A directory where importers only ever need one file from it (see above).

Note `show`/`hide`/`as` is NOT an exemption: `import 'models.dart' show
CharacterCard;` is valid and preferred over reaching for the single file. Only
keep the direct import when the barrel genuinely reintroduces a collision the
`hide` was there to solve (`import database.dart hide World` is that case —
and `database.dart` has no barrel anyway).

### Riverpod patterns (for new code)
- **The decision rule (maintainer-set, 2026-07-25): Riverpod is allowed when the state can be fully owned and tested without replacing `ChatService`, `StorageService`, or the `main.dart` provider graph; otherwise Provider stays.** There is NO project to migrate the whole codebase — a full Provider→Riverpod conversion was explicitly evaluated and rejected (dual-model review): it would churn ~634 consumer call sites, 39 ChangeNotifier services, the delicate `main.dart` init order, and the Realism/Needs parity hub for zero user-visible benefit. Do not start one, and do not convert files "while you're in there" unless the feature you're shipping needs it.
- **Qualifies for Riverpod:** new self-contained features (the weather provider — pure engine + `@riverpod` codegen + `ProviderContainer` tests — is the template), UI-local ephemeral state, read-only projections over existing public APIs, greenfield modules outside the ProxyProvider chain.
- **Off-limits as "migration work":** `ChatService` + Realism/Needs orchestration, `StorageService`, the `main.dart` MultiProvider/ProxyProvider graph, mass UI conversion, test-suite rewrites, backend/engine lifecycle services, the web facade's ChatService binding.
- **Revisit full migration only when** ChatService has naturally shrunk to a thin coordinator via leaf extraction AND Realism parity has strong automated tests — then it's a modest finishing step, not a gamble.
- Use `AsyncNotifier` for async operations.
- `ref.watch` for reactive dependencies, `ref.read` for one-time actions.
- Proper error handling with `AsyncValue`.
- Prefer `@riverpod` codegen style (maintainer directive 2026-07-21): family parameters as plain named args, autoDispose default.

### Error handling
- Never silently swallow errors; always log or surface to the user.
- Test error conditions explicitly.
- Mock external dependencies in unit tests.

## Testing Expectations

- **Goldens are Linux-gated.** 18 widget golden files carry `@TestOn('linux')` and the
  `golden` tag, so a green macOS `flutter test` NEVER runs them. Run
  `./scripts/ci-local.sh` (the fpai-golden linux/amd64 container) before pushing — the
  script's own header notes this is how a red-CI commit once reached Rawhide.
- **E2E coverage inventory: [`docs/design/e2e-coverage-inventory.md`](docs/design/e2e-coverage-inventory.md). E2E lives in `integration_test/`** — the suites below are the inventory; add new ones
  alongside them.
  Today: `app_smoke_test.dart` (1:1 journey — realism, needs, chaos, objectives,
  journal, persistence, backend-failure resilience, worlds + lorebook injection),
  `group_smoke_test.dart` (per-speaker `_groupRealism` isolation + settle-guarded
  reload persistence), `group_realism_wiring_test.dart` (post-reload turns),
  `realism_off_test.dart` (engine disabled), `chat_switch_smoke_test.dart`
  (chat switching under stacked routes + rapid A/B churn — the duplicate-
  GlobalKey crash class; no per-message state may collide across
  simultaneously-live chat screens), `theme_interaction_test.dart` (every
  theme preset must leave bubble controls hit-testable),
  `settings_persistence_test.dart` (the "Stays Put" class: settings survive page
  reopens + a settings-layer reload), `message_actions_test.dart` (edit /
  regenerate / delete-with-needs-refund through the real bubble controls),
  `web_server_test.dart` (WebServerHost launches for real: PWA shell served,
  anon API 401s, setup→cookie→state loop over genuine HTTP),
  `story_time_test.dart` (story clock advances per scored turn and survives
  reload via realism_state), `backup_restore_test.dart` (real Backups page:
  create → restore → every service rebound, portraits kept),
  `persona_folder_test.dart` (persona form + session round-trip; folder
  create/move/open via real menus), `lorebook_chat_test.dart` (This Chat entry
  dialog → trigger preview → prompt injection + dialect decodes),
  `worlds_management_test.dart` (New World dialog + Places-panel attach),
  `journal_review_test.dart` (review-first: park → banner → apply),
  `growth_rings_test.dart` (evolution switch → pass → ring + receipt jump),
  `sidebar_sweep_test.dart` (every accordion opens; a control per section
  responds), `swipe_fork_cancel_test.dart` (swipe chevrons, cancel-mid-regen
  put-back via the paced fake, fork branch), `model_downloader_test.dart`
  (fake-HF search/download + the VRAM oversize dialog),
  `stoop_test.dart` (sign-in → AUP gate → browse → download-to-library →
  share wizard, against a fake backporch server),
  `story_pipeline_test.dart` (Porch Stories wizard → bible → structure →
  prose → reader, 5 canned stages). CI globs `integration_test/*_test.dart` and
  runs ONE invocation per file on macOS/Windows/Linux — a new suite is picked up
  automatically. Before capturing or persist-asserting chat state in ANY suite,
  `await d.waitSendable()` — the settling window (`isSettlingTurn`) is part of
  the turn, and skipping it is exactly the Windows reload flake.
- **Interaction coverage is the point.** Goldens answer "does it look right"; only an
  E2E tap answers "can a user actually do this". The 10-theme dead-button bug
  (512e4803) shipped with pixel-identical goldens and a fully green suite because
  nothing in CI had ever pressed a button. Prefer a few BROAD hit-test sweeps over a
  guard per widget.
- **Every new guard must be proven to fail (mandatory).** A test that has only ever
  been green is not evidence of anything — it may be asserting something that
  cannot break, or asserting it in a place the bug does not reach. After a new
  test passes, BREAK the thing it guards (revert the fix, restore the old
  behaviour, flip the constant), confirm it goes red, then put the code back and
  confirm it goes green again. Report both results. If you cannot make it fail,
  say so plainly — that guard is decoration, and the maintainer decides whether it
  is worth keeping.
  Two precedents from one day (2026-08-04): `persona_default_test` was
  negative-checked by temporarily restoring the merged persona value, and only
  then was it known to catch anything; `needs_reprocess_test` failed on its FIRST
  run with `hunger: expected -8, actual -16` — an exact double — which is how a
  second, deeper baseline bug was found before shipping. A test that goes red
  before it goes green has already paid for itself.
  The anti-pattern to watch for is a suite that admits its own gap in a comment.
  `needs_impact_evaluator_test.dart` carried "God-level orchestration
  (manualReprocessNeeds/revert, …) verified via source review" — and the needs
  reprocess bug lived in exactly that orchestration, stayed green through every
  run, and had to be reported by a user. "Verified via source review" means "no
  guard"; write the guard or write down that there isn't one.
- **Changing an existing test needs the maintainer's input and a written
  rationale** (maintainer directive, 2026-08-04). A test whose subject genuinely
  changed may be provably wrong and SHOULD then be updated — the rule is not
  "never touch tests", it is "never quietly touch tests". Bring: which behaviour
  changed, why the old assertion is now false rather than merely inconvenient, and
  what the replacement asserts. If the honest answer is "my change broke it and
  the test was right", fix the change instead — that is what happened when
  `reprocessWithUserCritique`'s return type was altered for convenience and took
  eight correct tests down with it (99859c8).
- **Do not edit a test to make CI green.** `.github/workflows/test-integrity.yml` runs
  on `pull_request_target` (from the base branch, so a PR cannot weaken it) and FAILS
  any PR that modifies or deletes an existing test, golden, baseline,
  `test/deps/dependency_floors.json`, workflow, or `analysis_options.yaml`. Adding NEW
  test files never blocks. Clearing it needs a maintainer's `approved-test-change`
  label — an author cannot self-approve. `.github/CODEOWNERS` is the second gate.
  Precedent: PR #172 edited the dependency floors to pass, which would have
  reintroduced the sqlite3 3.2.0 → 2.9.4 downgrade that shipped v1.1.0 with no SQLite
  engine on Linux.
- Aim for **80%+ coverage** on new code.
- Test error conditions and edge cases.
- Mock external dependencies.
- Test async operations properly.

### Reviewing Sub-Agent / AI-Generated Work
- **Always perform a proper manual code review** of the actual changes before accepting the work.
- Do **not** rely solely on a sub-agent's self-report or the fact that `flutter analyze` passes.
- Read the modified code; evaluate logic, edge cases, consistency with existing architecture, and potential regressions.
- Only mark tasks complete after personal verification.
- Sub-agents must **never** produce skeleton code, stub files, or partial implementations.

## Commit Messages

Use the conventional commit prefix on the first line (`type(scope): short summary`), but **do not stop there**. Write for a human reading the git log months later. Explain:
- What the actual problem was
- Why it mattered (impact on users or developers)
- How it was fixed and why that approach was chosen
- Any important context, gotchas, or trade-offs

**Bad (too terse):**
```
fix(lorebook): correct keyword matching regex to use proper word boundaries
```

**Good (clear and relatable):**
```
fix(lorebook): keyword triggers were completely dead even for single-word keys

The regex in _matchKeyword was written as RegExp(r'\b${key}\b') inside
a Dart raw string. Because raw strings don't interpolate ${}, it was
literally searching for the text "\bkey\b" (with literal backslashes)
instead of using word boundaries.

This meant no keyword-based lorebook entry would ever activate
(isTriggered stayed false), which is why the green dot in the sidebar
never lit up and nothing ever appeared in the Context Viewer — even
when the user typed the exact trigger word.

Fixed by using explicit string concatenation instead of ${} inside
a raw string so the regex is actually built correctly.
```

Write like you're explaining the change to a teammate who wasn't in the room.

## Changelog Tracking

After making any code changes, append an entry to `.claude/changelog.md` with:
- Date (UTC)
- Files changed
- Brief reason for the change
- Commit hash (if committed)

This enables regression tracing.

## User-Facing Changelog for the Update Dialog

The in-app "Update Available" dialog renders a non-technical "What's New" section (sourced from the GitHub release body). Users who never visit GitHub or Discord rely on this text.

You are responsible for keeping it current:
- User-facing "What's New" notes go in `docs/Rawhide.md` — short benefit-oriented bullets with emojis (e.g. "🎭 Character Expressions now support sidebar mode").
- When preparing a release, use the relevant `docs/Rawhide.md` content for the GitHub release body.
- Never use raw commit messages, `.claude/changelog.md` contents, or technical PR lists — those are internal.
- `docs/release-notes.md` remains the long-form historical document.
- Update `docs/Rawhide.md` as part of any user-visible work.

## Community

- Discord: https://discord.gg/e4tET6rpdv

## Git Contributions

- Never amend or rewrite commits from other authors.
- This file (CLAUDE.md) is committed to the repository so contributors and their AI agents can follow the project's guidelines.
