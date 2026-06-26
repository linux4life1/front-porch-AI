# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Front Porch AI is a Flutter desktop application (Windows/Linux/macOS) for AI-powered character chat using local LLMs via KoboldCpp. It features a "Realism Engine" for emotion/trust/relationship tracking, RAG memory via ONNX embeddings, TTS/STT, cloud sync, and a novel generator.

**License:** AGPL-3.0 (v0.9.0+), GPLv3 (earlier)
**State management:** Provider (migrating to Riverpod for new code)
**Database:** SQLite via Drift ORM

## Key Commands

```bash
# Setup
flutter pub get

# Development
flutter run                          # Debug run
flutter analyze                      # Lint (0 warnings on active rules; CI runs on changed .dart files for PRs + full scheduled job)
flutter format --set-exit-if-changed .  # Format check

# Tests
flutter test                         # Run all tests
flutter test --coverage              # With coverage
flutter test test/path/to/file.dart  # Single test file
flutter test -n "test name"          # Run specific test by name

# Build embedding server (Rust, required for RAG)
cargo build --release --manifest-path tools/embed_server/Cargo.toml

# Release builds
flutter build linux                  # Linux (then copy embed_server to build/linux/x64/release/bundle/embed_server/)
flutter build windows                # Windows (then copy embed_server.exe to build/windows/x64/runner/Release/)
./scripts/build-macos.sh             # macOS (bundles embed_server automatically)
```

## Architecture

### Directory Structure

```
lib/
├── main.dart                    # Entry point; initializes all services, window config, SIGINT handling
├── app_version.dart             # Version constant + isPreRelease flag
├── database/
│   ├── database.dart            # Drift schema (characters, chats, messages, lorebooks, worlds, etc.)
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
│   │   ├── summary_service.dart         # Chat summary generation (periodic, RAG-grounded)
│   │   ├── fact_extraction.dart         # Fact extraction + consolidation + quality gate
│   │   └── evolution_service.dart       # Character evolution (trait development, effective layering)
│   ├── prompt_injection/        # 8 prompt-injection builders (author_note, relationship, emotion,
│   │                            #   behavioral, time, nsfw, chaos, needs)
│   ├── cloud_providers/         # Cloud storage backends (Google Drive, OneDrive, WebDAV)
│   ├── grpc/                    # gRPC-generated code and services (e.g. Draw Things)
│   ├── chat_service.dart        # Core chat orchestration: context building, streaming, Realism
│   │                            #   orchestration, _groupRealism map, post-gen wiring (see notes below)
│   ├── kobold_service.dart      # KoboldCpp API client
│   ├── llm_provider.dart        # Abstraction over Kobold/OpenRouter/external APIs
│   ├── character_repository.dart # Character CRUD via Drift
│   ├── storage_service.dart     # File system paths, beta/stable data dir isolation
│   ├── embedding_sidecar.dart   # Rust subprocess manager for ONNX embeddings
│   ├── memory_service.dart      # RAG memory extraction and retrieval
│   ├── tts_service.dart         # TTS orchestration (Kokoro, ElevenLabs, OpenAI, Piper)
│   ├── stt_service.dart         # Whisper STT via Python subprocess
│   ├── cloud_sync_service.dart  # Google Drive / WebDAV sync
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
│   ├── pages/                   # Screen pages (chat_page, home_page, settings_page, etc.)
│   ├── dialogs/                 # Modal dialogs
│   ├── theme/app_colors.dart    # Central theme definitions and dark/light color helpers
│   └── widgets/                 # Reusable layout widgets (inputs, cards, sliders, dropdowns, etc.)
└── utils/                       # Helpers (emotion_labels, vram_estimator, gguf_parser, etc.)
```

### Critical Services

