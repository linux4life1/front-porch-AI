# Sidecar Retirement Plan (the "sidecar-ectomy")

**Status: COMPLETE (2026-07-18).** Every Python/PyInstaller sidecar is gone
— sources deleted, Dart fallback paths removed, nightly build steps
removed. See the Removal record at the bottom for what shipped and the two
deliberate exceptions. The phase records below are kept as history.
Maintainer-approved direction was: eliminate every Python/PyInstaller
sidecar in favor of in-process Dart + `dart:ffi` against plain native
libraries.

## Why

The PyInstaller sidecars are the app's most ship-fragile components: frozen
Python with its own dependency graph (hidden-import landmines — see the
2026-07-15 protobuf freeze bug that silently broke Draw Things in every signed
release), hardened-runtime entitlement exceptions (`Sidecar.entitlements`),
huge bundles, and stdin/stdout JSON protocols whose failures are dead
processes instead of catchable exceptions. Plain dylibs sign/notarize like the
Flutter engine itself.

## Inventory & target architecture

| Sidecar | What it does | Replacement | Phase |
|---|---|---|---|
| `dt_grpc_client` (Python) | Draw Things gRPC | Pure-Dart client (`lib/services/grpc/dt_native/`) + tiny fpzip FFI | **1 — shipped, soaking** |
| `sentiment_classifier` (Python) | emotion/expression ONNX classifier | in-process ONNX via `onnxruntime_v2` + Dart WordPiece tokenizer | **2 — shipped, soaking** |
| `whisper_stt` (Python, faster-whisper/CT2) | STT | sherpa-onnx via the official `sherpa_onnx` Dart package | **3 — shipped, soaking** |
| `kokoro_tts` (Python) | Kokoro TTS | sherpa-onnx (Kokoro is first-class; bundles espeak-ng G2P) | **4a — shipped, soaking** |
| `piper` (PyInstaller wrap of `python -m piper`) | Piper TTS | sherpa-onnx (vits-piper) | **4b — shipped, soaking** |
| `embed_server` (Rust, already non-Python) | RAG embeddings | optional: fold into in-process ort; low priority — it is stable | 5 (optional) |

## The two upgrade surfaces

### 1. Binaries — free ride
Sidecar executables live **inside the app bundle**; upgrades replace the
bundle wholesale, so removing a sidecar needs zero migration code. The staged
pattern (below) keeps *downgrades* safe during each soak window.

### 2. Downloaded models — the real migration surface
Models live in the user data dir (`StorageService.rootPath`), which upgrades
never touch. Per engine:

| Models on disk | Fate on migration |
|---|---|
| Draw Things | none — nothing to migrate |
| RAG embedding ONNX (~270 MB) | reusable as-is (ONNX is engine-agnostic) |
| Expression/sentiment ONNX | reusable as-is |
| Kokoro (`kokoro-v1.0.onnx` ~310 MB + `voices-v1.0.bin`) | **NOT reusable** (corrected 2026-07-16: sherpa needs its own export + voices.bin format) — one-time ~160 MB bundle re-download |
| Whisper (CTranslate2 format, 75 MB–1.5 GB) | **NOT reusable** — sherpa/whisper.cpp use a different export; one-time re-download, must be explicit UX |
| Piper voices (`.onnx` + `.json`) | **NOT reusable** (corrected 2026-07-16: sherpa needs its vits-piper re-exports) — per-voice ~60–100 MB re-download, 404 → legacy binary |

## The playbook (every phase MUST follow this)

1. **Fallback-first rollout.** Ship native-first with the sidecar still
   bundled and an automatic per-call fallback + loud log lines
   (`[DT-Native]`-style) + a `FP_<X>_SIDECAR=1`-style env rollback lever.
   Remove the sidecar (and its build-workflow steps, and its
   `Sidecar.entitlements` need) only after a release of soak.
2. **Cross-language golden verification.** Pin the new implementation to the
   exact bytes/outputs of the Python stack it replaces, with goldens generated
   FROM that Python stack (precedent: `test/services/grpc/dt_native_test.dart`
   — proto bytes, FlatBuffer field-by-field, tensor bytes, fpzip floats).
   Tests must skip (not fail) when an optional native lib is absent so CI
   stays green.
3. **Version-stamped migration pass on first launch** after upgrade: detect
   old artifacts → reuse what's valid → queue downloads for what's missing →
   only then treat anything as obsolete.
