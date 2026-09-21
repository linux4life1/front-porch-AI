# Contributing to Front Porch AI

Thanks for your interest in contributing. Contributions are welcome from
developers of all skill levels.

## Licensing

Front Porch AI is licensed under the **GNU Affero General Public License,
version 3 or (at your option) any later version** (`AGPL-3.0-or-later`).
Releases before v0.9.0 were GPLv3.

**By submitting a contribution — code, documentation, assets or anything
else — you agree that it is licensed under AGPL-3.0-or-later**, and you
confirm that you have the right to submit it under that license. If you are
contributing work you do not personally own, make sure that is permitted and
compatible before opening a pull request.

There is no Contributor License Agreement and no copyright assignment. You
keep the copyright in your own work.

- **New source files need the AGPL header.** Copy it from any existing file
  in `lib/`.
- **Mind what your dependencies drag in.** A package with an incompatible
  license cannot be merged. A silent downgrade of an existing package fails
  the dependency-floor guard (see [Required Checks](#required-checks)).
- **Model weights are not code.** Anything the app downloads at runtime (TTS
  voices, embeddings, engines) is fetched by the user from a third party.
  If you add a downloaded model, say in the PR where it comes from and what
  it is licensed under.

Read the AGPL before contributing, and get your own legal advice if you
need it.

## Code of Conduct

Be respectful and constructive.

## Which branch do I target?

| Change type | Target branch |
|---|---|
| All work (features, fixes, experiments) | `Rawhide` |
| Tagged stable releases | `main` |

Work lands on `Rawhide`. Direct PRs to `main` are almost never accepted.
PRs opened against the wrong branch will be asked to move.

## Development setup

### Prerequisites

- **Flutter 3.47.0** (what CI uses). Dart SDK constraint `^3.10.8`.
  macOS **12 Monterey** is the floor.
- [Git](https://git-scm.com/)
- Windows 10+, macOS 12+, or Linux
- **Linux** desktop builds:
  `libgtk-3-dev ninja-build libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`
- **Node 20+** only if you touch `web_ui/` (CI uses Node 24)

There is **no Rust toolchain, no Python, and no `pip install` step.** Every
engine runs in-process. See `docs/design/sidecar-retirement.md` before
touching an engine — **do not reintroduce sidecars.**

### Setup

```bash
git clone https://github.com/<your-username>/front-porch-AI.git
cd front-porch-AI
flutter pub get

# Only if you are working on the web/mobile UI
cd web_ui && npm ci
```

Database schema changes also need:

```bash
dart run build_runner build   # regenerates lib/database/database.g.dart
```

## Pull request process

1. Branch from `Rawhide` (or `main` only for a tagged-release chore).
2. Keep the change scoped to one thing.
3. Run the [required checks](#required-checks) locally.
4. Write a commit message that explains **why**, not just what — see the
   commit section of [CLAUDE.md](CLAUDE.md).
5. Open the PR against the same branch. GitHub fills the PR template;
   delete sections that do not apply.
6. Say what you tested, and on which platforms.

Draft PRs are welcome when you want direction on an approach.

## Required checks

CI runs these on PRs to `main` and `Rawhide`. Run them locally first.

```bash
flutter analyze
flutter test --concurrency=4 --exclude-tags golden
flutter test --tags golden              # pixel goldens; authored on Linux
cd web_ui && npm run lint && npm test   # only if you touched web_ui/
```

Linux goldens that a Mac `flutter test` never executes:

```bash
./scripts/ci-local.sh
```

| Job | What fails it |
|---|---|
| `analyze` | Analyzer issues in the Dart files your PR changed |
| `test` | Failing unit/widget test, including the dependency-floor guard |
| E2E smoke | The app failing a suite in `integration_test/*_test.dart` |
| `web-tests` | `tsc` errors or failing vitest specs |
| `theme-lint` | Adding a raw `Colors.blueAccent` under `lib/` |
| `io-lint` | Adding synchronous I/O under `lib/ui/` |
| `golden` | A pixel golden that changed without being updated |

Two surprises:

- **Dependency-floor** (`test/deps/dependency_floor_test.dart`) fails if any
  package in `pubspec.lock` moves *backwards*. Do not fix a failure by
  regenerating `test/deps/dependency_floors.json` — find what pulled the
  version back.
- **`io-lint`** exists because a single `existsSync` in a widget `build()`
  was invisible on macOS and much slower on Windows under Defender. A line
  that cannot run in a build path may carry `// io-ok: <reason>`.

**Editing or deleting an existing test, golden, baseline, workflow, or
`analysis_options.yaml`** fails `test-integrity.yml` until a maintainer
adds the **`approved-test-change`** label. Adding a **new** test file never
blocks.

### Format only the Dart files you already touched

If you edited `foo.dart`, run `dart format foo.dart` (tall style). Do
**not** run `dart format .` or format a directory. Do **not** format an
existing test you were not already changing. After formatting, fix any lint
the wrap introduced.

## Project rules that trip people up

[CLAUDE.md](CLAUDE.md) is the full engineering law. The ones that most
often send a PR back:

- **Handwritten Dart under `lib/` stays under 500 lines.** That is CI
  (`test/hygiene/god_file_ratchet_test.dart`, empty
  `test/baselines/god_files.json`). Split instead of growing. Generated
  `.g.dart` (including `database.g.dart`) is a different test
  (`generated_dart_size_test.dart`). Do not invent a second 500-line gate.
- **Web/mobile parity.** A user-visible desktop change ships in `web_ui/`
  in the same work, including its settings and toggles, unless the
  maintainer defers that item on the PR.
- **Realism/Needs parity.** Observable behaviour must match in a 1:1 chat
  and a group.
- **Theme system.** `AppColors` only. New chrome accents use
  `AppColors.formMasterAccent` or `AppColors.porchAmberOf(context)`.
- **Barrel imports** where a barrel covers the file.
- **Do not edit `pubspec.yaml` version** — CI/CD normalizes it.
- **Database schema changes need a plan.** The Drift `onUpgrade` ladder is
  load-bearing. Additive columns are the safe default. Breaking changes
  need maintainer confirmation first.
- **Never silently swallow errors.** Log them or surface them.
- **Public text has no personal names.**

## Testing

```bash
flutter test --concurrency=4 --exclude-tags golden
flutter test --coverage
flutter test test/path/to/file.dart
flutter test -n "test name"
flutter test --tags golden
# E2E: one file per invocation
flutter test integration_test/app_smoke_test.dart -d linux
```

Aim for 80%+ coverage on new code, and test error paths. Mock external
dependencies.

For anything that cannot be unit-tested, build and run the app and say in
the PR what you exercised and on which platform. "It compiles" is not
testing.

## Building

```bash
flutter build linux
flutter build windows
./scripts/build-macos.sh   # signs, packages and notarizes
```

Native libraries ship inside their pub packages. No post-build copy step.

## Reporting issues

1. Check existing issues first.
2. Include steps to reproduce, expected vs actual behaviour, OS and app
   version, and logs or screenshots where relevant.
3. **Do not open a public issue for a security problem.** Use the
   [Security tab](https://github.com/linux4life1/front-porch-AI/security)
   — see [SECURITY.md](SECURITY.md).

## Additional resources

- [CLAUDE.md](CLAUDE.md) — engineering law (AGENTS.md points here)
- [Path-complete chat work](docs/design/path-complete-chat-work.md)
- [Flutter docs](https://docs.flutter.dev/) · [Effective Dart](https://dart.dev/effective-dart/style)
- [Discord](https://discord.gg/e4tET6rpdv)

Thanks for contributing to Front Porch AI.
