#!/usr/bin/env bash
# Run the CI-parity Linux test jobs locally BEFORE pushing, inside the
# linux/amd64 `fpai-golden` Docker image (runs via Rosetta on Apple Silicon).
#
# Why this exists: the widget golden tests are Linux-gated — a green macOS
# `flutter test` does NOT execute them, which is exactly how a red-CI commit
# once reached Rawhide. This script mirrors the GitHub `golden` and `test`
# jobs byte-for-byte (same Flutter 3.41.1, same flags) so pushes can be gated
# on the same evidence CI uses.
#
# Usage:
#   scripts/ci-local.sh                 # golden suite only (the Linux-only gap)
#   scripts/ci-local.sh test            # full unit/integration suite on Linux
#   scripts/ci-local.sh all             # both
#   scripts/ci-local.sh update-goldens  # regenerate pixel goldens after an
#                                       # intentional UI change and sync the
#                                       # refreshed PNGs back into the repo
#
# The macOS working tree is rsynced into a named Docker volume (incremental,
# a few seconds) instead of being mounted read-write, so the container's
# Linux .dart_tool/build artifacts can never pollute the Mac checkout.

set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-golden}"
IMG="${FPAI_CI_IMAGE:-fpai-golden:3.41.1}"
VOL=fpai-ci-workspace
# The pub cache MUST persist across steps: every `docker run --rm` is a fresh
# container, and without this volume the cache `flutter pub get` builds is
# gone by the test step — which then re-resolves mid-compile and can see a
# half-fetched package (observed as "hooks.dart: No such file" while
# compiling objective_c's native-asset hook).
PUBVOL=fpai-pub-cache
PLATFORM=linux/amd64

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
    run_in "flutter test --concurrency=1 --tags golden"
    ;;
  test)
    echo "── full test suite on Linux (CI parity)…"
    run_in "flutter test"
    ;;
  all)
    echo "── widget golden suite (CI parity)…"
    run_in "flutter test --concurrency=1 --tags golden"
    echo "── full test suite on Linux (CI parity)…"
    run_in "flutter test"
    ;;
  update-goldens)
    echo "── regenerating pixel goldens…"
    run_in "flutter test --concurrency=1 --tags golden --update-goldens"
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