4. **Never silently delete user downloads.** Obsolete model formats are
   offered in a cleanup UI with sizes ("2.1 GB from the old speech engine —
   [Reclaim]"), and the offer only appears in the release where the sidecar is
   actually removed — never during the soak (downgrade safety).
5. **Settings continuity.** Keep identifiers stable across engines (voice IDs
   like `af_heart`, whisper size names like `base.en`, embedding model name)
   so user selections survive invisibly.
6. **Update-dialog honesty.** When a one-time re-download applies (Whisper),
   say so in `docs/Rawhide.md` → the "What's New" dialog.
7. **Deletion is part of the phase.** The removal release deletes the sidecar
   binary, its build-workflow steps, its bundling/signing steps, and its
   Python source — per CLAUDE.md's dead-code rules. Bundle native libs
   (libfpzip, sherpa-onnx) via `Contents/Frameworks/` on macOS; they are
   signed by the existing broad codesign pass.

## Phase 1 record (Draw Things) — precedent to copy

- Native client: `lib/services/grpc/dt_native/` (proto codec, FlatBuffer
  builder with exact slot/default parity, NNC tensor codec, fpzip FFI).
- Fallback wiring: `draw_things_grpc_service.dart` — native first, sidecar on
  any failure, `FP_DT_SIDECAR=1` forces legacy, fpzip pre-flight avoids
  wasting a generation when the dylib is missing.
- Dev dylib: `scripts/build-fpzip-macos.sh` → `tools/fpzip/` (gitignored).
- Still TODO for phase-1 completion: bundle libfpzip in release workflows
  (macOS Frameworks/, Windows/Linux alongside exe), soak one release, then
  delete `tools/dt-grpc-python/`, the dt_grpc PyInstaller build steps, and
  the dt_grpc bundling/chmod steps in all three build paths.

## Phase 2 record (expression classifier) — shipped 2026-07-16

- In-process pipeline: `lib/services/expression/` — `wordpiece_tokenizer.dart`
  (BERT-uncased WordPiece: lowercase, Latin accent strip, punctuation/CJK
  splitting, greedy longest-match), `onnx_emotion_engine.dart` (isolate-run
  session-per-call inference via `onnxruntime_v2`, smolvlm precedent —
  better memory profile than the persistent sidecar), and
  `onnx_emotion_classifier.dart` (native-first `ExpressionClassifier` with
  automatic sidecar fallback + direct-HTTPS model download).
- Rollback lever: `FP_EXPR_SIDECAR=1` forces the legacy Python sidecar for
  classification AND download. Per-call fallback logs `[Expr-Native] ...`.
- Model reuse: resolves the sidecar's HuggingFace hub cache first (its
  `tokenizer.json` doubles as the vocab source when `vocab.txt` is absent);
  fresh installs download `model.onnx` + `vocab.txt` (~268 MB) straight from
  HF — **no Python required anymore** for the download or inference.
- **Bug fixed, not ported**: the sidecar's `EMOTION_LABELS` had 26 entries
  for a 28-class model (missing `disapproval` and `relief`), so every label
  after `disappointment` was reported shifted. The native path uses the
  model's true id2label order from its config.json.
- Verification: `test/services/expression/onnx_emotion_test.dart` — 18
  goldens generated from the exact Python sidecar stack (token ids for 13
  sentences incl. accents/curly-quotes/emoji/CJK/512-truncation; float64
  softmax scores from real model logits). Plus
  `onnx_emotion_e2e_test.dart` — full text→label pipeline against the real
  268 MB model, gated on `FP_EMOTION_TEST_MODEL` (skips in CI); passed
  against the Python reference on 2026-07-16 (all six labels + confidences
  within 1e-3).
- Still TODO for phase-2 completion: soak one release, then delete
  `sentiment_classifier.py`, its PyInstaller build/bundle steps in
  release/nightly workflows + `scripts/build-macos.sh`, and the
  `ONNXExpressionClassifier` sidecar class + its resolution logic.

## Phase 3 record (Whisper STT) — shipped 2026-07-16

- In-process engine: `lib/services/stt/sherpa_whisper_engine.dart` —
  isolate-run sherpa-onnx OfflineRecognizer (whisper int8 export), WAV
  reading via the package's `readWave`, plus an RMS silence trim
  (`trimSilence`) standing in for faster-whisper's VAD filter (all-silent
  clips → '' → "No speech detected"; documented divergence: mid-clip
  silence is left to Whisper).
