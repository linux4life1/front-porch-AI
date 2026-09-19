# AI agent rules — Front Porch AI

**Read [CLAUDE.md](CLAUDE.md) before writing code.** That file is the
project's engineering law. This file exists because many tools look for
`AGENTS.md` first. The two must not contradict. If they ever do, CLAUDE.md
wins and this file is stale.

Humans: [CONTRIBUTING.md](CONTRIBUTING.md). Driving agents without reading
Dart: [docs/maintainer-agent-playbook.md](docs/maintainer-agent-playbook.md).

## What you must believe

- **No sidecars.** TTS, STT, embeddings, expression, Draw Things run
  in-process. Do not spawn helper processes. Waifu Coder may manage an
  OpenCode binary the way the app manages Kobold — that is not a chat sidecar
  and not a Dart coding loop.
- **File size.** Handwritten Dart under `lib/` stays **under 500 lines**.
  That is CI via `test/hygiene/god_file_ratchet_test.dart` (`kGodFileBar`
  is 500, empty `test/baselines/god_files.json`). Do not add baseline
  leftovers — split the file. Generated `.g.dart` (including
  `lib/database/database.g.dart`) is excluded from that ratchet and owned
  by `test/hygiene/generated_dart_size_test.dart` / Drift
  `generate_manager: false`. Do not invent a second 500-line gate.
- **Style.** DRY, readable Dart, few comments. `dart format` the files you
  already edited. Never `dart format .`. Touched code must be analyzer-clean.
- **Chat contracts.** `resolveMouthSpeech`: a closed think-only body is
  spoken; an unclosed cut-off stays tagged. Continue does **not** tick the
  story clock. Continue `asContinuation` keeps the turn's `pockets_before`.
  Pockets **hide**, they do not erase. `objectivesActive` is a **live AND**
  of the per-chat switch and the global switch.
- **Path-complete chat work** for generation, Continue, regen/swipe/delete,
  Realism, Needs, Journal, Growth, Pockets, RAG, or group orchestration. Fill
  [docs/design/path-complete-chat-work.md](docs/design/path-complete-chat-work.md).
  Continue is not regen-lite. Journal rewrite twins Growth. 1:1 twins group.
- **Web/desktop parity.** User-visible work ships in Flutter **and**
  `web_ui/` (including settings/toggles), or the maintainer defers that item
  in the current conversation.
- **Realism/Needs 1:1 ↔ group.** Observable behaviour for a character is the
  same in both modes. Orchestration may differ; results may not.
- **Tests.** Adding a new test file is fine. Editing or deleting an existing
  test, golden, baseline, workflow, or `analysis_options.yaml` needs the
  maintainer's `approved-test-change` label. Do not quietly edit a test to
  make CI green. A new guard must be proven red, then green.
- **Public text.** No personal names in user-facing copy, release notes, or
  docs that ship to users.
- **Never** edit the version in `pubspec.yaml`, run destructive git restore
  (`git checkout --`, `git restore`) on files, or imply a sandbox launch
  happened when it did not.

## Done means

Path-complete checklist when chat/realism/memory is in scope. A 2–5 step
poke script. `flutter analyze` clean on touched Dart. Web shipped or
explicitly deferred. Green suite is not ship.
