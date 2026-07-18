#!/usr/bin/env bash
#
# promote-rawhide-to-main.sh — safely cut a stable release by promoting Rawhide.
#
# WHY THIS EXISTS
#   A plain `git merge Rawhide` into main hand-resolves conflicts in the big CI
#   workflow files (release.yml / nightly.yml). That hand-resolution is what has
#   mangled release.yml before ("restore missing shim DMG step lost during merge
#   conflict resolution"). This script removes the human from that step: it makes
#   main's tree become Rawhide's tree WHOLESALE — so the workflows are Rawhide's
#   verbatim, byte-for-byte — while KEEPING a small, explicit set of stable-facing
#   files from main (the guard list). No conflict is ever hand-resolved.
#
# WHAT IT DOES / DOES NOT DO
#   - Builds a *candidate* branch off main whose tree == Rawhide, except GUARD_PATHS.
#   - Verifies the result with hard gates and STOPS.
#   - It NEVER touches `main`, NEVER pushes, NEVER tags. You do that after review.
#
# See docs/release-promotion.md for the full runbook and the finish steps.
#
set -euo pipefail

MAIN="${MAIN:-main}"
RAWHIDE="${RAWHIDE:-Rawhide}"
REMOTE="${REMOTE:-origin}"

# Stable-facing files that MUST keep main's version (never overwritten by Rawhide).
# Override by exporting GUARD_PATHS="README.md docs/main.md docs/other.md".
read -r -a GUARD_PATHS <<< "${GUARD_PATHS:-README.md docs/main.md}"

# Colors only when writing to a terminal (keep logs/pipes clean).
if [ -t 1 ]; then R=$'\033[31m'; G=$'\033[32m'; C=$'\033[36m'; Z=$'\033[0m'; else R=; G=; C=; Z=; fi
die() { printf '\n%s✗ %s%s\n' "$R" "$*" "$Z" >&2; exit 1; }
ok()  { printf '%s✓ %s%s\n' "$G" "$*" "$Z"; }
info(){ printf '%s• %s%s\n' "$C" "$*" "$Z"; }

# ── Preflight ────────────────────────────────────────────────────────────────
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository."

[ "$(git rev-parse --is-shallow-repository)" = "false" ] \
  || die "shallow clone — a merge here treats every file as a conflict. Run: git fetch --unshallow"

git diff --quiet && git diff --cached --quiet \
  || die "working tree is dirty. Commit or stash first (this script must start clean)."

info "fetching $REMOTE ..."
git fetch --quiet "$REMOTE" "$MAIN" "$RAWHIDE" || die "fetch failed for $REMOTE $MAIN/$RAWHIDE."

git rev-parse --verify --quiet "$REMOTE/$MAIN"    >/dev/null || die "$REMOTE/$MAIN not found."
git rev-parse --verify --quiet "$REMOTE/$RAWHIDE" >/dev/null || die "$REMOTE/$RAWHIDE not found."

MB="$(git merge-base "$REMOTE/$MAIN" "$REMOTE/$RAWHIDE" || true)"
[ -n "$MB" ] || die "no common ancestor between $MAIN and $RAWHIDE (shallow history?). Run: git fetch --unshallow"

RAW_SHA="$(git rev-parse --short "$REMOTE/$RAWHIDE")"
STAMP="$(date -u +%Y%m%d)"
CAND="${CANDIDATE_BRANCH:-release/promote-${STAMP}-${RAW_SHA}}"

git rev-parse --verify --quiet "$CAND" >/dev/null \
  && die "candidate branch '$CAND' already exists — delete it or set CANDIDATE_BRANCH."

info "main    = $REMOTE/$MAIN    ($(git rev-parse --short "$REMOTE/$MAIN"))"
info "rawhide = $REMOTE/$RAWHIDE ($RAW_SHA)"
info "guarded (kept from main): ${GUARD_PATHS[*]}"
info "candidate branch: $CAND"

# ── Build the candidate (tree := Rawhide, then restore guarded files) ─────────
git checkout -q -b "$CAND" "$REMOTE/$MAIN"