- Sidecar transport extracted verbatim to
  `lib/services/stt/whisper_sidecar_transport.dart` (SttService shrank
  768→~700 lines); the whole file is the phase-completion deletion target.
  Rollback lever: `FP_STT_SIDECAR=1`. Fallback logs: `[STT-Native] ...`.
- New dep `sherpa_onnx` ^1.13.4 — prebuilt native libs ship inside the pub
  platform packages for macOS/Windows/Linux, so release bundling is
  automatic (no fpzip-style build script) and signing rides the existing
  codesign pass.
- Models: CT2 NOT reusable — sherpa int8 exports
  (`csukuangfj/sherpa-onnx-whisper-<size>`: encoder+decoder+tokens)
  download over direct HTTPS into `system/whisper_models/sherpa/<size>/`
  (CT2 cache untouched until the post-soak cleanup UI). Same size names
  ('tiny.en' ~105MB / 'base.en' ~155MB / 'small.en' ~360MB — dropdown
  labels updated), so the user's setting carries over; download happens on
  the settings button OR on first transcription (the sidecar also
  auto-downloaded on first use). One-time re-download called out in
  Rawhide.md per playbook rule 6.
- Shared infra: `lib/services/model_fetch.dart` — the direct-HTTPS
  downloader (.part + rename, skip-if-present, ~1% throttle, HEAD
  contentLength for aggregate multi-file progress) consolidated out of the
  phase-2 classifier and reused here.
- Web-UI mic uploads are webm/ogg — the native path handles WAV only
  (`canDecode` RIFF probe) and browser audio stays on the sidecar.
  **Phase-3 completion blocker:** move web mic capture to WAV (AudioWorklet
  PCM) or add an opus decode story before deleting the sidecar, else web
  voice input breaks.
- Verification: `test/services/stt/sherpa_whisper_test.dart` — trimSilence
  + canDecode unit tests always run; the real-model WAV→text test (gated on
  FP_STT_TEST_MODEL_DIR + FP_SHERPA_LIB) reproduced the upstream reference
  transcript exactly with tiny.en int8 in-sandbox 2026-07-16, and
  faster-whisper (the legacy stack, beam 5 + VAD) produced the identical
  words on the same WAV (punctuation/casing differ — expected across
  engines).
- Still TODO for phase-3 completion: web mic WAV capture (above), soak one
  release, then delete `whisper_stt.py`, its PyInstaller build/bundle steps
  in release/nightly workflows + `scripts/build-macos.sh`, and
  `whisper_sidecar_transport.dart`; offer the CT2 cache in the cleanup UI.

## Phase 4a record (Kokoro TTS) — shipped 2026-07-16

- In-process engine: `lib/services/tts/sherpa_kokoro_engine.dart` — ONE
  persistent worker isolate holding the loaded sherpa OfflineTts (the
  stays-warm parity for the 1–4 process Python pool; ONNX intra-op
  threading covers the parallelism), jobs serialized over SendPorts, WAV
  written via sherpa's writeWave into the same temp-file contract the pool
  used, so TtsService playback/chunking is untouched.
- Wiring: `kokoro_engine.dart` — native-first in generateAudio /
  ensureModelReady / ensureWorkersWarm / isAvailable / shutdown, Python
  pool as automatic per-call fallback. Lever: `FP_TTS_SIDECAR=1`. Logs:
  `[TTS-Native] ...`.
- **Model reuse correction:** the doc's earlier "mostly reusable" guess
  was WRONG — sherpa's export embeds required ONNX metadata and its
  voices.bin is a custom binary (not the kokoro-onnx npz), so the legacy
  kokoro-v1.0.onnx + voices-v1.0.bin are NOT loadable. One-time re-download
  of `kokoro-multi-lang-v1_0.tar.bz2` (~160MB compressed → ~380MB: model,
  voices.bin, tokens, lexicons, espeak-ng-data, jieba dict) from sherpa's
  GitHub releases (same host the legacy engine downloaded from), extracted
  with package:archive in an isolate into
  `system/kokoro_models/sherpa-v1_0/` (legacy files untouched until the
  post-soak cleanup UI). Surfaced in Rawhide.md.
- Settings continuity: voice NAMES are identical (af_heart … zm_yunyang);
  `SherpaKokoroEngine.speakerIds` maps all 53 names to sherpa speaker ids
  (source: scripts/kokoro/v1.0/generate_voices_bin.py). Characters'
  saved voices keep working; unknown names fall back to af_heart.
- Shared infra: `lib/services/sherpa_runtime.dart` — sherpaNativeLibDir()
  consolidated out of the phase-3 whisper engine, used by both.
