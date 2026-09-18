# Developer notes

Working notes for maintainers and coding agents. **This is not user
documentation** — see [`docs/`](../docs/) for that, and
[`CLAUDE.md`](../CLAUDE.md) for the project's rules.

These files live outside `docs/` on purpose: `.github/workflows/pages.yml`
publishes the whole of `docs/` to the documentation site.

| File | What it is |
|---|---|
| [`refactoring-guide.md`](refactoring-guide.md) | The god-file modularization strategy — how a large service gets broken into focused leaves without breaking Realism/Needs parity |
| [`release-promotion.md`](release-promotion.md) | Runbook for promoting `Rawhide` to `main` and cutting a release |
| [`web-parity.md`](web-parity.md) | Desktop ⇄ web/mobile parity checklist |

Nothing here is authoritative over `CLAUDE.md`. Where they disagree, `CLAUDE.md`
wins and the note is out of date.
