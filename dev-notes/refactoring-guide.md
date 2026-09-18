# God File Refactoring Guide

**This guide is finished work. The rules that are still in force live in
[`CLAUDE.md`](../CLAUDE.md) — read that instead.**

## Why this is a stub

Until 2026-09-18 this file was the seven-stage plan for breaking apart the
original god files: lift `ChatMessage`, split `chat_page.dart`, split
`chat_service.dart` into domain services, then the creator, settings, web
server and storage service. Every one of those stages shipped. The campaign
completed on 2026-08-07, `test/baselines/god_files.json` is `{}`, and
`test/hygiene/god_file_ratchet_test.dart` now holds the line at 1,000 with an
empty baseline. A stage-by-stage plan for work that is done is history, and git
has it.

Two parts had gone from "done" to actively wrong:

- It opened by promising a **full Riverpod migration** after the extractions.
  That migration was evaluated and **rejected** — converting ~634 consumer call
  sites, 39 `ChangeNotifier` services and the `main.dart` init order for no
  user-visible benefit. `CLAUDE.md` now carries the narrow rule that replaced
  it: Riverpod is for new, self-contained state that needs no change to
  `ChatService`, `StorageService` or the provider graph.
- It taught a **deprecation shim pattern** — keep the old entry point beside
  the new one. Current law is the opposite: one contract, one implementation,
  no shim next to the real path.

## What survived, and where it lives now

The parts worth keeping were never specific to those seven stages, and
`CLAUDE.md` is their home:

| Idea | Where it lives now |
|---|---|
| Extract, don't rewrite; never refactor and add features in one change | `CLAUDE.md` → "Code File Size Limits & Single Responsibility" |
| Every Dart file under 500 lines; no `lib/` file may reach 1,000 | same section, plus the CI ratchet |
| A new guard must be proven to fail before it is trusted | `CLAUDE.md` → "Testing Expectations" |
| Realism/Needs parity across 1:1 and group | `CLAUDE.md` → "Realism & Needs System Parity" |
| Path-complete chat work | [`docs/design/path-complete-chat-work.md`](../docs/design/path-complete-chat-work.md) |

The remaining files over 500 lines, and the order to take them in, are
inventoried in
[`docs/superpowers/plans/2026-09-18-rawhide-debt-payback.md`](../docs/superpowers/plans/2026-09-18-rawhide-debt-payback.md).
