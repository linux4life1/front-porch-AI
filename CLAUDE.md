# CLAUDE.md

Engineering rules for Front Porch AI. Everything here is either enforced by
CI, pinned by a test, or a product contract that has already been broken
once by an agent that did not know it. Point at live sources rather than
pinning numbers that rot.

Humans: [CONTRIBUTING.md](CONTRIBUTING.md). Maintainer prompts:
[docs/maintainer-agent-playbook.md](docs/maintainer-agent-playbook.md).
[AGENTS.md](AGENTS.md) is a pointer at this file; keep them in agreement.

## Product

Flutter desktop app (Windows, Linux, macOS) for character chat with local
LLMs (KoboldCpp) and remote APIs, with a companion React PWA in `web_ui/`
served by the app's built-in server. Realism Engine (emotion, trust,
relationship, needs), RAG memory via in-process ONNX, TTS/STT, Porch
Stories, The Stoop (opt-in 18+ hub), Waifu Coder (managed OpenCode), Living
Worlds (places with lore and climate). AGPL-3.0-or-later.

- State: Provider for the `main.dart` graph. Riverpod only for new
  self-contained state. No project to migrate the app.
- Database: SQLite via Drift. `schemaVersion` lives on `AppDatabase` in
  `lib/database/database.dart`.
- Nightly / Rawhide builds isolate data in `FrontPorchAI-Beta/` with
  `beta_` preference keys. Never point them at a stable library.

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # after a Drift or @riverpod change
flutter analyze lib/path/you/touched.dart
dart format lib/path/you/touched.dart                      # edited files only, never a directory

tools/preflight.sh            # the checks the branch needs, chosen from what it changes
flutter test --concurrency=4 --exclude-tags golden          # CI `test`
flutter test test/path/to/file.dart
./scripts/ci-local.sh test | all | update-goldens          # Linux-gated pixel goldens

