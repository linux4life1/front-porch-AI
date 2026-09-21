<!--
Thanks for contributing! Keep this short — a clear paragraph beats a filled-in
form. Delete any section that doesn't apply.

Not finished yet? Open it as a DRAFT. You'll get feedback on the approach
instead of a list of unfinished pieces.
-->

## What and why

<!-- What changes, and what problem it solves. If it fixes an issue, link it. -->

## Target branch

<!-- All work (features, fixes, experiments) -> Rawhide. main is tagged
releases only. -->

- [ ] This PR targets the correct branch ([which branch?](https://github.com/linux4life1/front-porch-AI/blob/Rawhide/CONTRIBUTING.md#which-branch-do-i-target))

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor / cleanup
- [ ] Documentation
- [ ] Build / CI

## How was this tested?

<!-- Required. "It compiles" is not testing. Say what you actually ran and saw.
Front Porch AI ships on Windows, macOS and Linux — tell us which you used, and
flag anything you could not verify. -->

Tested on: <!-- Windows / macOS / Linux — and which ones you couldn't check -->

- [ ] `flutter analyze` is clean
- [ ] `flutter test` passes
- [ ] Ran the app and exercised the change by hand

## Parity

<!-- Only if your change is user-visible. Delete this section otherwise. -->

- [ ] Web/mobile UI (`web_ui/`) updated to match — including any new setting or toggle
- [ ] Realism/Needs behaviour is identical in 1:1 and group chats
- [ ] Not applicable / deferral agreed with the maintainer in this PR

## Dependencies and licensing

<!-- Only if you added a package, an asset, or something the app downloads. -->

- [ ] No package in `pubspec.lock` moved backwards (the dependency-floor guard)
- [ ] New dependencies are license-compatible with AGPL-3.0-or-later
- [ ] Any model/voice/asset the app downloads names its source and license below

Source and license: <!-- e.g. "kokoro-multi-lang-v1_0, Apache-2.0" -->

## Checklist

- [ ] New files carry the AGPL header
- [ ] New/refactored UI uses `AppColors` (no hard-coded `Color(0xFF…)`, no raw `Colors.whiteXX`/`blackXX`)
- [ ] I ran `dart format` only on Dart files I edited (never `dart format .`)
- [ ] I did not edit the version in `pubspec.yaml`
- [ ] Errors are logged or surfaced, not silently swallowed
- [ ] My contribution is licensed under AGPL-3.0-or-later and I have the right to submit it

## Screenshots

<!-- Required for UI changes. Before/after if you're changing something existing.
Include light AND dark mode if you touched colours. -->
