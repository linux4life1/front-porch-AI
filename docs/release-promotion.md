# Release promotion: Rawhide → main

How a stable release is cut. `main` only moves this way; every feature and
fix lands on `Rawhide` first. The mechanical part is
`scripts/promote-rawhide-to-main.sh`; this page is the order around it.

The whole thing takes an hour of wall-clock, most of it CI.

## 0. Decide the version and the name

- A release that changes behaviour (new features, a raised floor, a changed
  engine rule) is a **minor** bump: `v1.5.0`. Fixes only is a patch:
  `v1.4.2`.
- Releases have a name (`v1.4.0 — Toolbox`, `v1.5.0 — Revenge of the
  Kobold`). It goes in the `docs/main.md` heading and the GitHub release
  title.
- The tag drives the version: `release.yml` rewrites `pubspec.yaml` and
  `lib/app_version.dart` from the tag. Do not edit the pubspec version.

## 1. Freeze Rawhide

- Everything meant for the release is merged; the last Rawhide CI run is
  green (`gh run list --branch Rawhide --limit 1`).
- The latest nightly is from that tip, or close to it, and someone has
  opened it. The nightly cron runs from `main`'s `nightly.yml`; it can be
  forced from the Actions tab with its checkbox.

## 2. Notes on Rawhide (they ride the promotion)

- `docs/release-notes.md`: a `## vX.Y.Z — Name` entry at the top of the
  history, the Table of Contents line, and the "current stable release"
  sentence. Check that the previous release has its entry too; v1.4.1 was
  missed once.
- `docs/Rawhide.md` is the nightly notes and is not touched for a release.

Commit to Rawhide and push before running the script, or the candidate
will not carry them.

## 3. Notes on main (the guarded files)

The script keeps main's copies of `README.md`, `docs/main.md` and
`.claude/changelog.md`, so a release's stable-facing text is written **on
main** first, as a plain docs commit:

- `docs/main.md`: a new `## vX.Y.Z — Name` section at the very top. Its
  bullets are the in-app "Update Available" dialog and the GitHub release
  body, verbatim (`release.yml` takes everything under the first `## `
  heading). Keep it to the high points: about fifteen bullets, user words,
  no names.
- `README.md`: the "New in X.Y.Z" callout near the top, and any line the
  release changes (a floor, a supported platform). Rawhide's README never
  reaches main, so a README fix on Rawhide must be made here as well.

## 4. Build the candidate

From a **clean** checkout (the script refuses a dirty tree; a scratch
worktree on `origin/main` is easiest):

```bash
bash scripts/promote-rawhide-to-main.sh
```

It creates `release/promote-<date>-<rawhide sha>` off main whose tree is
Rawhide's byte for byte except the guarded files, then runs its gates:
workflows identical to Rawhide, `release.yml` identical, each guarded file
identical to main, the tree differs from Rawhide only in the guarded
paths, no conflict markers, every workflow YAML parses. It never touches
main, pushes or tags.

A gate that fails on tooling (no YAML parser) is not a bad tree; the
script now tries python3 with PyYAML, then ruby.

## 5. Push the candidate, PR to main, merge

```bash
git push -u origin release/promote-<...>
gh pr create --base main --head release/promote-<...> --title "Release: promote Rawhide → main for vX.Y.Z"
```

- CI runs on the PR. "Guard protected paths" fails on a promotion by
  design (it sees every test change since the last release); apply
  `approved-test-change` and it re-runs.
- Infrastructure failures (a Linux runner stuck in the apt step, a
  Windows native-assets build that fails with no cause line, a WebKit
  crash) are re-run with `gh run rerun <run> --failed`; a test that fails
  twice is looked at, not re-run.
- Merge **fast-forward only**, never squash: `main` must point at the
  candidate commit so the tag lands on the tree the script verified.

```bash
git checkout main && git pull --ff-only origin main
git merge --ff-only release/promote-<...>
git push origin main
```

## 6. Tag and publish

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
```

`release.yml` builds Windows, macOS and Linux, sets the version from the
tag, and publishes the GitHub release with `docs/main.md`'s first section
as its body. The title comes out as the bare tag; set the name by hand:

```bash
gh release edit vX.Y.Z --title "vX.Y.Z — Name"
```

## 7. After

- A stable install sees the update dialog on its next start (the app's
  update check reads GitHub releases/latest).
- Dependabot alerts are computed against `main`; the ones already fixed on
  Rawhide clear on their own once the promotion lands.
- The Discord post.
- Delete the candidate branch once the tag exists.