- **ChatService** (`lib/services/chat_service.dart`): The orchestration hub. Builds context windows, handles message streaming, coordinates Realism Engine evaluations and post-generation needs/climax/sexual/daily checks, owns the `_groupRealism` map and load/save scalars for per-character group state, attaches chip deltas to messages, and wires all cross-service callbacks. The domain logic lives in the `chat/` leaf services below; ChatService stays the thin coordinator. **It is still large — do not grow it. Extract cohesive logic into new `chat/` leaves instead.**
- **NeedsSimulation** (`lib/services/chat/needs_simulation.dart`): Sims-style needs (hunger, bladder, energy, social, fun, hygiene, comfort) — decay, post-climax arousal suppression/afterglow buffers, catastrophe narrative triggers, `applyNeedsDeltas`, `applySceneImpact`, `computeNeedsDeltasWithReasons`, and context helpers. Pure class; all cross-state (group, time, arousal) via callbacks.
- **NeedsImpactEvaluator** (`lib/services/chat/needs_impact_evaluator.dart`): Post-gen needs impact layer (LLM "needs_impact" JSON + declarative activity table + ordered modifiers pipeline for romance/stance/enjoys). Produces a `NeedsImpact` and applies it via the simulation.
- **ChaosModeService** (`lib/services/chat/chaos_mode_service.dart`): Chaos Mode pressure growth, Chance Time random event selection, custom event prompt injection.
- **RelationshipService** (`lib/services/chat/relationship_service.dart`): Bond/trust/fixation/spatial stance/inter-character feelings.
- **ExpressionClassifier** (`lib/services/chat/expression_classifier.dart`): ONNX + LLM emotion classification and reclassification (inertia, manual overrides, avatar selection). The core classifier impls still live in the legacy `lib/services/expression_classifier.dart`; the `chat/` version delegates to it.
- **LlmEvalEngine** (`lib/services/chat/llm_eval_engine.dart`): Shared eval plumbing — streaming LLM fire with retry/cancel, central think-block stripping, JSON extraction. Used by `realism_evals`, `objective_proposal`, and others.
- **RealismEvals** (`lib/services/chat/realism_evals.dart`): The 5 realism evaluation calls (relationship, emotional state, physical state, narrative, one-shot) plus their prompt builders, orchestration, and parse (bond/trust/emotion/arousal/fixation/spatial/time deltas + pending chip metadata).
- **ObjectiveProposal** (`lib/services/chat/objective_proposal.dart`): Objective proposal handling (autonomous "none" vs value, dedup, auto task-gen for autonomous), `generateObjectiveTasks`, and background task-completion checks.
- **SummaryService** (`lib/services/chat/summary_service.dart`): Periodic chat summary generation using the active LLM with RAG grounding.
- **FactExtraction** (`lib/services/chat/fact_extraction.dart`): Auto persona / learned-fact extraction, consolidation, and quality gate.
- **EvolutionService** (`lib/services/chat/evolution_service.dart`): Character evolution — trait development, effective personality/scenario layering, group per-character counts.
- **KoboldService** (`lib/services/kobold_service.dart`): HTTP client for KoboldCpp (`/api/v1/generate`, `/api/extras/abort`, etc.).
- **StorageService** (`lib/services/storage_service.dart`): Data directories. Beta builds use `FrontPorchAI-Beta/` with `beta_` prefixed SharedPreferences keys.
- **EmbeddingSidecar** (`lib/services/embedding_sidecar.dart`): Manages the Rust `embed_server` subprocess for ONNX embeddings (RAG memory).

### Python Sidecars

TTS and STT use Python subprocesses communicating via JSON over stdin/stdout:
- `kokoro_tts.py` — Kokoro TTS engine
- `whisper_stt.py` — Whisper speech-to-text
- `embed_server.py` — Fallback embedding server (Rust binary preferred)

Protocol: read JSON from stdin → process → write JSON result to stdout → errors to stderr with non-zero exit.

### Database

Drift ORM with SQLite. Schema in `lib/database/database.dart`. Run `dart run build_runner build` after schema changes to regenerate `database.g.dart`.

Key tables: `characters`, `chats`, `chat_messages`, `lorebooks`, `worlds`, `group_chats`, `story_projects`, `learned_facts`, `avatars`. UUID primary keys for cloud sync merge compatibility.

