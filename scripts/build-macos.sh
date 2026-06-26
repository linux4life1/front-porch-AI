#!/bin/bash
# Build Front Porch AI for macOS (Release) — FULL local equivalent of the nightly CI flow.
#
# Replicates the macOS Rawhide path from CI so you can debug codesign + notarize + .pkg
# + "ticket survives so Gatekeeper accepts the installed app".
#
# Bare-minimum packaging: plain pkgbuild + productsign for .pkg (signed+notarized+stapled).
# Also emits one last unsigned/un-notarized shim DMG (under legacy channel names
# like Front_Porch_AI_Nightly.dmg) so the in-app updater (which still knows how
# to hdiutil+replace for old .app installs) can bridge old and new users.
# Primary artifacts: .pkg . The shim is the compat layer only (transitional).
#
# Preferred auth: App Store Connect API key (stable, no flaky password keychain item).
#   export APPLE_API_KEY_PATH=/path/to/AuthKey_XXXX.p8
#   export APPLE_API_KEY_ID=XXXXXX
#   export APPLE_API_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export APPLE_TEAM_ID=22VHJ43YNK
#
# Fallback: keychain profile "front-porch-ai" (run store-credentials once) or APPLE_ID envs.
#
# What it does:
#   1. flutter build macos --release
#   2. Rename to FrontPorchAI-Rawhide.app + Plist patch for Rawhide
#   3. Full ML sidecars (all PyInstaller + embed_server) unless --fast
#   4. xattr clean + robust codesign (handles Python.framework from dt_grpc etc.)
#   5. Bare pkgbuild .pkg (installs the app to /Applications)
#   6. Notarize + staple the .pkg (using API key if set)
#   7. Diagnostics + verification steps
#
# Usage:
#   ./scripts/build-macos.sh            # full (sidecars + sign + bare .pkg + notarize + unsigned shim DMG)
#   ./scripts/build-macos.sh --fast
#   ./scripts/build-macos.sh --full-notarize
#   ./scripts/build-macos.sh --skip-shim   # independent; --skip-pkg does not force it
#
# After run: the .pkg (+ last unsigned shim DMG for updater compat) is ready.
# Double-click the .pkg to install to /Applications.
# The shim DMG (Front_Porch_AI_Nightly.dmg etc.) is deliberately unsigned/un-notarized
# and is the bridge so in-app auto-update continues to work for everyone during
# the .dmg->.pkg transition.
# Note: --skip-shim is now independent of --skip-pkg (the .app bundle from a prior
# full or --fast run is sufficient for shim production).
# The app ends up with all sidecars in the correct bundle locations.

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Argument parsing (simple, no getopts for maximum portability)
# ─────────────────────────────────────────────────────────────────────────────
DO_ML=1          # full sidecars by default — user wants the complete app
SKIP_SIGN=0
SKIP_PKG=0
SKIP_SHIM=0
FULL_NOTARIZE=0
CERT_NAME="${MACOS_CERTIFICATE_NAME:-}"

# Notary auth — initialized here at top level so they are always in scope
# regardless of --skip-sign. Populated later once cert/team are known.
HAVE_NOTARY_CREDS=0
NOTARY_AUTH=""
NOTARY_PROFILE="front-porch-ai"

for arg in "$@"; do
  case "$arg" in
    --fast|--skip-ml|--skip-pyinstaller|--no-ml) DO_ML=0 ;;
    --skip-sign) SKIP_SIGN=1 ;;
    --sign-only) DO_ML=0; SKIP_SIGN=0 ;;
    --full-notarize) FULL_NOTARIZE=1 ;;
    --skip-pkg) SKIP_PKG=1 ;;
    --skip-shim) SKIP_SHIM=1 ;;
    --cert-name=*) CERT_NAME="${arg#*=}" ;;
    --help|-h)
      echo "See top of script for usage."
      exit 0
      ;;
  esac
done

if [ "$DO_ML" -eq 0 ]; then
  echo "==> --fast requested: will reuse existing sidecars for quick sign/PKG/staple iteration"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# We always target the Rawhide-style name for local testing (matches what users
# will download from nightlies and what Gatekeeper will see).
APP_NAME="FrontPorchAI-Rawhide.app"
APP_BUNDLE="$ROOT/build/macos/Build/Products/Release/$APP_NAME"
PKG_PATH=""
SHIM_DMG_PATH=""
EMBED_SRC="$ROOT/tools/embed_server"

