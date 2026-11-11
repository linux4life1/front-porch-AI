# AGENTS.md

Read [CLAUDE.md](CLAUDE.md) first. It is the engineering law for this
repository; this file exists because some tools look for `AGENTS.md`. If
the two disagree, CLAUDE.md wins and this file is stale.

The parts of CLAUDE.md that bite most often:

- **One UI (non-negotiable)** — desktop, web wide, web phone, 1:1 and
  group are one screen: same controls, same places, same order, same
  behaviour; only the layout adapts. Every UI change ships desktop and
  `web_ui/` together, and drift fails CI (`one_ui_parity_test`, the
  `group_sidebar_parity` goldens, `settings_parity_manifest_test`).
- **Screenshots are required** — every UI or UX PR carries screenshots of
  each changed screen, desktop and web, in the PR description's
  `## Screenshots` section (never a comment), as GitHub uploads or files
  under `docs/screenshots/`, using seeded or synthetic data only. The PR
  rules check fails without them; no label skips it and no author is
  exempt.
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
  change unless the maintainer deferred it in this conversation (the
  One UI rule above, applied per pairing).
- **Tests** — new guards fail without the fix; no stub network tests; no
  test that scripts a model's answer and asserts it back.
- **Git** — no `git restore` or `git checkout --` on a file without
  approval; never edit the `pubspec.yaml` version.

Humans: [CONTRIBUTING.md](CONTRIBUTING.md). Maintainer prompts:
[docs/maintainer-agent-playbook.md](docs/maintainer-agent-playbook.md).
