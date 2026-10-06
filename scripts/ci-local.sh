#!/usr/bin/env bash
# Run the CI-parity Linux test jobs locally BEFORE pushing, inside the
# linux/amd64 `fpai-golden` Docker image (runs via Rosetta on Apple Silicon).
#
# Why this exists: the widget golden tests are Linux-gated — a green macOS
# `flutter test` does NOT execute them, which is exactly how a red-CI commit
# once reached Rawhide. This script mirrors the GitHub `golden` and `test`
# jobs byte-for-byte (same Flutter version as ci.yml, same flags) so pushes
# can be gated on the same evidence CI uses.
#
# The image is built from scripts/ci-golden.Dockerfile — when ci.yml bumps
# its flutter-version, rebuild with the matching FLUTTER_VERSION build-arg
# and update the IMG default below, or the gate false-fails on pub get.
#
# Usage:
#   scripts/ci-local.sh                 # golden suite only (the Linux-only gap)
#   scripts/ci-local.sh test            # full unit/integration suite on Linux
#   scripts/ci-local.sh all             # both
#   scripts/ci-local.sh update-goldens  # regenerate pixel goldens after an
#                                       # intentional UI change and sync the
#                                       # refreshed PNGs back into the repo
#
# Every mode, update-goldens included, first refuses a stale base: CI tests a
# PR merged with Rawhide's head, so a green run on a branch that is not on the
# current Rawhide proves nothing about the tree CI builds (a PR that merged
# after the rebase can break the merge while this tree still passes). The
# script fetches origin Rawhide and exits 3 unless origin/Rawhide's head is
# the merge base of HEAD. FPAI_ALLOW_STALE_BASE=1 skips the check, for
# offline use.
#
# The macOS working tree is rsynced into a named Docker volume (incremental,
# a few seconds) instead of being mounted read-write, so the container's
# Linux .dart_tool/build artifacts can never pollute the Mac checkout.

set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-golden}"
IMG="${FPAI_CI_IMAGE:-fpai-golden:3.47.0}"
VOL=fpai-ci-workspace
# The pub cache MUST persist across steps: every `docker run --rm` is a fresh
# container, and without this volume the cache `flutter pub get` builds is
# gone by the test step — which then re-resolves mid-compile and can see a
# half-fetched package (observed as "hooks.dart: No such file" while
# compiling objective_c's native-asset hook).
PUBVOL=fpai-pub-cache
PLATFORM=linux/amd64

# Stale-base refusal (see the header). Before any Docker work, for every mode.
if [ "${FPAI_ALLOW_STALE_BASE:-0}" = "1" ]; then
  echo "── skipping the Rawhide base check (FPAI_ALLOW_STALE_BASE=1)"
else
  echo "── checking this branch is on the current Rawhide…"
  if ! git fetch --quiet origin Rawhide; then
    echo "✗ Could not reach GitHub to check the current Rawhide. Connect and try again, or run with FPAI_ALLOW_STALE_BASE=1." >&2
    exit 3
  fi
  if [ "$(git merge-base HEAD origin/Rawhide)" != "$(git rev-parse origin/Rawhide)" ]; then
    echo "✗ This branch is not on the current Rawhide (another PR merged since your rebase). Rebase first, or run with FPAI_ALLOW_STALE_BASE=1." >&2
    exit 3
  fi
fi

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "✗ Docker image $IMG not found — build/pull it first." >&2
  exit 1
fi

docker volume create "$VOL" >/dev/null
docker volume create "$PUBVOL" >/dev/null

echo "── syncing sources into $VOL (incremental)…"
docker run --rm --platform "$PLATFORM" \
  -v "$PWD":/src:ro -v "$VOL":/build "$IMG" \
  bash -lc "rsync -a --delete \
    --exclude build/ --exclude .dart_tool/ --exclude .git/ \
    --exclude node_modules/ --exclude web_ui/node_modules/ \
    /src/ /build/"

run_in() {
  docker run --rm --platform "$PLATFORM" \
    -v "$VOL":/build -v "$PUBVOL":/root/.pub-cache -w /build "$IMG" \
    bash -lc "$1"
}

echo "── flutter pub get…"
run_in "flutter pub get"

case "$MODE" in
  golden)
    echo "── widget golden suite (CI parity)…"
    run_in "flutter test --concurrency=4 --tags golden"
    ;;
  test)
    echo "── full test suite on Linux (CI parity)…"
    # Must stay byte-identical to the `test` job's command in ci.yml — that is
    # this script's entire reason to exist. It said bare `flutter test` for a
    # long time, which is NOT what CI runs: no --exclude-tags golden (so the
    # pixel suite ran twice, once here and once in the golden step) and default
    # concurrency instead of CI's explicit flag. Fixed 2026-08-07 alongside the
    # concurrency=1 → 4 change.
    run_in "flutter test --concurrency=4 --exclude-tags golden"
    ;;
  all)
    echo "── widget golden suite (CI parity)…"
    run_in "flutter test --concurrency=4 --tags golden"
    echo "── full test suite on Linux (CI parity)…"
    # Must stay byte-identical to the `test` job's command in ci.yml — that is
    # this script's entire reason to exist. It said bare `flutter test` for a
    # long time, which is NOT what CI runs: no --exclude-tags golden (so the
    # pixel suite ran twice, once here and once in the golden step) and default
    # concurrency instead of CI's explicit flag. Fixed 2026-08-07 alongside the
    # concurrency=1 → 4 change.
    run_in "flutter test --concurrency=4 --exclude-tags golden"
    ;;
  update-goldens)
    echo "── regenerating pixel goldens…"
    run_in "flutter test --concurrency=4 --tags golden --update-goldens"
    echo "── syncing refreshed goldens back into the repo…"
    docker run --rm --platform "$PLATFORM" \
      -v "$PWD":/src -v "$VOL":/build "$IMG" \
      bash -lc "rsync -a /build/test/golden/ /src/test/golden/"
    echo "✓ goldens updated — review the PNG diffs before committing."
    ;;
  *)
    echo "Unknown mode: $MODE (use golden | test | all | update-goldens)" >&2
    exit 1
    ;;
esac

echo "✓ ci-local ($MODE) passed"