flutter test integration_test/app_smoke_test.dart -d linux  # E2E: ONE file per run
cd web_ui && npm ci && npm run lint && npm test             # CI `web-tests`
cd web_ui && npm run build                                  # writes ../assets/web_app; required after any web_ui change
```

CI Flutter version: `.github/workflows/ci.yml` `flutter-version`. Dart SDK
constraint: `pubspec.yaml`. macOS E2E: unset the `MallocStackLogging*`
variables first or Flutter's isolate JSON is corrupted.

## Layout

```
lib/main.dart                 startup shell (legacy main.*.dart parts)
lib/database/                 Drift shell + parts; no migrations/ directory
lib/models/  lib/providers/  lib/utils/
lib/services/chat_service.dart   hub shell: fields and one-line forwarders
lib/services/chat/               ChatService parts + leaf classes; grep here for behaviour
lib/services/backporch/          The Stoop client
lib/services/web/                built-in server, facades, /api/stoop relay
lib/services/world_from_wiki/  story/  image/  grpc/
lib/ui/pages/ settings/ dialogs/ widgets/ chat_components/ layout/ theme/
web_ui/                       React PWA; desktop parity is mandatory
integration_test/             one suite per *_test.dart file
test/hygiene/                 the ratchets listed under CI
docs/design/                  design docs; user docs under docs/ are not rules
```

Barrels: if a directory has `<dir>/<dir>.dart`, import it. Never export a
`chat_service_*.dart` part from `services/chat/chat.dart`. Do not run mass
import rewrites.

`ChatService` is a `part` library. Members that golden fakes override stay
on the class as forwarders; new behaviour goes in an existing part or a
leaf class, never a new part.

## What CI enforces

| Check | Fails when | Escape hatch |
|-------|-----------|--------------|
| `analyze` | analyzer issues in changed `.dart` files | none |
| `test` | unit/widget tests | none |
| `e2e-smoke` | any `integration_test/*_test.dart` suite | none; Linux on PRs, all OSes on Rawhide/main pushes |
| `web-tests` | `npm run lint` or `npm test` in `web_ui/` | none |
| `web-e2e` | Playwright sweep and journeys against the real app | none |
| `golden` | pixel drift (Linux image) | `update-goldens` with the label below |
| `theme-lint` | new raw `Colors.*` under `lib/` | `// theme-keep: <reason>` for a maintainer-approved semantic hue |
| `io-lint` | new sync I/O under `lib/ui/` | `// io-ok: <reason>` |
| `god_file_ratchet_test` | handwritten `lib/` Dart at or over 500 lines; `test/baselines/god_files.json` is empty and stays empty | split the file |
| `part_file_ratchet_test` | a library gains a `part` | extract a class instead |
| `generated_dart_size_test` | `*.g.dart` over its recorded ceiling; Drift managers on | none; `build.yaml` keeps `generate_manager: false` |
| `raw_colors_ratchet_test`, `raw_dialogs_ratchet_test` | a file gains a raw colour or a dialog opened outside `showWarmDialog`; a new file must have none | none |
| `needs_gate_ratchet_test`, `clock_*_ratchet_test`, `picker_calls_guarded_test`, `settings_parity_manifest_test` | the gates in **Chat contracts** are bypassed; a setting lacks its web twin | none |
| PR rules | a UI PR's `## Hand-check` lines do not each name a test or start `eye-only:`; images added outside goldens, `assets/`, `docs/screenshots/` | `approved-images` label |
| Test integrity | an existing test, golden, baseline, dependency floor, `.github/`, `scripts/ci-local.sh` or `analysis_options.yaml` is modified or deleted | maintainer applies `approved-test-change` |

Adding a new test file, or appending whole `test(` / `group(` calls and
imports to an existing one, never blocks. Touching a helper, fake or
`setUp` that old tests use does. The dependency-floor test fails when
`pubspec.lock` moves a package backwards; do not regenerate the floor file.

Draft PRs run only the cheap jobs. Open PRs as drafts; the merge queue
takes them out. `full-lint` is informational. Direct PRs to `main` are
not accepted; work lands on `Rawhide`. `schedule:` workflows run from the
default branch, and `test-integrity.yml` runs the base branch's copy.

## Size law

Handwritten `lib/` Dart stays under 500 lines, including new files. Get
under by extracting a real class, widget or plain-Dart helper with explicit
inputs, never by adding a `part`. The Drift library and the ChatService
shell keep their existing parts; every other part file is legacy and the
count only goes down.

## Style

- `dart format` only the files you edited. Fix lints a wrap creates.
- Zero analyzer warnings on touched Dart.
- Do not swallow errors silently. Log or surface them.
- No hardcoded Unix paths: `Directory.systemTemp`, `StorageService.rootPath`,
  or `package:path`.
- No sync I/O in widget `build` or per-frame paths.
- Colours come from `lib/ui/theme/`: `AppColors.*Of(context)` for chrome,
  `StatusColors`, `InkColors`, `RealismColors`, `ChatColors`, `NavColors`,
  `ModelColors`, `AccentColors` for their domains. A bare palette constant in
  UI code stays Porch under every theme.
- Dialogs open through `showWarmDialog`.
- Creation wizards follow `create_character_page.dart`: step dots, linear
  `_currentStep`, bottom nav.
- `GlobalKey`s are owner-scoped. Never `GlobalObjectKey(model)`.
- Rendered text never shows `{{char}}`, `{{user}}` or a raw enum name.
- New screens, panels and sidebars work at 400 px and 1440 px wide and in a
  short window. Top-level pages get a stop in
  `integration_test/layout_sweep_test.dart`.
- Comments explain a non-obvious contract, not the next line.

## Chat contracts

Live product behaviour, each pinned by a test. Do not collapse the cases.

| Contract | Rule | Where |
|----------|------|-------|
| Mouth speech | Closed think-only body lifts and is spoken; an unclosed cut-off stays tagged, display empty | `lib/utils/think_tags.dart` `resolveMouthSpeech` |
| Continue | Not regen. Does not tick the clock, scores only `newPart`, keeps the turn's `pockets_before`, does not consume one-shots, finalizes pre-continue + new body | `chat_service_generation_postgen_engine.dart` |
| Pockets | Hide, never erase: `pocketsFor` is null when off; stored records and the save wire are untouched | `pockets_rewind_test` |
| Objectives | `objectivesActive` is a live AND of the per-chat switch and `realismSettings.objectivesEnabled`, read every turn | `chat_service_accessors.dart` |
| Needs | One gate, `NeedsPass.active` = engine AND chat switch AND global default, read live by every pass; the stored flag only seeds and rewinds | `needs_gate_ratchet_test` |
| Clock | Passage of time needs a model call. `_clockRunning` is Porch Life `passageOfTimeDefault` live. Regen rewinds from `story_clock_before`. One-shot must not apply minutes twice | `clock_*_ratchet_test`, `scene_time_evaluator.dart` |
| Evals | Score the user's message before generation, never the reply. Regen with the same inputs reproduces the same deltas; non-scalar inputs join `captureCadenceAndFeelings` / `restoreFromMessageState` | `regen_feelings_cadence_test` |
| Eval transport | Native tool call first, then the regex/JSON text floor. No GBNF on the floor. The prefix-sharing judges send the same `kJudgeEvalTools` list | `docs/design/tools-transport.md` |
| One-shot | Tri-state auto/on/off; when active it matches the multi-call path; local backends stay multi-call in auto | `one_shot_parity_test` |
| Post-gen passes | Posture, climax, pockets are post-generation; a fused reply-facts call is transport only, each keeps its own gate | `chat_service_generation_postgen_engine.dart` |
| Chaos | Per-chat switch plus `chaosModeDefault` OR-override; every conversation start path seeds it (`grep seedFromGroupOrExt`) | `chaos_mode_service.dart` |
| Journal / Growth | Per chat, per character; cards never cross chats; a Journal rewrite rule applies to Growth too | `swipe_buried_journal_test` |
| Group restore | Keys by message speaker id, never whoever is active after post-gen; `_saveScalarsIntoGroupRealism` persists group state | `chat_service_group_entry.dart` |
| Living Worlds | Setting slot owns weather and prose; Lore slots add books only; lore enumerates once per world id | `chat_places_primary_lore_test` |

## Path-complete chat work

Any change to generation, Continue, regen/swipe/delete/edit, Realism,
Needs, Journal, Growth, Pockets, RAG, Living Worlds or group orchestration
covers every sibling path or says which it skipped and why. Load the
`path-complete-chat` skill; the matrix is
[docs/design/path-complete-chat-work.md](docs/design/path-complete-chat-work.md).
The usual misses: Continue without regen, Journal without Growth, 1:1
without group speaker restore, desktop without web.

## Parity

- **Desktop ↔ web.** Anything the user can see, tap or configure on
  desktop ships in `web_ui/` in the same change. Phone vs wide adaptation is
  fine; omission is not, unless the maintainer deferred that item in the
  current conversation. `settings_parity_manifest_test` checks settings.
- **1:1 ↔ group.** A character's observable Realism and Needs results match
  in both modes. Storage may differ; the simulation may not.
- **Stoop.** An endpoint or field is three edits: Dart client
  (`lib/services/backporch/`), relay (`lib/services/web/` routes + facade),
  `web_ui/src/stoop/`. The PWA talks to the relay, never the backend.

## Database

- Migrations are additive and go in the onUpgrade ladder parts. Table
  declaration order is load-bearing for codegen; regenerate after any
  change and commit the honest `database.g.dart` diff.
- Removing or renaming a column needs maintainer confirmation first.
- `objectives`, `message_embeddings` and `data_bank_entries` key
  `character_id` by `stableGroupId` (image-filename basename), not
  `characters.id`; `avatar_images` uses the UUID. Resolve through
  `stableGroupIdFrom()` in `lib/utils/character_id.dart`.

## The Stoop

Backend and hosting are not in this repo. Do not add hosts, IPs, buckets or
credentials. The fleet runs mixed app versions: responses are additive only,
never tighten a request the old app sends, breaking changes are new
endpoints, parse defensively.

## Engines

No Python, no Rust, no helper processes. TTS, STT, embeddings and
expression run in-process. Waifu Coder may download a pinned
OpenCode zip and run `opencode serve` on loopback; that is process
management like Kobold. No in-process coding loop, and never the user's own
OpenCode install or config.

## Tests

- A new guard goes in its feature's existing test file. New files only for
  a feature that has none; each file is its own compile in CI.
- A new test must fail with the product change reverted. A test that stays
  green without the fix pins nothing; do not ship it.
- Prefer one interaction or E2E journey over another unit of a helper.
- Clocks: code that compares against "now" takes it from the caller or an
  injectable clock. Tests never pin a date the code compares with the real
  clock.
- Create and save buttons: the test calls `doubleTapNoFrame`
  (`test/helpers/double_tap.dart`) and asserts exactly one write.
- Web: a new screen gets a route in `web_ui/e2e/sweep.spec.ts`; a new flow
  gets a journey in `web_ui/e2e/journeys.spec.ts`. Before asserting
  persisted chat state in E2E: `await d.waitSendable()`.
- Changing an existing test needs a written reason: what behaviour changed
  and why the old assertion is now false.
- **No stub network tests.** Stoop, Backporch and model-download pins talk
  to a real server or skip when the env is absent. No `FakeStoopServer`,
  loopback JSON behind `overrideBaseUrl`, or canned `HttpOverrides`.
  Live pins are tagged `stoop_live` and read `STOOP_TEST_EMAIL` / `STOOP_TEST_PASSWORD` (optional
  `STOOP_LIVE_URL`, `STOOP_TEST_TOTP`) from `Platform.environment`; CI
  `stoop-live` injects them on same-repo PRs. Never print them.
- **No scripted-answer tests.** A scripted model reply may only feed
  the code under test (clock math, a gate, a dialog). No test scripts a
  reading, a verdict or a reply and then asserts that same answer back,
  or claims a model reads something right, or names an issue fixed on
  the strength of one. How a model reads text is proven by a `live` test
  against a real model or by hand. Reviewers HOLD a PR that adds one.
- Inventory of E2E suites: `docs/design/e2e-coverage-inventory.md`.

## Public text

No personal names in anything that ships to users. What's New: nightly in
`docs/Rawhide.md`, stable in `docs/main.md`, long form in
`docs/release-notes.md`. Never paste commit messages or session logs there.
`docs/Rawhide.md` holds only bullets no nightly has shipped yet, one line
each under a single `## Unreleased` heading; the nightly's `rotate-notes`
job clears what it shipped (`tools/rotate-rawhide-notes.sh`) and
`rawhide_notes_test` fails on a second heading, a duplicate, or a stall.
`.claude/changelog.md` is a pointer, not a diary. Never commit screenshots
of real chats or user data; evidence goes in the PR thread.

## Files that need a reason

`lib/database/database.dart` and its migration parts, `lib/main.dart`
(init order), `pubspec.yaml` (no version bumps; new deps need a licence
check), `analysis_options.yaml`, `scripts/`, `nightly.yml` (must land on
`main` to take effect).

## Git

- Conventional commit first line, then why it mattered.
- Never amend or rewrite another author's commits.
- Never `git checkout --`, `git restore`, or `git checkout HEAD --` on a
  file without approval in the current conversation.

## Reporting

The maintainer does not read Dart and does not hand-test the PWA. A
completion summary states: what was verified by which test, what was not
verified and why, the path-complete matrix when chat state is in scope, and
a 2 to 5 step poke script for anything a sandbox cannot certify (looks, OS
dialogs, a running model). A remote sandbox cannot self-certify a UI change;
say so. If the request cannot be finished without leaving the tree broken,
stop and say so; no stubs or skeletons.