# Record Rawhide as a parent, but replace the whole tree with Rawhide's exactly
# (read-tree --reset handles adds, modifications AND deletions):
git merge -s ours --no-commit "$REMOTE/$RAWHIDE" >/dev/null
git read-tree -u --reset "$REMOTE/$RAWHIDE"

# Restore the guarded stable-facing files from main:
for p in "${GUARD_PATHS[@]}"; do
  if git cat-file -e "$REMOTE/$MAIN:$p" 2>/dev/null; then
    git checkout "$REMOTE/$MAIN" -- "$p"
  else
    info "guard '$p' does not exist on $MAIN — skipping."
  fi
done

git add -A
git commit -q -m "release: promote $RAWHIDE -> $MAIN (tree=$RAWHIDE @ $RAW_SHA; kept ${GUARD_PATHS[*]} from $MAIN)"
ok "candidate committed."

# ── Hard verification gates (any failure aborts the release) ──────────────────
echo; info "verifying ..."

# 1) Workflows must equal Rawhide's byte-for-byte (the files that mangle).
git diff --quiet "$REMOTE/$RAWHIDE" -- .github/workflows/ \
  || die "workflows differ from $RAWHIDE — they must be identical. Inspect: git diff $REMOTE/$RAWHIDE -- .github/workflows/"
ok ".github/workflows/ == $RAWHIDE (verbatim)"

# 2) release.yml specifically (the historical victim) equals Rawhide's.
git diff --quiet "$REMOTE/$RAWHIDE" -- .github/workflows/release.yml \
  || die "release.yml differs from $RAWHIDE."
ok "release.yml == $RAWHIDE"

# 3) Every guarded file equals main's (stable version preserved).
for p in "${GUARD_PATHS[@]}"; do
  git cat-file -e "$REMOTE/$MAIN:$p" 2>/dev/null || continue
  git diff --quiet "$REMOTE/$MAIN" -- "$p" || die "guarded file '$p' does not match $MAIN — the guard failed."
  ok "guard preserved: $p == $MAIN"
done

# 4) The tree differs from Rawhide ONLY in the guarded paths (nothing leaked).
#    (while-read, not mapfile — macOS ships bash 3.2.)
drift_count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  drift_count=$((drift_count + 1))
  keep=false; for p in "${GUARD_PATHS[@]}"; do [ "$f" = "$p" ] && keep=true; done
  $keep || die "unexpected file differs from $RAWHIDE: $f (only guarded paths may differ)."
done <<< "$(git diff --name-only "$REMOTE/$RAWHIDE")"
ok "tree == $RAWHIDE except the $drift_count guarded path(s)"

# 5) No conflict markers anywhere in code/workflows.
if git grep -nE '^(<<<<<<<|>>>>>>>) ' -- .github lib web_ui scripts >/dev/null 2>&1; then
  die "conflict markers found — aborting."
fi
ok "no conflict markers"

# 6) Every workflow YAML parses.
if command -v python3 >/dev/null 2>&1; then
  for f in .github/workflows/*.yml; do
    python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" \
      || die "YAML parse failed: $f"
  done
  ok "all .github/workflows/*.yml parse"
else
  info "python3 not found — skipped YAML lint (do it manually)."
fi

# ── Done — hand back to the human ────────────────────────────────────────────
cat <<EOF

$(ok "candidate '$CAND' is ready and verified.")

Nothing has been pushed and '$MAIN' is untouched. To finish the release:

  1. Push + open a PR so CI runs on the exact tree that will ship:
       git push -u $REMOTE $CAND
       gh pr create --base $MAIN --head $CAND --title "Release: promote $RAWHIDE" --fill

  2. When CI is green and you've eyeballed the release notes, fast-forward main:
       git checkout $MAIN && git pull
       git merge --ff-only $CAND
       git push $REMOTE $MAIN

  3. Tag to trigger the stable build (release.yml runs from the tag's tree):
       git tag vX.Y.Z && git push $REMOTE vX.Y.Z

  Before tagging, confirm the APT/RPM deploy hosts in release.yml
  (apt.frontporchai.app / rpm.frontporchai.app) are live on the server.
EOF
