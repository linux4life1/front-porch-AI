# CLAUDE.md

Engineering law for Front Porch AI. Agents read this before writing code.
[AGENTS.md](AGENTS.md) is a short pointer at the same law — do not let the
two files drift.

Humans: [CONTRIBUTING.md](CONTRIBUTING.md). Driving agents without reading
Dart: [docs/maintainer-agent-playbook.md](docs/maintainer-agent-playbook.md).
User docs live under `docs/` and are **not** agent law.

Prefer short durable rules over session narration. If a number or file list
will rot, point at the live source instead of pinning it here.

---

## Product

Front Porch AI is a Flutter desktop app (Windows / Linux / macOS) for
character chat with local LLMs (KoboldCpp) and optional remote APIs. It
includes a Realism Engine (emotion / trust / relationship / needs), RAG
memory via in-process ONNX embeddings, TTS/STT, Porch Stories, **The Stoop**
(opt-in 18+ community hub), Waifu Coder (managed OpenCode), and a companion
web/mobile UI in `web_ui/`. Automatic local backups cover the library.

- **License:** AGPL-3.0-or-later (v0.9.0+). Earlier releases were GPLv3.
- **State:** Provider for the `main.dart` graph. Riverpod only for new
  self-contained state that does not replace `ChatService`, `StorageService`,
  or that graph. There is no project to migrate the whole app to Riverpod.
- **Database:** SQLite via Drift. Schema version lives on `AppDatabase` in
  `lib/database/database.dart` — read it, do not memorise it here.

Nightly / Rawhide builds isolate data in `FrontPorchAI-Beta/` (historical
name) with `beta_` SharedPreferences keys. Do not point them at a stable
library.

---

## Commands

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
  # After a Drift schema change (regenerates database.g.dart)
  # or after adding a @riverpod provider.

flutter run
flutter analyze
dart format path/to/the_file_you_edited.dart
  # Only files you already edited. NEVER `dart format .`

# What the CI `test` job runs
flutter test --concurrency=4 --exclude-tags golden

flutter test test/path/to/file.dart
flutter test -n "test name"

# Linux-gated pixel goldens (macOS `flutter test` never runs them)
./scripts/ci-local.sh                 # goldens in the fpai-golden image
./scripts/ci-local.sh test | all | update-goldens

# E2E — ONE file per invocation. A directory launch starts a second app
# while the first still holds the device.
flutter test integration_test/app_smoke_test.dart -d linux
# macOS: unset MallocStackLogging MallocStackLoggingNoCompact
# MallocStackLoggingLite before E2E (even `=0` prints to stderr and
# corrupts Flutter's isolate JSON).

cd web_ui && npm ci
cd web_ui && npm run lint && npm test   # CI `web-tests` (tsc + vitest)
cd web_ui && npm run build              # writes ../assets/web_app — required
                                        # after ANY web_ui change or the
                                        # desktop app serves the old bundle

flutter build linux
flutter build windows
./scripts/build-macos.sh
```

CI Flutter is **3.47.0**. Dart SDK constraint is `^3.10.8`.

---

## Layout (find code here; do not trust counts)

```
lib/
  main.dart                 # Startup shell; bodies in main.*.dart parts
  database/                 # Drift shell + parts. NO database/migrations/
  models/
  providers/app_state.dart
  services/
    chat_service.dart       # Hub SHELL: fields, fake-pinned forwarders
    chat/                   # Leaves + chat_service_*.dart parts
    backporch/              # The Stoop Dart client
    web/                    # Built-in server, facades, /api/stoop relay
    story/  image/  grpc/
    services.dart           # Curated barrel — does NOT re-export chat/
  ui/
    pages/  settings/  dialogs/  widgets/
    chat_components/  layout/  theme/app_colors.dart
  utils/