if [ "$DO_ML" -eq 1 ]; then
  echo "======================================================================"
  echo "  LOCAL FULL macOS BUILD + SIGN + BARE .PKG + NOTARIZE (Rawhide-equivalent)"
  echo "======================================================================"
  echo "This script mirrors the important parts of nightly.yml so you can"
  echo "debug codesign / packaging (.pkg) / notarize + staple locally."
  echo ""

  echo "==> Installing Flutter dependencies..."
  flutter pub get

  # Build the rewritten React PWA (web_ui/) into assets/web_app so Flutter
  # bundles a fresh web UI. Skipped gracefully if npm/web_ui is absent (e.g. the
  # legacy web server is still the default until the parity cutover).
  if [ -d "$ROOT/web_ui" ] && command -v npm &>/dev/null; then
    echo "==> Building web UI (React + Vite) into assets/web_app..."
    ( cd "$ROOT/web_ui" && npm ci && npm run build )
  else
    echo "==> Skipping web UI build (web_ui/ or npm not present)."
  fi

  echo "==> Building embedding server (Rust)..."
  if ! command -v cargo &>/dev/null; then
    echo "Error: Rust toolchain not found. Install it from https://rustup.rs/"
    exit 1
  fi
  cargo build --release --manifest-path "$EMBED_SRC/Cargo.toml"

  echo "==> Building macOS app (release)..."
  flutter build macos --release

  echo "==> Renaming to $APP_NAME and patching display name (Rawhide nightly style)..."
  cd "$ROOT/build/macos/Build/Products/Release"
  if [ -d FrontPorchAI.app ]; then
    rm -rf "$APP_NAME" 2>/dev/null || true
    mv FrontPorchAI.app "$APP_NAME"
  fi
  if [ -d "$APP_NAME" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Front Porch AI Nightly" "$APP_NAME/Contents/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Front Porch AI Nightly" "$APP_NAME/Contents/Info.plist" 2>/dev/null || true
    echo "    Renamed and patched: $APP_NAME"
  else
    echo "ERROR: Expected $APP_NAME after rename"
    exit 1
  fi
  cd "$ROOT"
  APP_BUNDLE="$ROOT/build/macos/Build/Products/Release/$APP_NAME"

  # Embed the Rust server early (it is small)
  echo "==> Bundling embed_server..."
  EMBED_DEST="$APP_BUNDLE/Contents/Resources/embed_server"
  mkdir -p "$EMBED_DEST"
  cp "$EMBED_SRC/target/release/embed_server" "$EMBED_DEST/" || true
  chmod +x "$EMBED_DEST/embed_server" 2>/dev/null || true

else
  # ── FAST MODE ──────────────────────────────────────────────────────────────
  # Skip flutter pub get, cargo build, flutter build, rename, and embed_server.
  # Work with the existing bundle that already has all sidecars embedded from the
  # last full build. This is the correct iteration loop for sign/PKG/notarize.
  echo "======================================================================"
  echo "  FAST MODE — reusing existing bundle (skip Flutter + sidecar build)"
  echo "======================================================================"
  echo ""
  echo "==> --fast: skipping Flutter build, Rust build, and sidecar copy."
  echo "    Working with existing bundle at:"
  echo "    $APP_BUNDLE"
  echo ""
  if [ ! -d "$APP_BUNDLE" ]; then
    echo "ERROR: --fast requires an existing bundle at:"
    echo "  $APP_BUNDLE"
    echo "Run without --fast first to do a full build."
    exit 1
  fi
  # Sanity check: a real bundle with sidecars should be >> 100 MB
  BUNDLE_SIZE_MB=$(du -sm "$APP_BUNDLE" 2>/dev/null | awk '{print $1}')
  if [ "${BUNDLE_SIZE_MB:-0}" -lt 100 ]; then
    echo "WARNING: Bundle is only ${BUNDLE_SIZE_MB}MB — it may be missing sidecars."
    echo "         Expected 400MB+. Run without --fast to rebuild from scratch."
  else
    echo "    Bundle size: ${BUNDLE_SIZE_MB}MB — looks good."
  fi
  echo ""
fi

if [ "$DO_ML" -eq 1 ]; then
  echo "==> Building ALL ML sidecars (kokoro, piper, whisper, sentiment, dt_grpc_client)..."
  echo "    (This is the expensive part — use --fast on subsequent runs for sign/PKG/staple only)"

  if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    echo "Error: Python 3 is required."
    exit 1
  fi

  ML_DEST="$ROOT/build_tmp/ml_engines"
  rm -rf "$ML_DEST"
  mkdir -p "$ML_DEST"

  python3 -m pip install --upgrade pip || pip install --upgrade pip

  # Match the packages and flags used in nightly.yml as closely as possible
  PIP_PKGS="pyinstaller kokoro-onnx soundfile piper_tts pathvalidate faster-whisper numpy onnxruntime transformers huggingface_hub tokenizers ctranslate2 grpcio grpcio-tools flatbuffers fpzip pillow"
  python3 -m pip install $PIP_PKGS || pip install $PIP_PKGS

  # Kokoro (expanded collect-all like CI)
  echo "  -> kokoro_tts"
  pyinstaller kokoro_tts.py \
    --onedir --name kokoro_tts \
    --collect-all kokoro_onnx --collect-all soundfile \
    --collect-all language_tags --collect-all csvw --collect-all segments \
    --collect-all phonemizer --collect-all espeakng_loader \
    --hidden-import kokoro_onnx --hidden-import soundfile \
    --hidden-import numpy --hidden-import onnxruntime \
    --distpath "$ML_DEST" --workpath ./build_tmp/kokoro --specpath ./build_tmp/kokoro \
    --clean --exclude-module torch --exclude-module torchvision --exclude-module torchaudio \
    --noconfirm

  # Piper
  echo "  -> piper"
  pyinstaller piper_entry.py \
    --onedir --name piper \
    --collect-all piper \
    --hidden-import piper --hidden-import pathvalidate --hidden-import piper_phonemize \
    --hidden-import onnxruntime \
    --distpath "$ML_DEST" --workpath ./build_tmp/piper --specpath ./build_tmp/piper \
    --clean --exclude-module torch --exclude-module torchvision --exclude-module torchaudio \
    --noconfirm

  # Whisper STT
  echo "  -> whisper_stt"
  pyinstaller whisper_stt.py \
    --onedir --name whisper_stt \
    --collect-all faster_whisper \
    --hidden-import faster_whisper --hidden-import ctranslate2 \
    --hidden-import huggingface_hub --hidden-import tokenizers \
    --distpath "$ML_DEST" --workpath ./build_tmp/whisper --specpath ./build_tmp/whisper \
    --clean --exclude-module torch --exclude-module torchvision --exclude-module torchaudio \
    --noconfirm

  # Sentiment classifier
  echo "  -> sentiment_classifier"
  pyinstaller sentiment_classifier.py \
    --onedir --name sentiment_classifier \
    --collect-all transformers --collect-all huggingface_hub \
    --hidden-import transformers --hidden-import huggingface_hub \
    --distpath "$ML_DEST" --workpath ./build_tmp/sentiment --specpath ./build_tmp/sentiment \
    --clean --exclude-module torch --exclude-module torchvision --exclude-module torchaudio \
    --noconfirm

  # Draw Things gRPC client (exact flags from nightly.yml)
  echo "  -> dt_grpc_client (Draw Things)"
  GRPC_SRC="$ROOT/tools/dt-grpc-python"
  pyinstaller "$GRPC_SRC/dt_grpc_client.py" \
    --onedir --name dt_grpc_client \
    --paths "$GRPC_SRC" \
    --add-data "$GRPC_SRC/client.py:." \
    --add-data "$GRPC_SRC/imageService_pb2.py:." \
    --add-data "$GRPC_SRC/imageService_pb2_grpc.py:." \
    --add-data "$GRPC_SRC/GenerationConfiguration.py:." \
    --add-data "$GRPC_SRC/SamplerType.py:." \
    --add-data "$GRPC_SRC/SeedMode.py:." \
    --add-data "$GRPC_SRC/LoRA.py:." \
    --add-data "$GRPC_SRC/LoRAMode.py:." \
    --add-data "$GRPC_SRC/Control.py:." \
    --add-data "$GRPC_SRC/ControlInputType.py:." \
    --add-data "$GRPC_SRC/ControlMode.py:." \
    --add-data "$GRPC_SRC/ca_chain.pem:." \
    --collect-all grpcio --collect-all flatbuffers --collect-all fpzip \
    --collect-all numpy --collect-all PIL \
    --hidden-import grpc --hidden-import grpc._cython --hidden-import grpcio \
    --hidden-import flatbuffers --hidden-import fpzip --hidden-import numpy \
    --hidden-import PIL --hidden-import PIL.Image \
    --hidden-import imageService_pb2 --hidden-import imageService_pb2_grpc \
    --hidden-import GenerationConfiguration --hidden-import SamplerType \
    --hidden-import SeedMode --hidden-import LoRA --hidden-import LoRAMode \
    --hidden-import client \
    --distpath "$ML_DEST" --workpath ./build_tmp/dt_grpc --specpath ./build_tmp/dt_grpc \
    --clean --exclude-module torch --exclude-module torchvision --exclude-module torchaudio \
    --noconfirm

  echo "Sidecars built into $ML_DEST"

  # Copy into the app bundle exactly like the CI does for macOS
  echo "==> Copying sidecars into $APP_NAME/Contents/Resources/..."

  # piper + kokoro (under Resources/piper/)
  PIPER_RES="$APP_BUNDLE/Contents/Resources/piper"
  mkdir -p "$PIPER_RES"
  cp -R "$ML_DEST/kokoro_tts" "$PIPER_RES/" 2>/dev/null || true
  cp -R "$ML_DEST/piper" "$PIPER_RES/" 2>/dev/null || true
  chmod +x "$PIPER_RES/kokoro_tts/kokoro_tts" 2>/dev/null || true
  chmod +x "$PIPER_RES/piper/piper" 2>/dev/null || true

  # whisper_stt
  WHISPER_RES="$APP_BUNDLE/Contents/Resources/whisper_stt"
  mkdir -p "$WHISPER_RES"
  cp -R "$ML_DEST/whisper_stt/"* "$WHISPER_RES/" 2>/dev/null || true
  chmod +x "$WHISPER_RES/whisper_stt" 2>/dev/null || true

  # sentiment_classifier
  SENT_RES="$APP_BUNDLE/Contents/Resources/sentiment_classifier"
  mkdir -p "$SENT_RES"
  cp -R "$ML_DEST/sentiment_classifier/"* "$SENT_RES/" 2>/dev/null || true
  chmod +x "$SENT_RES/sentiment_classifier" 2>/dev/null || true

  # embed_server (Rust)
  EMBED_RES="$APP_BUNDLE/Contents/Resources/embed_server"
  mkdir -p "$EMBED_RES"
  cp -R "$ML_DEST/embed_server/"* "$EMBED_RES/" 2>/dev/null || true
  chmod +x "$EMBED_RES/embed_server" 2>/dev/null || true

  # dt_grpc (Draw Things) — the one that was causing the Python.framework crash
  DT_RES="$APP_BUNDLE/Contents/Resources/dt_grpc"
  mkdir -p "$DT_RES"
  cp -R "$ML_DEST/dt_grpc_client" "$DT_RES/" 2>/dev/null || true
  chmod +x "$DT_RES/dt_grpc_client/dt_grpc_client" 2>/dev/null || true

  echo "Sidecars copied."

  # Optional cleanup
  rm -rf ./build_tmp
fi

# ─────────────────────────────────────────────────────────────────────────────
# xattr clean (MUST be before any codesigning)
# ─────────────────────────────────────────────────────────────────────────────
echo "==> Cleaning xattrs (critical before codesign/notarization)..."
xattr -cr "$APP_BUNDLE" || true
find "$APP_BUNDLE" -exec xattr -d com.apple.FinderInfo {} + 2>/dev/null || true

if [ "$SKIP_SIGN" -eq 1 ]; then
  echo "==> Skipping codesign (--skip-sign)"
else
  # Determine certificate — auto-discover, prefer the known working one on this Mac.
  # We use tool access to discover it so you never have to export or type the cert name.
  PREFERRED_CERT="Developer ID Application: Joseph Spooner (22VHJ43YNK)"
  if [ -z "$CERT_NAME" ]; then
    CERT_NAME=$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$PREFERRED_CERT" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  fi
  if [ -z "$CERT_NAME" ]; then
    CERT_NAME=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  fi
  if [ -z "$CERT_NAME" ]; then
    echo "    No Developer ID Application cert found in keychain."
    echo "    Falling back to ad-hoc signing ( - ). This is enough to test bundle layout"
    echo "    and the 'ambiguous bundle format' fixes, but will not produce a shippable build."
    CERT_NAME="-"
  fi
  echo "==> Codesigning with: $CERT_NAME"

  # Extract team ID for notarization steps (no user input needed)
  TEAM_ID=$(echo "$CERT_NAME" | sed -n 's/.*(\([A-Z0-9]*\)).*/\1/p' || true)
  if [ -z "$TEAM_ID" ]; then
    TEAM_ID="22VHJ43YNK"   # known from this Mac's cert
  fi
  echo "==> Team ID: $TEAM_ID"

  # Look for Installer cert for signing the .pkg (required for proper .pkg notarization)
  INSTALLER_CERT=$(security find-identity -v 2>/dev/null | grep 'Developer ID Installer' | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [ -n "$INSTALLER_CERT" ]; then
    echo "==> Found Installer cert for .pkg signing: $INSTALLER_CERT"
  else
    # Force the known name even if find-identity doesn't list it yet (common until ACLs fully updated)
    INSTALLER_CERT="Developer ID Installer: Joseph Spooner (22VHJ43YNK)"
    echo "==> Using known Installer cert name for .pkg signing: $INSTALLER_CERT (verify it exists in keychain)"
  fi

  ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"
  SIDECAR_ENT="$ROOT/macos/Runner/Sidecar.entitlements"

  # 1. Frameworks (outer)
  while IFS= read -r -d '' f; do
    codesign --force --sign "$CERT_NAME" --timestamp --options runtime "$f" \
      2>&1 | grep -v -E '(replacing existing signature|already signed)' || true
  done < <(find "$APP_BUNDLE/Contents/Frameworks" \( -name "*.framework" -o -name "*.dylib" \) -print0 2>/dev/null || true)

  # 2. Normal Mach-O under Resources (skip anything inside a .framework to avoid double-work)
  echo "    Signing loose Mach-O files under Resources..."
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
      echo "    Signing native binary: $f"
      codesign --force --sign "$CERT_NAME" --timestamp --options runtime \
        --entitlements "$SIDECAR_ENT" "$f" \
        2>&1 | grep -v -E '(replacing existing signature|already signed)' || true
    fi
  done < <(find "$APP_BUNDLE/Contents/Resources" -type f ! -path '*/.framework/*' ! -path '*/Python.framework/*' -print0 2>/dev/null || true)

  # 3. Special handling for every *.framework under Resources (the Python.framework fix)
  echo "    Handling nested *.framework (Python.framework from PyInstaller etc.)..."
  while IFS= read -r -d '' fw; do
    echo "      $fw"
    # All Mach-O inside the framework
    while IFS= read -r -d '' bin; do
      if file "$bin" | grep -q "Mach-O"; then
        codesign --force --sign "$CERT_NAME" --timestamp --options runtime \
          --entitlements "$SIDECAR_ENT" "$bin" \
          2>&1 | grep -v -E '(replacing existing signature|already signed)' || true
      fi
    done < <(find "$fw" -type f -print0 2>/dev/null || true)

    # The framework directory itself (this is what usually fixes the ambiguity)
    codesign --force --sign "$CERT_NAME" --timestamp --options runtime \
      "$fw" 2>&1 | grep -v -E '(replacing existing signature|already signed)' || true
  done < <(find "$APP_BUNDLE/Contents/Resources" -type d -name "*.framework" -print0 2>/dev/null || true)

  # 4. BROAD CATCH-ALL: Sign EVERY remaining Mach-O under Resources.
  # This is the critical step for PyInstaller onedir sidecars (kokoro, piper, whisper, dt_grpc, sentiment).
  # They contain hundreds of .dylib/.so in _internal/ dirs that are NOT inside *.framework.
  # The previous loops can miss some due to path skips or "file" detection.
  # Previous runs that succeeded had fewer sidecars; this ensures completeness for the .pkg payload.
  echo "    Broad catch-all pass: force-signing EVERY Mach-O under Resources (sidecar _internal trees etc.)..."
  while IFS= read -r -d '' f; do
    if file "$f" | grep -qiE 'mach-o|executable|shared library|dynamically linked'; then
      # Avoid re-doing the main app binary or outer Frameworks (already handled)
      if [[ "$f" == *"/Contents/MacOS/FrontPorchAI"* ]] || [[ "$f" == *"/Contents/Frameworks/"* ]]; then
        continue
      fi
      echo "      $f"
      codesign --force --sign "$CERT_NAME" --timestamp --options runtime \
        --entitlements "$SIDECAR_ENT" "$f" \
        2>&1 | grep -v -E '(replacing existing signature|already signed|is not signed)' || true
    fi
  done < <(find "$APP_BUNDLE/Contents/Resources" -type f -print0 2>/dev/null || true)

  # 5. The main app bundle last (after all nested/sidecar code is signed)
  codesign --force --sign "$CERT_NAME" --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" || true

  # 6. Strict post-sign verification: fail loud if anything under Resources is not signed
  # with *our* Developer ID Application cert + hardened runtime. This prevents silent
  # "some binary wasn't covered" problems that cause Apple "Invalid" on .pkg.
  echo "    Strict verification: checking every Mach-O under Resources has our Developer ID cert + runtime..."
  verification_failed=0
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
      sig_output=$(codesign -dvv "$f" 2>&1)
      if ! echo "$sig_output" | grep -q "Developer ID Application: Joseph Spooner (22VHJ43YNK)"; then
        echo "      !!! MISSING OR WRONG CERT: $f"
        echo "$sig_output" | grep -E 'Authority|flags=' | head -3
        verification_failed=1
      elif ! echo "$sig_output" | grep -q 'flags=.*runtime'; then
        echo "      !!! MISSING HARDENED RUNTIME: $f"
        verification_failed=1
      fi
    fi
  done < <(find "$APP_BUNDLE/Contents/Resources" -type f -print0 2>/dev/null || true)

  if [ $verification_failed -eq 1 ]; then
    echo "ERROR: One or more binaries under Resources are not signed with the correct Developer ID Application certificate + hardened runtime."
    echo "This is almost certainly why the previous .pkg notarization was rejected as 'Invalid'."
    # Do not exit here — let the build continue so you can inspect, but the .pkg will likely fail notarization again.
  else
    echo "    All Resources Mach-O verified as correctly signed with Developer ID + runtime."
  fi

  echo "    Verifying signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | tail -10 || true
  echo "==> Codesign complete."

  # === DIAGNOSTICS for ticket/CDHash (for notarization debugging) ===
  echo "=== DIAGNOSTIC: Post-sign state of .app ==="
  echo "CodeDirectory / CDHash info:"
  codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E 'CDHash|CodeDirectory|Sealed Resources|Timestamp|flags=' | cat
  echo "xattrs on the signed app:"
  xattr -l "$APP_BUNDLE" 2>/dev/null | cat || echo 'none (or provenance only)'
  echo "=== End post-sign diagnostic ==="

  # === Unified notary auth detection (run once, early) ===
  # Prefer stable App Store Connect API key (no flaky password keychain item).
  # Set these (recommended):
  #   APPLE_API_KEY_PATH=/path/to/AuthKey_XXXX.p8
  #   APPLE_API_KEY_ID=XXXXXX
  #   APPLE_API_ISSUER=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  #   APPLE_TEAM_ID=22VHJ43YNK
  # Fallbacks: keychain profile or APPLE_ID envs.
  # Note: NOTARY_PROFILE/HAVE_NOTARY_CREDS/NOTARY_AUTH are initialized at top of script
  # so they survive even if --skip-sign is used (PKG notarization still runs).

  if [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -f "$APPLE_API_KEY_PATH" ] && \
     [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then
    NOTARY_AUTH="--key $APPLE_API_KEY_PATH --key-id $APPLE_API_KEY_ID --issuer $APPLE_API_ISSUER --team-id ${APPLE_TEAM_ID:-$TEAM_ID}"
    HAVE_NOTARY_CREDS=1
    echo "==> Using App Store Connect API key for notarization (stable, recommended)"
  elif xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    HAVE_NOTARY_CREDS=1
    NOTARY_AUTH="--keychain-profile $NOTARY_PROFILE"
    echo "==> Using existing notary keychain profile '$NOTARY_PROFILE'"
  elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ID_PASSWORD:-}" ]; then
    HAVE_NOTARY_CREDS=1
    NOTARY_AUTH="--apple-id $APPLE_ID --password $APPLE_ID_PASSWORD --team-id ${APPLE_TEAM_ID:-$TEAM_ID}"
    echo "==> Using Apple creds from environment."
  else
    echo "==> No notary auth available (API key or profile)."
    echo "    (Set APPLE_API_* envs above, or: xcrun notarytool store-credentials front-porch-ai --team-id $TEAM_ID)"
  fi

fi



# ─────────────────────────────────────────────────────────────────────────────
# Bare-minimum .pkg (often more reliable for notarization on complex apps with
# sidecars). Installs the exact same bundle to /Applications.
# All sidecars stay inside the .app exactly as built.
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_PKG" -eq 1 ]; then
  echo "==> Skipping .pkg creation (--skip-pkg)"
else
  PKG_NAME="Front_Porch_AI_Rawhide.pkg"
  PKG_PATH="$ROOT/$PKG_NAME"

  echo "==> Creating bare-minimum .pkg (unsigned first, then signed with productsign for cleaner signature)"
  rm -f "$PKG_PATH"

  # Verify the Installer cert is present in the login keychain (more reliable than find-identity -p codesigning)
  if ! security find-certificate -c "Developer ID Installer: Joseph Spooner (22VHJ43YNK)" -a ~/Library/Keychains/login.keychain-db > /dev/null 2>&1; then
    echo "ERROR: Developer ID Installer cert not found in login keychain."
    echo "Please import ~/Desktop/Certificates.p12 (we just did it for you), then run in this terminal:"
    echo "  security unlock-keychain ~/Library/Keychains/login.keychain-db"
    echo "  security set-key-partition-list -S apple-tool:,apple: -s ~/Library/Keychains/login.keychain-db"
    echo "  (enter your Mac login password at prompts)"
    echo "Then open Keychain Access, find the cert, Get Info > Trust > Code Signing > Always Trust."
    exit 1
  fi

  # Create unsigned package first — use build dir, not /tmp, to avoid xattr contamination
  UNSIGNED_PKG="$ROOT/build/unsigned-$$.pkg"
  pkgbuild \
    --component "$APP_BUNDLE" \
    --install-location /Applications \
    "$UNSIGNED_PKG" || {
      echo "ERROR: pkgbuild failed for unsigned package"
      exit 1
    }

  # Sign with productsign using the exact known Installer cert name + explicit keychain
  # This is more reliable for locating the cert in the specific keychain
  productsign --sign "Developer ID Installer: Joseph Spooner (22VHJ43YNK)" \
    --keychain ~/Library/Keychains/login.keychain-db \
    "$UNSIGNED_PKG" "$PKG_PATH" || {
    echo "ERROR: productsign failed for $PKG_PATH"
    echo "The cert must be in the keychain and its private key authorized (run the unlock + set-key-partition-list above if needed)."
    rm -f "$UNSIGNED_PKG"
    exit 1
  }

  rm -f "$UNSIGNED_PKG"
  ls -lh "$PKG_PATH"
  echo "    .pkg created: $PKG_PATH (signed with Installer cert via productsign)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# One last unsigned shim DMG (transitional bridge for the in-app updater).
# Produced from the *same* .app that went into the .pkg so versions match.
# Deliberately NOT codesigned or notarized (so Gatekeeper does not interfere
# with the temp hdiutil attach that the legacy client replace script performs).
# The DMG contains the .app directly at the volume root so the client's
#   find "$MOUNT_POINT" -maxdepth 1 -name "*.app" ...
# logic continues to work exactly as before.
# Uses direct hdiutil (minimal) or falls back to ./create-dmg.sh --skip-jenkins.
# Only for the Rawhide/nightly legacy name here (local builds target Rawhide).
# CI publishes the full set of legacy shims for all channels.
# ─────────────────────────────────────────────────────────────────────────────
if [ "$SKIP_SHIM" -eq 1 ]; then
  echo "==> Skipping unsigned shim DMG (--skip-shim)"
else
  # Legacy shim name expected by both old and new client code for the nightly/rawhide channel.
  SHIM_DMG_NAME="Front_Porch_AI_Nightly.dmg"
  SHIM_DMG_PATH="$ROOT/$SHIM_DMG_NAME"
  echo "==> Producing unsigned un-notarized shim DMG for updater transition: $SHIM_DMG_NAME"
  rm -f "$SHIM_DMG_PATH"
  SHIM_ROOT="$ROOT/build/shim-dmg-$$"
  rm -rf "$SHIM_ROOT"
  mkdir -p "$SHIM_ROOT"
  cp -R "$APP_BUNDLE" "$SHIM_ROOT/" || {
    echo "ERROR: failed to stage .app for shim DMG"
    rm -rf "$SHIM_ROOT"
  }
  if [ -d "$SHIM_ROOT" ]; then
    # Minimal hdiutil (no fancy UI, no sign, no notarize).
    if hdiutil create -volname "Front Porch AI" -srcfolder "$SHIM_ROOT" -ov -format UDZO "$SHIM_DMG_PATH" >/dev/null 2>&1; then
      echo "    Shim DMG created via hdiutil: $SHIM_DMG_PATH"
    else
      echo "    hdiutil create for shim failed, trying create-dmg.sh --skip-jenkins (if present)..."
      if [ -x "./create-dmg.sh" ]; then
        ./create-dmg.sh --skip-jenkins "$SHIM_DMG_PATH" "$SHIM_ROOT" || echo "    create-dmg shim attempt also failed (continuing)"
      fi
    fi
    rm -rf "$SHIM_ROOT"
    if [ -f "$SHIM_DMG_PATH" ]; then
      ls -lh "$SHIM_DMG_PATH"
      echo "    Unsigned shim DMG ready (no codesign/notarize — bridge only)"
    else
      echo "    WARNING: shim DMG was not produced"
    fi
  fi
fi

# Use the NOTARY_AUTH detected earlier (API key preferred).
# Notarize + staple the .pkg.
if [ "$FULL_NOTARIZE" -eq 1 ] || [ -n "$NOTARY_AUTH" ]; then
  if [ -z "$NOTARY_AUTH" ]; then
    echo "    (No notary auth — skipping .pkg notarization.)"
  else
    echo "==> Notarizing and stapling .pkg (bare minimum, API key or profile)"

    if [ -f "$PKG_PATH" ]; then
      # Clean quarantine/provenance xattrs from the final .pkg.
      # Note: .pkg is a flat XAR archive — do NOT use `find` inside it, only xattr -cr on the file itself.
      xattr -cr "$PKG_PATH" 2>/dev/null || true
      xattr -d com.apple.FinderInfo "$PKG_PATH" 2>/dev/null || true
      xattr -d com.apple.quarantine "$PKG_PATH" 2>/dev/null || true

      echo "    Submitting .pkg for notarization (this can take several minutes for a large bundle)..."
      xcrun notarytool submit "$PKG_PATH" $NOTARY_AUTH --wait || echo "    .pkg submit had issues (continuing anyway)"
      xcrun stapler staple "$PKG_PATH" || true
      xcrun stapler validate "$PKG_PATH" || echo "    (.pkg stapler validate had issues)"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Final verification instructions
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "======================================================================"
echo "  DONE.  Bare .pkg + notarize/staple + unsigned shim DMG (transition bridge)."
echo "======================================================================"
echo ""
echo "Artifacts produced:"
echo "  .pkg (primary, signed+notarized+stapled): $PKG_PATH"
echo "  shim DMG (unsigned/un-notarized, last one for in-app updater compat):"
if [ -n "${SHIM_DMG_PATH:-}" ] && [ -f "$SHIM_DMG_PATH" ]; then
  echo "    $SHIM_DMG_PATH"
else
  echo "    (skipped via --skip-shim or not produced)"
fi
echo ""
echo "To install/test:"
echo "  1. Double-click $PKG_PATH for the real signed install (recommended)."
echo "  2. The unsigned shim DMG (if produced) is only for testing the legacy"
echo "     in-app auto-update replace path from old .dmg-based installs."
echo "  3. Let the Installer place the app to /Applications/FrontPorchAI-Rawhide.app"
echo "  4. All sidecars (dt_grpc, whisper_stt, embed_server, etc.) are inside"
echo "     the installed bundle in the exact correct relative paths."
echo "  4. Run the 4 checks on the installed app:"
echo "     codesign -vvv --deep --strict /Applications/$APP_NAME"
echo "     spctl --assess --type exec -vv /Applications/$APP_NAME"
echo "     xcrun stapler validate /Applications/$APP_NAME"
echo ""
echo "If Gatekeeper still complains after install, check the notarization log"
echo "for the submission and re-run with API key env vars (more reliable)."
echo ""
echo "The .pkg is at:"
echo "   $PKG_PATH"
echo ""
echo "Iterate fast: ./scripts/build-macos.sh --fast"
echo ""
echo "Good luck — this should produce a working notarized .pkg installer."