- Verification: `test/services/tts/sherpa_kokoro_test.dart` — speaker-id
  map test always runs; gated real-model tests (FP_TTS_TEST_ROOT) verified
  in-sandbox 2026-07-16, including the **closed-loop test**: Kokoro speaks
  a sentence and the phase-3 Whisper engine transcribes the exact words
  back (24kHz→16kHz resample handled by sherpa) — two retired sidecars
  verifying each other, no reference audio needed.
- Still TODO for phase-4a completion: soak one release, then delete
  `kokoro_tts.py`, `kokoro_worker_pool.dart`, the kokoro PyInstaller
  build/bundle steps, and the legacy download URLs; offer the old model
  files in the cleanup UI.

## Phase 4b record (Piper TTS) — shipped 2026-07-16

- Engine: `lib/services/tts/sherpa_piper_engine.dart` — persistent worker
  isolate holding one loaded vits voice (respawns on voice change);
  strictly faster than the legacy one-process-spawn-per-chunk binary.
- Voice mapping is PROGRAMMATIC, no curated table: rhasspy voiceKey
  `en_US-lessac-medium` → sherpa bundle `vits-piper-en_US-lessac-medium`
  (.tar.bz2 on the same GitHub tts-models release as kokoro; ~60–100MB
  incl. per-voice espeak-ng-data). `ensureVoice` fetches on first native
  use into `system/piper_models/sherpa/<voiceKey>/`; a 404 (no re-export,
  e.g. hand-made voices) returns false and that whole message uses the
  legacy piper binary — automatic degradation. Original rhasspy `.onnx`
  files are NOT sherpa-loadable (missing embedded metadata).
- Wiring: `TtsService` piper block — `ensureVoice` once per message, then
  per-chunk native generate with binary fallback. Shares `FP_TTS_SIDECAR=1`
  with Kokoro. tar.bz2 download+extract consolidated into
  `ModelFetch.fetchAndExtractTarBz2` (kokoro engine refactored onto it).
- Verification: layout-probe unit test always runs; gated closed-loop test
  (Piper speaks → phase-3 Whisper transcribes the words back, 22.05kHz
  resample) passed in-sandbox 2026-07-16 with the real
  vits-piper-en_US-lessac-medium export. NOTE: the gated TTS suites should
  run serially (`flutter test -j 1 test/services/tts/`) — two ONNX TTS
  engines + two Whisper decodes in parallel can starve small machines.
- Still TODO for phase-4b completion: soak, then delete `piper_entry.py`,
  its PyInstaller build/bundle steps, and `_generatePiperWav`/binary
  resolution in tts_service.dart; offer legacy piper `.onnx` files in the
  cleanup UI (keep `.onnx.json` — the voice manager still lists from it).

## Success criteria (whole effort)

Zero Python at runtime; `Sidecar.entitlements` deleted; release workflows lose
all PyInstaller steps; bundle shrinks >1 GB; worst-case user migration cost is
one Whisper model re-download + a few MB of Kokoro extras.

## Removal record (2026-07-18, branch claude/sidecar-ectomy)

Users field-confirmed all engines native in the no-Python Rawhide build, so
the removal release shipped. What landed:

- **Dart:** every sidecar spawn/fallback path deleted
  (whisper_sidecar_transport.dart, kokoro_worker_pool.dart,
  ONNXExpressionClassifier, DT `_runCli`), all `FP_*_SIDECAR` levers gone.
  Piper's streaming/call-mode and web-speak paths — which had NEVER been
  wired to sherpa — were unified onto the native engine.
  VoiceManager re-keyed "installed" onto `.onnx.json`; installs fetch the
  sherpa bundle eagerly instead of the unplayable rhasspy `.onnx`.
- **Web mic** (the phase-3 blocker): captures raw PCM via Web Audio and
  uploads 16 kHz WAV — no webm anywhere.
- **EngineHealth** became a failure ledger (reportFailure); the Settings
  Engine Status panel was removed at the maintainer's request (desktop +
  web); the pre-release first-failure snackbar remains the loud surface.
- **Cleanup UI** (playbook rule 4): "Reclaim Disk Space" in Settings →
  Voice & Media + web Settings parity, backed by
  `lib/services/legacy_model_cleanup.dart` (one scanner + one applier;
  spares `sherpa/` dirs, piper `.onnx.json`, and the expression HF hub
  cache, which the native engine still reads).
- **Build:** Python sources + tools/dt-grpc-python deleted; nightly.yml and
  scripts/build-macos.sh build only the Rust embed_server (+ libfpzip).