web_ui/                     # React PWA; desktop parity is mandatory
integration_test/           # One suite per *_test.dart file
```

**ChatService is a `part` library.** Behaviour lives under
`lib/services/chat/`. Grep that directory when hunting a method. Count
`part` lines in `chat_service.dart` if you need a number — it changes when
files split.

Fake-pinned members stay on the **class** as one-line forwarders. Golden
fakes override the class member; moving the body onto an extension-only
name breaks their dispatch.

Hunt current barrels with:

```bash
find lib -name '*.dart' | awk -F/ '$NF==$(NF-1)".dart"'
```

High-frequency ones: `models/models.dart`, `utils/utils.dart`,
`services/services.dart`, `services/chat/chat.dart` (leaves only — never
export `chat_service_*.dart` parts), `ui/widgets/widgets.dart`,
`ui/chat_components/chat_components.dart`, `ui/dialogs/dialogs.dart`,
`ui/pages/pages.dart`. If a barrel covers a file, import the barrel. If you
import 2+ siblings from an un-barrelled directory, add a barrel in the same
change. `show` / `hide` is not an exemption unless the barrel reintroduces a
real collision (`database.dart hide World` is that case).

Do **not** run a mass import rewrite. Leave every file you touch on barrels
and tall style.

---

## Size law

| Rule | Enforcement |
|------|-------------|
| **No handwritten `lib/` Dart may reach 500 lines** | CI: `test/hygiene/god_file_ratchet_test.dart` + empty `test/baselines/god_files.json`. `kGodFileBar` is 500. Adding a baseline entry needs `approved-test-change` and should not happen — split the file instead. |
| New / extracted Dart stays **under 500 lines** | Same gate. Extract; do not grow. |
| Generated `*.g.dart` stays under recorded ceilings; Drift table managers stay **off** | CI: `test/hygiene/generated_dart_size_test.dart`. `build.yaml` must keep `generate_manager: false`. `lib/database/database.g.dart` is excluded from the handwritten ratchet and owned here. |

Do not invent a second 500-line gate. Generated protobuf / `.g.dart` /
`grpc/generated` are excluded from `god_file_ratchet_test.dart` (generated
size is the other test).

---

## Style

- DRY, readable Dart. One class per file except small related types.
- **Limited comments.** Explain non-obvious contracts, not the next line.
- `dart format` per edited file. Never `dart format .`, never a directory,
  never an existing test you were not already changing.
- After a wrap, fix lints the wrap created (`if (x) return;` split trips
  `curly_braces_in_flow_control_structures`).
- Touched Dart: **zero** analyzer warnings. `flutter analyze` on those paths.
- Do not silently swallow errors. Log or surface them.
- Do not hardcode Unix paths. Use `Directory.systemTemp`,
  `StorageService.rootPath`, or `package:path`.
- Sync I/O (`existsSync`, `readAs*Sync`, `Process.runSync`, …) is banned in
  widget `build` / per-frame paths. CI `io-lint` fails **new** sync I/O under
  `lib/ui/**` unless the line has `// io-ok: <reason>`.
- UI uses `AppColors` only. New chrome accents:
  `AppColors.formMasterAccent` or `AppColors.porchAmberOf(context)`;
  `AppColors.onChaosAccent` on solid amber. CI `theme-lint` fails new
  `Colors.blueAccent` under `lib/` unless `// theme-keep: <reason>` and the
  colour is a genuine semantic status hue the maintainer approved **in this
  conversation**.
- Creation wizards follow `create_character_page.dart`: AppBar step dots,
  linear `_currentStep`, bottom nav. No side-menu wizards.
- `GlobalKey`s are owner-scoped. Never `GlobalObjectKey(model)` — two live
  routes showing the same object crash. The owner holds an identity map.

---

## Chat contracts (do not “simplify”)

These are live product behaviour. Tests pin them. Do not collapse the cases.

**Mouth speech** — `lib/utils/think_tags.dart` `resolveMouthSpeech`:

- Closed think-only (`<think>…</think>` and nothing visible) **lifts** so
  the bubble speaks.
- Unclosed cut-off (stream still inside `<think>`) stays tagged. Salvage the
  closer; do not promote. Thought chip stays; display stays empty.

**Continue** is its own product, not regen-lite:

- Does **not** tick the story clock.
- Post-gen scores the **new** text only (`newPart`), not the whole reply
  (that would double-apply).
- `_runPocketsPass(asContinuation: true)` **keeps** the message's original
  `pockets_before` (unions new transfer recipients, appends receipts) so
  regen / tail-delete rewind to the turn base.
- Finalize keeps pre-continue + new body. Partial / history builders use
  think-stripped, history-safe text.

**Pockets hide, they do not erase.** `pocketsFor` returns `null` when the
feature is off (no eval, no injection, no sidebar panel). Stored records and
the session save/load wire stay as they were. Switching the feature back on
finds the kit still there.

**`objectivesActive` is a live AND** — per-chat `_objectivesEnabled` AND
`realismSettings.objectivesEnabled`. Not a stored AND at seed time. Flipping
the global off must take effect on the next turn.

**Clock.** Passage of time needs a **model call**, not the Realism Engine.
`standaloneClockEnabled` (default off) is the opt-in driver when the engine
is off. The time **prompt** gates on `_clockRunning` (either driver), never
on `passageOfTimeEnabled` alone. Regen/swipe rewind from
`story_clock_before`. One-shot must not apply minutes (would double).

**Evals score the user's message**, never the character's own reply. They
fire before generation. A regen with the same inputs must reproduce the same
deltas; disagreement is a rewind bug. Non-scalar eval inputs must join
`captureCadenceAndFeelings` / `restoreFromMessageState`.

**Eval transport.** Structured evals try native tool calls first
(`fireStructuredEval`), then the regex/JSON text floor. Do **not** put GBNF
on the JSON floor — it produced empty Kobold replies. The three
prefix-sharing judges must send the **same** `kJudgeEvalTools` list (named
`tool_choice` selects the function). Per-eval one-tool lists defeat the
Kobold jinja KV-cache. Director / character-creator / story prose stay
text-only. Detail: `docs/design/tools-transport.md`.

**One-shot** is a tri-state (`auto` / `on` / `off`). When active it must
match the multi-call path for observable Realism/Needs. Local backends stay
multi-call in `auto`.

**Posture, climax, pockets** are post-generation. When two or more of those
passes are live, one fused reply-facts call is transport only — each feature
keeps its own gate.

**Chaos** is not a Realism dependency. It has a per-chat switch and a global
default (`chaosModeDefault`, OR-override, default false). Every conversation
**start** path must seed that global or the switch is silently missing on
that path. Grep `seedFromGroupOrExt` / `chaosModeDefault` rather than
trusting a site count.

**Growth Rings** are per-chat, per-character character evolution.

**Journal** is per-chat, per-character. Cards never cross chats. Item cards
are written from applied pocket events when **both** pockets and journal
are on. Review-first parks a batch; Apply uses the same applier as auto.

**Group restore** keys by **message speaker id**, not whoever is active
after post-gen.

---

## Path-complete chat work

Mandatory for generation, Continue, regen/swipe/delete/edit, Realism, Needs,
Journal, Growth, Pockets, RAG, or group orchestration.

Fill the matrices in
[docs/design/path-complete-chat-work.md](docs/design/path-complete-chat-work.md)
in the completion summary (or mark N/A with one line why).

Sibling-path law: fixing history think-strip without Continue, Journal
rewrite without Growth, or 1:1 pockets without group speaker restore is
incomplete. Grep the twin.

---

## Parity laws

**Web ↔ desktop.** Everything the user can see, tap, or configure on
desktop ships in `web_ui/` in the same work — theming, settings/toggles,
dialogs, sidebars, buttons, indicators. Adaptation to phone vs wide is
expected (separate shells if UX needs it). Omission is not. Silent “web
later” is a violation unless the maintainer deferred **that item** in the
**current** conversation.

A Stoop endpoint or field needs three edits: Dart client
(`lib/services/backporch/`), relay (`lib/services/web/` routes + facade),
and `web_ui/src/stoop/`. The PWA talks to the Dart `/api/stoop/*` relay, not
the backend directly.

**Realism / Needs 1:1 ↔ group.** Observable results for a character must
match. Storage may be scalars vs `_groupRealism`. Do not add a second
simulation. After post-gen, `_saveScalarsIntoGroupRealism` is what makes
group state persist.

Presentation may duplicate (desktop vs phone CSS). Engine logic may not.

---

## Database

Drift library: `lib/database/database.dart` (annotation, ctor,
`schemaVersion`, migration stub) plus parts for tables, the onUpgrade
ladder, repair, and queries. Table **declaration order is load-bearing** for
codegen. After a schema or layout change, regenerate
`dart run build_runner build` and keep `database.g.dart` honest — a
file-move that changes declaration order is a real diff, not noise.

Migrations are additive. A mistake in the ladder corrupts user libraries.
Breaking changes (removed/renamed columns) need maintainer confirmation
before you start.

**Identity:** `objectives`, `message_embeddings`, and `data_bank_entries`
key `character_id` by **`stableGroupId`** (portable image-filename
basename), not `characters.id`. `avatar_images` uses the UUID. Joining the
former against the UUID matches nothing and marks real rows as orphans.
Resolve via `stableGroupIdFrom()` in `lib/utils/character_id.dart`.

---

## The Stoop

Opt-in, account-gated, 18+ hub. Dart client in `lib/services/backporch/`.
Backend source and hosting are **not in this repo**. Do not add hosts, IPs,
buckets, or credentials.

The live fleet is a mix of app versions. Responses are additive-only. Never
tighten a request the old app still sends. Breaking changes are new
endpoints; keep the old one until the fleet ages out. Parse defensively.

---

## Engines

No Python, no Rust, no helper processes. See
`docs/design/sidecar-retirement.md`.

Waifu Coder may download a pinned GitHub OpenCode zip into the app-support
closet and run `opencode serve` on 127.0.0.1. That is process management,
like Kobold. Do not reintroduce an in-process coding loop. Do not use the
user's Homebrew OpenCode or `~/.config/opencode` as the product copy.

---

## Branches and CI

| Change | Branch |
|--------|--------|
| Features, fixes, experiments | `Rawhide` |
| Tagged stable releases | `main` |

Work lands on `Rawhide`. Direct PRs to `main` are almost never accepted.

GitHub `schedule:` triggers run from the **default** branch. A change to
`nightly.yml` must land on `main` or nightlies keep the old file.
`test-integrity.yml` is `pull_request_target` — it runs the **base**
branch's copy.

**CI jobs that actually fail a PR** (`.github/workflows/ci.yml`):

| Job | Fails when |
|-----|------------|
| `analyze` | Analyzer issues in **changed** `.dart` files |
| `test` | Unit/widget tests (`--concurrency=4 --exclude-tags golden`) |
| `e2e-smoke` | A suite under `integration_test/*_test.dart` fails (one process per file, 5 shards × 3 OSes) |
| `web-tests` | `npm run lint` / `npm test` in `web_ui/` |
| `theme-lint` | New raw `Colors.blueAccent` under `lib/` |
| `io-lint` | New sync I/O under `lib/ui/` |
| `golden` | Pixel golden drift (Linux image) |

`full-lint` is scheduled / branch-push and is **not** a hard PR gate (it
ends `|| true`). Do not tell contributors the whole tree is analyzed on
every PR.

**Test integrity** (`.github/workflows/test-integrity.yml`): modifying or
deleting an existing test, golden, baseline, `test/deps/dependency_floors.json`,
anything under `.github/`, `scripts/ci-local.sh`, or `analysis_options.yaml`
fails until a maintainer applies **`approved-test-change`**. Adding a **new**
test file never blocks. `integration_test/support/` (harness, no asserts) is
reported, not blocked.

The dependency-floor test fails if `pubspec.lock` moves a package
**backwards**. Do not “fix” that by regenerating
`test/deps/dependency_floors.json`.

Do not edit `pubspec.yaml` version — CI/CD normalizes releases.

---

## Testing

- A new guard must be **proven red** (break the fix, see fail) then green.
  If deleting the product call site still leaves the test green, it is
  decoration — say so or fix the test. Do not ship that test.
- Prefer one broad interaction / E2E journey over another pure unit of a
  helper. Goldens answer “does it look right”; a tap answers “can a user do
  this.”
- Inventory of E2E suites: [docs/design/e2e-coverage-inventory.md](docs/design/e2e-coverage-inventory.md).
  Before persist-asserting chat state: `await d.waitSendable()`
  (`isSettlingTurn` is part of the turn).
- Changing an existing test needs a written rationale: what behaviour
  changed, why the old assertion is now false. If the test was right, fix
  the change.

### No stub tests

A pin that plants the answer is not a pin. **Forbidden:**

- flutter_test / `HttpOverrides` stub clients that return canned 400/200
  without a real listening server
- Mockito / mocktail HTTP or API fakes that hand the suite its JSON
- Hand-rolled “fake success” maps that never exercise the real client stack
- Stub LLMs that return the expected string so the test cannot fail
- `FakeStoopServer`, `integration_test/support/fake_stoop.dart`, or an
  inline `HttpServer.bind` that invents JSON behind
  `BackporchApi.overrideBaseUrl`

Those stay in old E2E journeys that already use them. **New pins of Stoop
/ Backporch behaviour must not add more.**

Required for Stoop / Backporch / other network features:

- Talk HTTP to a **real** Stoop/backporch server — the live hub
  (`https://api.frontporchai.app`) or the team’s real droplet/API.
- Not a toy. Not `overrideBaseUrl` at loopback JSON.

If CI has no credentials or network, tag the test `live` / `stoop_live`
and **skip only when the env is absent**. Do not replace it with a stub.

Runtime env (`Platform.environment`, not dart-define):

- `STOOP_LIVE_URL` — optional. Defaults to `https://api.frontporchai.app`.
- `STOOP_TEST_EMAIL` — required to run.
- `STOOP_TEST_PASSWORD` — required to run.
- `STOOP_TEST_TOTP` — optional, if that account has 2FA.

```
STOOP_TEST_EMAIL=… STOOP_TEST_PASSWORD=… flutter test --tags stoop_live
```

CI job `stoop-live` in `.github/workflows/ci.yml` injects those env vars
from repo secrets on same-repo PRs and Rawhide/main pushes. Fork PRs skip
the job. Do not print the secrets. Local/CI without the vars skips. That
is a skip, not a pass-by-stub.

Model download pins: real `file://` or real HTTP of a tiny fixture the
test controls (a real listening server serving a real file), or tag
`live`. No 400-stub theater.

---

## Public text

No personal names in user-facing copy, `docs/Rawhide.md`, `docs/main.md`,
release notes, or other text that ships to users.

User-facing “What’s New”:

- Nightly / Rawhide → `docs/Rawhide.md`
- Stable dialog → `docs/main.md`
- Long-form history → `docs/release-notes.md`

Never paste commit messages or agent session logs into those files.

Do **not** append to `.claude/changelog.md`. That file is a pointer, not a
progress diary. `git log` is the history.

---

## Files that need a reason before you edit them

- `lib/database/database.dart` and its migration parts — plan first.
- `lib/main.dart` — init order is delicate.
- `pubspec.yaml` — not for version bumps; new deps need a license check.
- `analysis_options.yaml` — lint set.
- `scripts/` — release/build. `scripts/ci-local.sh` is also test-integrity
  protected because it must match the CI golden/test jobs.

---

## When the maintainer cannot read Dart

Green analyze + green tests are not a second look. Grep twins (1:1 ↔ group,
Continue ↔ regen, Journal ↔ Growth, desktop ↔ web/relay). Prove one new
guard red, then green — or say you could not.

For chat/realism/memory work, fill the path-complete checklist in
[docs/design/path-complete-chat-work.md](docs/design/path-complete-chat-work.md)
(or mark N/A with one line why).

A remote sandbox cannot self-certify a UI change. Say so. End with a 2–5
step poke script.

If you cannot finish the request without leaving the tree broken, stop and
say so. No stubs, no “skeleton for later.”

---

## Git

- Conventional commit first line, then **why** it mattered.
- Never amend or rewrite another author's commits.
- Never `git checkout -- <file>`, `git restore <file>`, or
  `git checkout HEAD -- <file>` without explicit approval in this
  conversation. Those destroy uncommitted work.

## Community

Discord: https://discord.gg/e4tET6rpdv
