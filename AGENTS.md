# AGENTS.md

Read [CLAUDE.md](CLAUDE.md) first. It is the engineering law for this
repository; this file exists because some tools look for `AGENTS.md`. If
the two disagree, CLAUDE.md wins and this file is stale.

The parts of CLAUDE.md that bite most often:

- **What CI enforces** — the ratchets (500-line files, no new `part`
  files, raw colours, raw dialogs, sync I/O in UI), the `## Hand-check`
  rule on UI PRs, and the `approved-test-change` label for any edit to an
  existing test, golden, baseline or workflow.
- **Style** — every UI element, desktop and web, follows the user-selected
  theme in light and dark; no colour that only fits Porch.
- **Chat contracts** — Continue is not regen, Pockets hide and never
  erase, Needs and Objectives are live gates, the clock needs a model call.
- **Path-complete chat work** — cover Continue, regen, swipe, delete, 1:1
  and group, Journal and Growth, desktop and web, or say which you skipped.
- **Parity** — desktop work ships with its `web_ui/` twin in the same
  change unless the maintainer deferred it in this conversation.
- **Tests** — new guards fail without the fix; no stub network tests; no
  test that scripts a model's answer and asserts it back.
- **Git** — no `git restore` or `git checkout --` on a file without
  approval; never edit the `pubspec.yaml` version.

Humans: [CONTRIBUTING.md](CONTRIBUTING.md). Maintainer prompts:
[docs/maintainer-agent-playbook.md](docs/maintainer-agent-playbook.md).
