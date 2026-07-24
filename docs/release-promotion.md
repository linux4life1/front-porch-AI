# Release runbook — promoting Rawhide to `main`

How to cut a stable release by promoting `Rawhide` onto `main` **without mangling
the CI workflows** (`release.yml` / `nightly.yml`). Automated by
[`scripts/promote-rawhide-to-main.sh`](../scripts/promote-rawhide-to-main.sh).

## Why not just `git merge Rawhide`?

`main` and `Rawhide` both carry their own copies of the big workflow files, and a
plain 3-way merge asks a human to hand-resolve conflicts inside 50 KB of YAML.
That hand-resolution is exactly what has corrupted `release.yml` before (see the
old commit *"restore missing shim DMG step lost during merge conflict
resolution"*). Two more traps make it worse:

- **`main` is the repo's default branch.** GitHub only runs the nightly `cron`
  from the **default branch's** copy of `nightly.yml`, so `main`'s workflows are
  live production infrastructure — a bad merge there breaks nightly + release
  builds, not just a dev branch.
- **A shallow clone has no merge base**, so a merge run from one turns *every*
  file into an add/add conflict. Always work from a full clone
  (`git fetch --unshallow`).

## The strategy

`Rawhide` is the forward source of truth and is a functional **superset** of
`main` (features that landed on `main` as stable hotfixes were forward-ported to
Rawhide). So the release is a **"Rawhide wins"** promotion:

- main's tree **becomes** Rawhide's tree wholesale — the workflows are Rawhide's
  **verbatim**, so there is no conflict to hand-resolve and nothing to mangle.
- A short, explicit **guard list** of stable-facing files keeps `main`'s version:

  | Guarded file | Why it stays main's |
  |---|---|
  | `README.md` | `main` has a distinct stable-facing README (badges, install, stable "What's New"). Rawhide's dev README must not overwrite it. |
  | `docs/main.md` | Stable-channel "What's New" that feeds the in-app update dialog. |

  Extend it by exporting `GUARD_PATHS="README.md docs/main.md …"` before running
  the script.

The result is recorded as a real merge commit (parents `[main, Rawhide]`), so
ancestry stays connected and the **next** promotion has a clean merge base.

## Pre-flight checklist (before you start)

- [ ] Rawhide is stabilized: CI green, `flutter analyze`/tests clean, goldens current.
- [ ] Full clone, not shallow: `git rev-parse --is-shallow-repository` → `false`
      (`git fetch --unshallow` if needed).
- [ ] Working tree clean (commit/stash anything local).
- [ ] Version decided. (Don't hand-edit `pubspec.yaml`; CI normalizes the version
      from the tag — see CLAUDE.md.)
- [ ] Stable "What's New" ready in `docs/main.md`, and `README.md` on `main` is the
      one you want to ship (these are guarded — edit them on `main`, not Rawhide;
      drafts can be prepared and reviewed on a candidate/practice branch first, but
      they only count once committed to `main`).
- [ ] **Screenshots are current**: the README hero (`docs/screenshots/home_new.png`)
      and any shots the release announcement or website will reuse are retaken on the
      current UI. (The existing `docs/screenshots/` set predates the warm-porch
      redesign — stale for 1.0.)
- [ ] **Website refresh prepared**: `frontporchai.app` must be updated alongside the
      release — new screenshots, current feature descriptions, and version/download
      links. The site is self-hosted and built from `website/` in this repo; deploy
      details are private (kept out of the repo on purpose). Publish the refresh when
      the release goes live, not before.
- [ ] **APT/RPM deploy hosts are live**: Rawhide's `release.yml` publishes `.deb`/
      `.rpm` to `apt.frontporchai.app` / `rpm.frontporchai.app`. Confirm those are
      configured on the server before tagging, or `publish-apt`/`publish-rpm` fail.

## Do the release

### 1. Build + verify the candidate (never touches `main`)

```bash
bash scripts/promote-rawhide-to-main.sh
```

It creates `release/promote-<date>-<rawhide-sha>` whose tree is Rawhide's + the
guarded files from `main`, then runs hard gates and stops:

- `.github/workflows/` (and `release.yml` specifically) **== Rawhide, verbatim**
- every guarded file **== main**
- the tree differs from Rawhide **only** in the guarded paths (nothing leaked)
- no conflict markers; every workflow YAML parses

Any failed gate aborts — nothing is pushed, `main` is untouched. It never pushes
or tags; that's the steps below.

### 2. PR so CI runs on the exact tree that will ship

```bash
git push -u origin release/promote-<…>
gh pr create --base main --head release/promote-<…> --title "Release: promote Rawhide" --fill
```

Eyeball the diff — the PR against `main` should show your feature work, and
`.github/workflows/**` should read as Rawhide's current files (e.g. the
`frontporchai.app` APT/RPM hosts). `README.md` / `docs/main.md` should be
unchanged from `main`.

### 3. Fast-forward `main`, then tag

```bash
git checkout main && git pull
git merge --ff-only release/promote-<…>     # ff-only: main only ever advances to the verified candidate
git push origin main

git tag vX.Y.Z && git push origin vX.Y.Z     # release.yml runs from the TAG's tree (now = Rawhide's)
```

## After a release

- Because `main` now equals Rawhide, **stop hand-editing workflows on `main`.** All
  CI edits happen on Rawhide and reach `main` only through the next promotion. That
  ends the error-prone "mirror the fix onto main's nightly.yml" habit that caused
  the drift.
- **`main` stays the default branch — deliberately.** Rawhide ships breaking changes
  constantly; it's for tip-of-the-sword testers, not general users. The default
  branch is what newcomers land on and what a bare `git clone` checks out, so it must
  stay `main` (stable). We do **not** make Rawhide the default just to simplify CI.
  The trade-off: the nightly `cron` runs from `main`'s copy of `nightly.yml`, so
  between releases `main`'s workflows can lag Rawhide's. Handle that with discipline,
  not a default-branch swap — make every workflow edit on Rawhide and let the
  promotion carry it to `main`; if a workflow fix is genuinely urgent for the *live*
  nightly before the next release, cherry-pick just that one workflow change onto
  `main` (never a broad hand-merge).

## If something looks wrong

The candidate is a throwaway branch; `main` is only touched at step 3 by an
`--ff-only` merge of an already-verified branch. To abandon a bad candidate:

```bash
git checkout Rawhide
git branch -D release/promote-<…>
git push origin --delete release/promote-<…>   # only if you already pushed it
```

Nothing on `main` changes until you deliberately fast-forward it.