**Important — external direct writers**: A community companion app (Character Card Forge — https://github.com/FrozenKangaroo/Character-Card-Forge) performs direct raw SQL `INSERT`/`UPDATE` into the database files (primarily `characters`, `sessions`, `messages`, `avatar_images`, `sync_meta`). Schema changes can break it. See "Files Requiring Discussion Before Changes".

### Realism Engine

A multi-component system spanning `chat_service.dart` (orchestration, `_groupRealism`, post-gen hooks, message metadata), the `chat/` domain services, and the LLM provider:
- Emotion tracking with inertia between turns (ExpressionClassifier)
- Bond/trust relationship scoring (bond clamped to ±300, arousal ±100) (RelationshipService)
- Deterministic time progression (advances every 6 turns) — still in ChatService; a TimeService is planned
- Fixation engine (emotional obsessions)
- Character evolution (trait development) (EvolutionService)
- Chaos Mode / "Chance Time" random events (ChaosModeService)
- Sims-style Needs Simulation (NeedsSimulation): decay, stepped descriptions, afterglow/lust-haze/post-climax-crash buffers, catastrophe triggers, hygiene inversion for "enjoys low hygiene"
- Escape hatch: `cancelRealismEval()` aborts in-flight evals via `_isCancellingRealismEval` + `abortGeneration()`

**Known gotcha**: GBNF grammar constraints cause many KoboldCPP models to return empty eval responses. Evals use stop sequences + regex parsing (no grammar). Remote APIs work fine without grammar.

**One-shot vs Normal Path Parity (strict)**: When `_storageService.realismOneShotEval` is true, `_evaluateOneShotCall` **must** produce 1:1 equivalent outputs for Bond/Trust/Emotion/Arousal/Fixation/Spatial Stance/Time/Needs deltas as the normal multi-call path (relationship + emotional-state + physical-state + narrative calls). The one-shot path exists purely for token/latency optimization — it must not change observable Realism or Needs behavior.

**Realism & Needs Parity (1:1 vs Group)**: Observable behavior (bond/trust deltas, emotion inertia, needs decay + scene rewards + buffers + catastrophes, time advance every 6, climax refractory, etc.) must be identical whether a character is in a 1:1 chat or a group (per-speaker). Orchestration differs (scalar fields vs `_groupRealism` map + load/save + speaker impersonation), but the simulation results and UI must not diverge. Any change touching these areas requires auditing both paths and the "keep reset blocks in sync" sites in `chat_service.dart`.

### Tracing Realism/Needs/Group Post-Generation, Chips, Sidebar & Climax Checks

Because core simulation lives in the `chat/` leaves while orchestration, the `_groupRealism` map, message metadata, UI attachment, and cross-speaker coordination stay in `chat_service.dart`, tracing post-turn bugs means following a few specific execution paths. Use this when you see:
- Needs chips/sidebar not updating or showing stale values (especially in groups)
- A climax/sexual/daily LLM eval firing twice for one response
- Group members not reflecting scene rewards (fun/social/hygiene) or decay
- Chips showing cross-character deltas or all "X 0"

**Where the pieces live:**
- **Orchestration + group state + chip attachment** — `chat_service.dart`:
  - Pre-turn capture (in `sendMessage`): `preTurnVector`, `groupSpeakerPreDecayNeeds` snapshot before `tickDecay`.
  - Group per-speaker pre-gen (`_evaluateRealismForUpcomingGroupSpeaker`): `_loadGroupRealismIntoScalars` → run evals under impersonation → `_saveScalarsIntoGroupRealism` → stamp `realism_state` metadata on the new message.
  - Post-gen finalization (late in `_generateResponse`): temporarily re-set `_activeCharacter` + `_loadGroupRealismIntoScalars` so checks see the right character, `await _runPostGenNeedsChecks(finalResponse)` (climax → sexual → daily → fulfillment), `applyLongGenerationNeedsDecay`, then **`_saveScalarsIntoGroupRealism`** (the critical persist — without it scene deltas never reach `_groupRealism`).
  - Chip delta computation/attach (after `_generateResponse` in the `sendMessage` caller): the `if (_needsSimEnabled && _messages.isNotEmpty)` block; 1:1 uses `preTurnVector`, group uses the pre-decay snapshot. Sets `metadata['needs_deltas']`.
  - Group helpers: `_getGroupNeeds`/`_setGroupNeeds`, `_loadGroupRealismIntoScalars`/`_saveScalarsIntoGroupRealism`, `getNeedsForGroupCharacter`, `_getCurrentSpeakerIdForRealism`, `nextCharacter`.
- **Domain simulation** — `chat/needs_simulation.dart`: `applyNeedsDeltas`, `applySceneImpact`, `computeNeedsDeltasWithReasons` (feeds the chips), `tickDecay` (has the explicit group vs 1:1 branch), buffer state (afterglow, postClimaxCrash, arousalSuppression, pendingCatastrophe), `initializeFresh`.
- **Needs impact eval** — `chat/needs_impact_evaluator.dart`: `evaluateAndApply(responseText)` is the single post-gen entry; activity table + modifiers pipeline; decoupled from the god via callbacks.
- **Display consumers**:
  - Per-message chips: `lib/ui/chat_components/bubbles/message_bubble.dart` `_buildRealismIndicator` reads `metadata['needs_deltas']` (skips zero-delta needs).
  - Sidebar levels/bars: `lib/ui/chat_components/sidebar/realism_section.dart` uses `chat.needsVector` or the group getters.
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

`StoryPipelineService` is created via `ChangeNotifierProxyProvider2` in `main.dart`. The `update` function must NOT return the previous instance early — it must recreate the service with `llmProvider.activeService` each time so backend switches (Kobold ↔ OpenRouter/Nano-GPT) take effect.

## Branch Workflow

| Change Type                  | Target Branch              |
|------------------------------|----------------------------|
| New features & experiments   | `Rawhide`                  |
| Bug fixes for current stable | `dev`                      |
| Bug fixes for active beta    | The active `*-Beta` branch |
| Release tagging              | `main`                     |

- **Rawhide** — primary rolling development branch. All new features, UI changes, major refactors, and experimental work target Rawhide.
- **dev** — bug fixes for the current stable release (when no beta branch is active).
- **Beta branches** (`0.9.x-Beta`) — created to stabilize an upcoming release. While active, only bug fixes for that beta are accepted; no new features.
- **main** — final, tagged stable releases only. Direct PRs are almost never accepted.

When a release cycle begins, a beta branch is cut from Rawhide; Rawhide keeps moving forward while the beta stabilizes.

## Important Constraints

- Beta builds MUST isolate data: `FrontPorchAI-Beta/` directory, `beta_` prefixed SharedPreferences keys.
- All AI processing is local/offline by default; cloud APIs (ElevenLabs, OpenRouter) are opt-in.
- Character cards follow V2/V2.5 spec (PNG/JSON with embedded metadata).
- Drift database uses UUID primary keys for cloud sync merge compatibility.
- **Database schema changes affecting external direct writers**: Character Card Forge writes directly via SQL. Any schema change that could break it (non-nullable new columns, removed/renamed columns, structural changes to `characters`/`sessions`/`avatar_images`/`sync_meta`) requires explicit maintainer approval before implementation.

## Files Requiring Discussion Before Changes

### Never touch without discussion
- `database/migrations/` — schema changes require migration planning. **Do not introduce breaking changes** (especially to columns/tables written by external tools such as `characters`, `sessions`, `messages`, `avatar_images`, `sync_meta`) without direct maintainer confirmation. Character Card Forge relies on direct raw SQL writes.
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
- **Deletion is part of the task.** Any time you implement or modify behavior, audit the files you touch for dead code, duplicate logic, or obsolete methods and delete them.
- **New private methods are expensive.** Before creating one, check whether an existing method can be extended, generalized, or refactored. New methods are a last resort.
- **Method proliferation is forbidden.** If you introduce more than **two** new private methods in a piece of work, stop and either consolidate existing logic or explicitly justify why deletion was not possible.
- **Parallel implementations are banned** unless the user explicitly approves. Do not create separate code paths for 1:1 vs group, or old vs new systems, without first attempting to unify them. **(Exception: UX — see the addendum directly below.)**
- **UX takes priority over de-duplication (addendum).** When proper UX/UI genuinely requires it, separate or duplicated implementations are acceptable and expected — correct user experience outweighs the anti-duplication rules in this section. The canonical case is **distinct desktop vs. mobile layouts** in the web UI (`web_ui/`): do **not** force a single responsive layout, component tree, or CSS path to serve both form factors when that degrades either one. Build separate desktop and mobile shells/styles (e.g. branch on `useLayout()` `wide`/`isPhone` and scope CSS so the two can't bleed into each other), duplicating as needed for a genuinely good experience on each. This exception covers **presentation/UX only** — it is not a license for duplicated business logic, services, data access, or Realism/Needs engine code, where consolidation still strictly applies.
- **Overlapping / redundant features — offer deprecation or removal** (mandatory). When a request overlaps with or makes an existing feature redundant, proactively offer to deprecate and/or fully remove the now-useless feature as part of the same work. Do not leave dead enum values, old UI surfaces, parallel paths, orphaned tests, or stale docs. Document the rationale in your response, the relevant `docs/Rawhide.md` entry, and any changelog. Ask for confirmation if the removal scope is large, but default to offering the cleanup. (The Image Studio "Visualize N-slider vs. old Message Illustration" work is the canonical precedent.)
- **Mandatory commands at the end of non-trivial work** (run and report results):
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`
  - `dart fix --dry-run` (apply safe fixes where appropriate)
  - Grep/search recently added methods to verify older similar methods are not now dead.
- **UI consistency for creation wizards** (mandatory): All "Create X" flows must use the **same top-bar step indicator pattern** and linear progression as `create_character_page.dart` (horizontal step dots + labels + connecting lines in the AppBar, `AnimatedSwitcher` driven by a `_currentStep` int, `_buildNavButtons` at the bottom). Do not invent side menus, tab bars, or free-jumping section lists for wizards.
- **Compilation gate after any structural change or major refactor** (non-negotiable): After deleting methods, large refactors, or changes to `home_page.dart`/`main.dart`/service init/widget trees, run a full `flutter analyze` (and ideally `flutter build macos` or `flutter run -d macos`) **before** claiming completion. "It looks good" is not sufficient. Leave the tree in a runnable state.
- **All widgets, dialogs, menus, toggles, cards, and surfaces must honor the AppColors system** (non-negotiable): Use `AppColors` from `lib/ui/theme/app_colors.dart` exclusively. Prefer helpers — `backgroundOf/cardOf/surfaceOf/surfaceContainerOf(context)`, `textPrimary/Secondary/Tertiary(context)`, `iconPrimary/Secondary(context)`, `borderOf(context)`, and `AppColors.resolve(context, dark, light)` for custom accents. Hard-coded `Color(0xFF...)` or raw `Colors.whiteXX`/`Colors.blackXX` are forbidden in new or refactored UI (except the few semantic accent constants that already have light variants in AppColors).
- **Destructive git operations on files are forbidden without explicit approval** (data loss risk): **Never** run `git checkout -- <file>`, `git restore <file>`, `git checkout HEAD -- <file>`, `git checkout <commit> -- <file>`, or anything that discards uncommitted local changes. Work is frequently done to files without immediate commits; these commands silently destroy it. Allowed only if the human explicitly authorizes the exact command in the current conversation. Prefer `git diff`, saving a patch (`git diff > /tmp/backup.patch`), or `git stash push -m "temp" -- <file>` (only when confirmed safe). If a file seems to need a destructive checkout to recover, **stop and ask** instead of acting.

**Hygiene Summary Requirement**: At the end of any response involving non-trivial changes, include a short "Hygiene Summary" covering:
- New private methods added (list them)
- Methods deleted (list them)
- Whether `flutter analyze` is clean
- Any duplication or dead code you chose not to remove and why

## Code Style & Conventions

### Code File Size Limits & Single Responsibility

To prevent "God files" (historically some `.dart` files exceeded 9,000 lines):
- **Do One Thing and Do It Well**: Every class, widget, or service has exactly one primary purpose. Extract complex sub-domains into distinct, focused files rather than piling them into existing god files.
- **Strict File Size Cap**: Every Dart source file (excluding generated `.g.dart` and third-party code) **must be kept under 500 lines**.
- **Action on Existing Files**: If modifying a file that already exceeds 500 lines (such as `chat_service.dart`), do not grow it. Extract cohesive chunks into new, focused classes under 500 lines.

### Reuse Existing Code
- **Prefer existing variables and scaffolds** — do not add complexity when unnecessary.
- **Utilize existing functions whenever possible** — reuse patterns that already work.
- **Avoid over-engineering** — simpler solutions are better when they achieve the same goal.
- **Leverage shared state** (e.g., `StorageService`) as the single source of truth.
- **Consolidate before extending**: In complex areas (Realism Engine, Needs, group chat), first try to generalize or extend existing methods rather than creating new ones. Parallel helpers for similar functionality are not acceptable. (Presentation exception: distinct desktop vs. mobile UI layouts may be duplicated where UX requires it — see "UX takes priority over de-duplication" above. This applies to layout/CSS only, not logic.)

### Verification
- **ALWAYS run `flutter analyze` after making code changes** — the project is at 0 warnings on the active rule set. New code must not introduce warnings. Never claim changes are "verified" without running it. Variables declared inside `try` blocks are not accessible outside — declare them before the `try` with defaults.
- **Cross-platform verification is mandatory.** Front Porch AI is a Windows + macOS + Linux desktop app. Every non-trivial change must be checked (or have an explicit plan) so it does not regress on any platform — especially file paths, process spawning, Python sidecars, and anything touching `dart:io` or native binaries.
- **Realism & Needs parity is mandatory** (see the dedicated section). Any change to the Realism Engine or Needs simulation must keep 1:1 and group behavior consistent unless explicitly approved otherwise.
- **Because the user cannot review code**, treat every change as if it will be accepted without scrutiny. Leave the codebase strictly cleaner (or at minimum no worse) than you found it.

### Task Completion Rules
- **No skeleton or partial implementations.** Never create stub files, placeholder methods with only TODOs, incomplete classes, or "skeleton" functionality to finish later.
- **All tasks must be completed in full during the turn they are started.** If a request cannot be fully implemented, pass `flutter analyze` (0 errors on changed files), be grepped for dead code, **actually compile and launch** (`flutter run -d macos` or equivalent with no red startup exceptions), and be manually verified — all within a single interaction — do not begin writing the code. Ask the user to clarify scope or break the work into smaller pieces instead.
- This rule takes precedence over "getting something started." Partial progress that leaves the codebase broken or misleading is not acceptable.
- Only mark a task complete after it is fully functional and all verification steps (analyze + grep + manual review) have passed.

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
- **Python sidecars** (`kokoro_tts.py`, `whisper_stt.py`, `piper_entry.py`): handle `python` vs `python3` (and `py` launcher on Windows); `;` vs `:` for `PYTHONPATH`/`PATH`; `HOME` (Unix) vs `USERPROFILE` (Windows). Prefer PyInstaller one-dir bundles; fall back to raw `python + .py` only in dev.
- **Process management**: use `Process.start(..., includeParentEnvironment: true)`; expect `process.kill()` differences (Unix SIGTERM vs Windows TerminateProcess).
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
Barrel files reduce repetitive intra-package imports:
- `package:front_porch_ai/models/models.dart`
- `package:front_porch_ai/utils/utils.dart`
- `package:front_porch_ai/services/services.dart` (curated — only the high-frequency public surface)
- `package:front_porch_ai/ui/widgets/widgets.dart`
- `package:front_porch_ai/ui/chat_components/chat_components.dart`

**Preferred style for new code and refactors** is to import the barrel(s) instead of many individual files. Direct single-file imports remain legal forever and are correct for internal-only or one-off modules.

**Long-term migration (opportunistic, no heroic PRs):**
- No dedicated "import cleanup" effort.
- When you open a file for a real reason, convert its imports to barrels as part of the same change.
- Small dedicated hygiene PRs (5–8 files max) are allowed at most once per month, only when the verification surface is tiny.
- Mass automated find/replace across dozens of files is forbidden.
- Rarely-edited files may stay on direct imports indefinitely.

When you add a new service or model used from 3+ locations and not purely internal, add the export to the appropriate barrel in the same PR.

### Riverpod patterns (for new code)
- Use `AsyncNotifier` for async operations.
- `ref.watch` for reactive dependencies, `ref.read` for one-time actions.
- Proper error handling with `AsyncValue`.

### Python sidecar protocol
- Read JSON from stdin → process → write JSON to stdout → errors to stderr with non-zero exit.
- Always validate input JSON; catch all exceptions; exit non-zero on failure.
- Never write errors to stdout (breaks JSON parsing).

### Error handling
- Never silently swallow errors; always log or surface to the user.
- Test error conditions explicitly.
- Mock external dependencies in unit tests.

## Testing Expectations

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