**Deliberate exceptions (maintainer decisions, 2026-07-18):**
1. `Sidecar.entitlements` KEPT for the Rust embed_server — it has always
   shipped signed with that exact set, and entitlement changes are only
   verifiable via a full signed build. Revisit at phase 5.
2. `release.yml` / `beta-release.yml` NOT touched — they still reference
   the deleted .py files and MUST be ported (nightly.yml is the reference)
   before the next beta cut or Rawhide→main promotion. nightly.yml must
   also be synced to main immediately (the cron runs main's copy).

**Accepted degradation:** hand-made custom Piper voices (no sherpa
re-export) can no longer play; they surface a clear error instead of
silently using a binary that no longer exists.

## Phase 5 record (RAG embeddings) — COMPLETE, Rust server fully removed 2026-07-18

- In-process engine: `lib/services/embedding/native_embedding_engine.dart`
  — nomic-embed-text-v1.5 via onnxruntime_v2 in ONE persistent worker
  isolate (the 547MB f32 session loads once; per-call sessions like the
  emotion engine's would be unusable). Pipeline: `search_document: `
  prefix (the server applied it to everything — parity means we do too) →
  shared BERT WordPiece tokenizer, 512-token truncation → forward pass →
  mean-pool → L2 normalize.
- **Golden methodology upgrade**: the reference vectors were captured from
  the LIVE production Rust server (fastembed 4) BEFORE any Dart was
  written — 14 cases spanning roleplay text, accents, emoji, CJK,
  truncation, and unicode edge cases
  (test/services/embedding/goldens/nomic_v15_rust_goldens.json). The suite
  pins cosine > 0.9999 per case; it runs wherever the model exists on disk
  and skips in CI. This matters more here than any other phase: stored
  embeddings in user databases must keep comparing correctly against
  vectors the new engine produces, or RAG retrieval silently degrades.
- **Real bug the goldens caught**: the shared WordPiece tokenizer's accent
  stripping was a Latin-only lookup table; HF/fastembed strip via Unicode
  NFD across ALL scripts (Japanese voiced kana が→か, Greek/Cyrillic/
  Vietnamese diacritics), so those tokenized as [UNK] natively. Fixed with
  true NFD (`unorm_dart`, maintainer-approved dep) + combining-mark
  removal — which also quietly improves the expression classifier that
  shares this tokenizer (its own 18 goldens still pass).
- Model reuse: the engine reads the fastembed hub cache the Rust server
  populated (`~/Library/Caches/front-porch-ai/embeddings` and the
  platform equivalents) — zero re-download for existing users. Fresh
  installs download model.onnx + tokenizer.json over direct HTTPS
  (`EmbeddingService.runSetup`, driven by the RAG consent dialog with
  real progress) into `<root>/models/embeddings/nomic-v1_5/`.
- **Full removal, no soak** (maintainer decision 2026-07-18, "strip the
  rust sidecar out fully"): `tools/embed_server/` and
  `embedding_sidecar.dart` deleted outright; `EmbeddingService` is
  native-only (the app spawns NO helper processes at all); the RAG setup
  dialog and sidebar status run off EmbeddingService; nightly.yml +
  build-macos.sh lost the Rust toolchain/cargo/bundling steps and the
  helper-signing pass; and `Sidecar.entitlements` is DELETED — the final
  success criterion of the whole retirement. Confidence for skipping the
  soak came from the golden pinning: unlike the other engines, the
  parity here is bit-level-verified against the production binary.
- EngineHealth row: 'Memory embeddings'. `FP_ORT_LIB` pre-loads
  libonnxruntime for bare test harnesses (FP_SHERPA_LIB pattern).
- **Windows field bug (fixed 2026-07-18)**: `OrtSession.fromFile` in
  onnxruntime_v2 passes the model path to `CreateSession` as UTF-8, but on
  Windows that C API parameter is a wide-char `ORTCHAR_T*` (UTF-16) — the
  path is reinterpreted as garbage, so loading by path could NEVER work
  there ("the engine failed its self-test" on every Windows install; the
  phase-2 emotion engine and the smolvlm captioner had the same latent
  bug). Fix: `lib/services/onnx_runtime.dart` `ortSessionFromFile` routes
  Windows through `fromBuffer` (`CreateSessionFromArray` takes no path),
  all three engines use it. Verified by re-running the nomic goldens with
  the fromBuffer path forced on Linux — identical golden vectors.
