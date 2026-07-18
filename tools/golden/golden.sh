#!/usr/bin/env bash
#
# Run the Flutter widget pixel goldens in a Linux/amd64 container that mirrors
# the GitHub CI runner, so you can check or refresh goldens locally without a
# CI round-trip.
#
#   tools/golden/golden.sh check    # run goldens, fail on any pixel mismatch (default)
#   tools/golden/golden.sh update   # regenerate goldens, copy changed PNGs back into the repo
#
# Why a container: the widget goldens are @TestOn('linux') (they can't run on
# macOS at all) and are byte-sensitive to OS / FreeType / CPU arch. This image
# pins Ubuntu 24.04 (== ubuntu-latest) + Flutter 3.41.1 (== ci.yml) and runs as
# linux/amd64 (under Rosetta on Apple Silicon) to match the amd64 CI runners.
#
# Best-effort local parity: emulated rasterization should match CI, but the
# "Widget Golden Tests" job stays authoritative. If a freshly built image's
# `check` disagrees with CI, regenerate on CI via the update-goldens workflow.
#
# Requires Docker Desktop with amd64 emulation (Rosetta) enabled.
set -euo pipefail

MODE="${1:-check}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="fpai-golden:3.41.1"
PLATFORM="linux/amd64"

case "$MODE" in
  check)  FLUTTER_FLAGS="" ;;
  update) FLUTTER_FLAGS="--update-goldens" ;;
  *) echo "usage: $0 [check|update]" >&2; exit 2 ;;
esac

echo "==> Building $IMAGE ($PLATFORM) — cached after first run"
docker build --platform "$PLATFORM" -t "$IMAGE" "$REPO_ROOT/tools/golden"

# Copy the working tree into the container (excluding host-specific / heavy dirs)
# so `pub get` never rewrites the host's .dart_tool. In update mode, test/golden
# is also mounted read-write so refreshed PNGs land back in the repo.
RUN_ARGS=(
  --rm --platform "$PLATFORM"
  -v "$REPO_ROOT":/src:ro
  -v fpai-golden-pub-cache:/root/.pub-cache
)
if [ "$MODE" = "update" ]; then
  RUN_ARGS+=(-v "$REPO_ROOT/test/golden":/out)
fi

echo "==> Running goldens ($MODE) in container"
docker run "${RUN_ARGS[@]}" "$IMAGE" bash -lc '
  set -euo pipefail
  rsync -a \
    --exclude=.git --exclude=node_modules --exclude=web_ui/node_modules \
    --exclude=build --exclude=.dart_tool --exclude=ios --exclude=android \
    /src/ /build/
  cd /build
  flutter pub get
  flutter test --concurrency=1 --reporter expanded --tags golden '"$FLUTTER_FLAGS"'
  if [ "'"$MODE"'" = "update" ]; then
    rsync -a --include="*/" --include="*.png" --exclude="*" \
      /build/test/golden/ /out/
    echo "==> Refreshed PNGs copied back into test/golden/"
  fi
'

if [ "$MODE" = "update" ]; then
  echo "==> Changed goldens (review before committing):"
  git -C "$REPO_ROOT" status --short -- test/golden
fi
