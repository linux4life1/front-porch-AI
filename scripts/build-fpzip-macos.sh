#!/usr/bin/env bash
# Build libfpzip.dylib for the pure-Dart Draw Things client's tensor decoder.
#
# Draw Things returns generated images as fpzip-compressed float tensors; the
# native (pure-Dart) DT client decodes them via dart:ffi against this library
# (lib/services/grpc/dt_native/dt_fpzip.dart). Without it, image *generation*
# fails with a clear libfpzip-missing error (no fallback exists — the
# sidecars are gone); test connection and model listing need no fpzip.
#
# Usage:  ./scripts/build-fpzip-macos.sh
# Output: tools/fpzip/libfpzip.dylib  (found automatically by `flutter run`)
#
# Requires: git, cmake (brew install cmake), Xcode command line tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/tools/fpzip"
WORK="$(mktemp -d /tmp/fpzip-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

FPZIP_REPO="https://github.com/LLNL/fpzip.git"
FPZIP_TAG="1.3.0"

echo "==> Cloning fpzip $FPZIP_TAG..."
git clone --depth 1 --branch "$FPZIP_TAG" "$FPZIP_REPO" "$WORK/fpzip"

echo "==> Building universal (arm64 + x86_64) shared library..."
# CMAKE_POLICY_VERSION_MINIMUM: fpzip 1.3.0's CMakeLists declares a
# cmake_minimum_required below 3.5, which CMake 4 (GitHub macOS runners)
# refuses outright. The override tells modern CMake to configure anyway;
# older CMakes ignore the unknown cache variable, so it is harmless there.
cmake -S "$WORK/fpzip" -B "$WORK/build" \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_UTILITIES=OFF \
  -DBUILD_TESTING=OFF \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" >/dev/null
cmake --build "$WORK/build" --config Release -j"$(sysctl -n hw.ncpu)"

mkdir -p "$DEST"
# CMake may emit a versioned dylib + symlink; resolve to the real file.
BUILT="$(find "$WORK/build" -name 'libfpzip*.dylib' -type f | head -1)"
if [ -z "$BUILT" ]; then
  echo "ERROR: build produced no libfpzip dylib" >&2
  exit 1
fi
cp "$BUILT" "$DEST/libfpzip.dylib"

echo "==> Verifying..."
file "$DEST/libfpzip.dylib"
echo "✓ Installed $DEST/libfpzip.dylib"
echo "  flutter run will pick it up automatically (see dt_fpzip.dart)."
