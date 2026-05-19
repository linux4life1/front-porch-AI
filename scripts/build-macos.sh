#!/bin/bash
# Build Front Porch AI for macOS (Release), including:
#   - Rust embedding server
#   - Kokoro TTS (via PyInstaller)
#   - Piper TTS (via PyInstaller)
#
# Usage: ./scripts/build-macos.sh
#
# Note: This script can take 10-20+ minutes on first run because it installs
#       Python dependencies and runs PyInstaller for the local TTS engines.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$ROOT/build/macos/Build/Products/Release/FrontPorchAI.app"
EMBED_SRC="$ROOT/tools/embed_server"

echo "==> Installing Flutter dependencies..."
cd "$ROOT"
flutter pub get

echo "==> Building embedding server..."
if ! command -v cargo &>/dev/null; then
  echo "Error: Rust toolchain not found. Install it from https://rustup.rs/"
  exit 1
fi
cargo build --release --manifest-path "$EMBED_SRC/Cargo.toml"

echo "==> Building macOS app..."
flutter build macos

echo "==> Bundling embedding server into app..."
EMBED_DEST="$APP_BUNDLE/Contents/Resources/embed_server"
mkdir -p "$EMBED_DEST"
cp "$EMBED_SRC/target/release/embed_server" "$EMBED_DEST/"

echo "==> Bundling ML Engines (Kokoro TTS + Piper TTS)..."
echo "    This step can take several minutes and requires a working Python + pip environment."

# Check for Python/pip
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
  echo "Error: Python 3 is required to bundle Kokoro and Piper TTS."
  echo "Please install Python 3 and pip, then re-run this script."
  exit 1
fi

ML_DEST="$ROOT/build_tmp/ml_engines"
mkdir -p "$ML_DEST"

# Install required Python packages for PyInstaller
python3 -m pip install --upgrade pip || pip install --upgrade pip
python3 -m pip install pyinstaller kokoro-onnx soundfile piper_tts pathvalidate numpy onnxruntime || \
  pip install pyinstaller kokoro-onnx soundfile piper_tts pathvalidate numpy onnxruntime

# Build Kokoro TTS
echo "==> Building Kokoro TTS binary..."
pyinstaller kokoro_tts.py \
  --onedir \
  --name kokoro_tts \
  --collect-all kokoro_onnx \
  --collect-all soundfile \
  --collect-all phonemizer \
  --hidden-import kokoro_onnx \
  --hidden-import soundfile \
  --hidden-import numpy \
  --hidden-import onnxruntime \
  --distpath "$ML_DEST" \
  --workpath ./build_tmp/kokoro \
  --specpath ./build_tmp/kokoro \
  --clean \
  --exclude-module torch \
  --exclude-module torchvision \
  --exclude-module torchaudio \
  --noconfirm

echo "Kokoro built at: $ML_DEST/kokoro_tts/"

# Build Piper TTS
echo "==> Building Piper TTS binary..."
pyinstaller piper_entry.py \
  --onedir \
  --name piper \
  --collect-all piper \
  --hidden-import piper \
  --hidden-import pathvalidate \
  --hidden-import piper_phonemize \
  --hidden-import onnxruntime \
  --distpath "$ML_DEST" \
  --workpath ./build_tmp/piper \
  --specpath ./build_tmp/piper \
  --clean \
  --exclude-module torch \
  --exclude-module torchvision \
  --exclude-module torchaudio \
  --noconfirm

echo "Piper built at: $ML_DEST/piper/"

# Copy ML engines into the app bundle
ML_RESOURCES="$APP_BUNDLE/Contents/Resources/piper"
mkdir -p "$ML_RESOURCES"
cp -R "$ML_DEST/kokoro_tts" "$ML_RESOURCES/"
cp -R "$ML_DEST/piper" "$ML_RESOURCES/"

# Make binaries executable
chmod +x "$ML_RESOURCES/kokoro_tts/kokoro_tts" 2>/dev/null || true
chmod +x "$ML_RESOURCES/piper/piper" 2>/dev/null || true

echo "==> ML Engines bundled successfully into $ML_RESOURCES"

# Optional cleanup of temp build files
rm -rf ./build_tmp

echo "==> Done: $APP_BUNDLE"
echo ""
echo "Note: If you see errors during the PyInstaller steps, make sure you have"
echo "      a clean Python environment with the required packages installed."
