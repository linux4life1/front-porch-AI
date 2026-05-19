# Troubleshooting

Diagnosis and fixes for common issues.

---

## Table of Contents

### Startup Issues
- [App won't launch](#app-wont-launch)
- [App crashes on startup](#app-crashes-on-startup)
- [Blank / white screen](#blank--white-screen)
- [Setup wizard doesn't appear](#setup-wizard-doesnt-appear)

### AI / Generation Issues
- [KoboldCpp won't start](#koboldcpp-wont-start)
- [Generation is extremely slow](#generation-is-extremely-slow)
- [Empty responses](#empty-responses)
- [Model won't load (OOM error)](#model-wont-load-oom-error)
- [GPU not detected](#gpu-not-detected)

### Chat Issues
- [Messages not saving](#messages-not-saving)
- [Character responses are cut off](#character-responses-are-cut-off)
- [Realism Engine eval fails](#realism-engine-eval-fails)
- [Memory / RAG not working](#memory--rag-not-working)

### Voice Issues
- [TTS not producing sound](#tts-not-producing-sound)
- [STT / microphone not working](#stt--microphone-not-working)
- [Voice call mode unstable](#voice-call-mode-unstable)

### Data Issues
- [Database corruption](#database-corruption)
- [Missing character images](#missing-character-images)
- [Cloud sync failing](#cloud-sync-failing)
- [Beta vs stable data confusion](#beta-vs-stable-data-confusion)

### Platform-Specific
- [Linux: wpewebkit missing](#linux-wpewebkit-missing)
- [Linux: Wayland flickering](#linux-wayland-flickering)
- [macOS: Apple Silicon performance](#macos-apple-silicon-performance)
- [Windows: Antivirus false positive](#windows-antivirus-false-positive)

---

## Startup Issues

### App won't launch

**Common causes and diagnostic steps (based on `main.dart`, `BackendManager`, `WebServerService`):**

1. **Missing system dependencies (especially Linux)**:
   - The app uses `flutter_inappwebview` for Chub.ai browsing and `window_manager`. On Linux you need:
     ```
     sudo apt install libgtk-3-dev libwebkit2gtk-4.1-0 wpewebkit-1.1 libgstreamer1.0-0
     ```
     (See `install.md` and the bundled AppImage which includes them.)
   - Run the binary from a terminal to see the exact missing `.so` error.

2. **Corrupted or incomplete installation**:
   - Re-download the latest release and replace the entire folder.
   - On macOS, if the binary is quarantined: `xattr -cr /Applications/Front\ Porch\ AI.app`

3. **Port conflicts**:
   - KoboldCPP listens on `127.0.0.1:5001` (configurable in Settings).
   - Embedding sidecar uses `localhost:5055`.
   - The internal shelf web server (used for Chub import) uses an ephemeral port.
   - Kill any leftover processes:
     - Windows: `taskkill /F /IM koboldcpp.exe`
     - macOS/Linux: `pkill -f koboldcpp` or `pkill -f embed_server`

4. **How to view logs**:
   - Launch from terminal: `./Front_Porch_AI` (or the .exe / .app bundle) and watch the console output.
   - KoboldCPP session logs are written to `<data>/characters/session_log.txt`.
   - Open **Settings → KoboldCPP → View Kobold Logs** (opens `kobold_log_dialog.dart`).

If the app still fails to start, delete the entire data directory (`~/Documents/FrontPorchAI` or `FrontPorchAI-Beta`) and relaunch — a fresh database will be created.

### App crashes on startup

**Step-by-step diagnosis (see `main.dart:111`, `AppDatabase.integrityCheck`, `KoboldService`):**

1. **Launch from terminal** and capture the full stack trace. Common crash signatures:
   - `FlutterEngineRemoveView returned kInvalidArguments` or segfault → unclean shutdown of KoboldCPP (the `SIGINT`/`SIGTERM` handlers in `main.dart:89` and `exit(0)` exist precisely to avoid this).
   - `Drift` / SQLite errors → database corruption.

2. **Database corruption** (most frequent cause):
   - On launch the app runs `db.integrityCheck()` (`PRAGMA quick_check`).
   - If it fails, a red "Database Corruption" overlay appears with a list of timestamped `.db` backups.
   - Click any backup row to restore. Backups are created automatically before cloud sync and on clean shutdown (`DbReunificationService.createBackups`).
   - Manual location: `<data>/characters/` (and sometimes root) — look for `*.db.bak*` files.

3. **GPU driver / KoboldCPP startup crash**:
   - Intel Mac users: local inference is explicitly blocked (`BackendManager.isIntelMac`).
   - Try switching to **Remote API** mode in Settings → AI Backend before the model loads.
   - On Linux: run `nvidia-smi` or `rocminfo` manually. If they fail, the app falls back to the `-nocuda` binary.
   - Force CPU-only: delete the current `koboldcpp*` binary from `koboldcpp_bin/` and let the app re-download the nocuda variant.

4. **Recovery command**:
   ```bash
   # macOS/Linux
   pkill -9 -f koboldcpp
   pkill -9 -f embed_server
   rm -f ~/Documents/FrontPorchAI/characters/*.db-wal
   ```

After fixing, the app should pass the integrity check on next launch.

### Blank / white screen

**UI rendering troubleshooting (Flutter desktop + window_manager):**

1. **GPU / driver incompatibility**:
   - Linux: Force X11 instead of Wayland:
     ```bash
     GDK_BACKEND=x11 ./Front_Porch_AI
     ```
   - Try disabling hardware acceleration in your GPU control panel (rare).

2. **Display scaling / HiDPI**:
   - On high-DPI monitors (especially macOS Retina or 4K Linux), try launching with:
     ```bash
     export GDK_SCALE=1
     ./Front_Porch_AI
     ```
   - Or change the app's window scale in Settings → UI → Interface Scale.

3. **Clear Flutter / window cache**:
   - Delete the app's data folder (or just the `custom_backgrounds/` and prefs) and restart.
   - On macOS, also clear `~/Library/Containers/` if sandboxed (unlikely for this app).

4. **Diagnostic**:
   - Launch from terminal; a white screen with console errors about `WPE` or `ANGLE` points to the inappwebview / OpenGL layer.

If the sidebar and title bar appear but the main content is white, the issue is usually inside the currently selected page (try clicking Home in the sidebar).

### Setup wizard doesn't appear

The first-run overlay (`SetupOverlay` in `lib/ui/widgets/setup_overlay.dart` and `SetupService`) is shown when `StorageService.rootPath` is still the default and no model or API key has been configured.

**Fixes:**
- Go to **Settings → AI Backend** and ensure either a local KoboldCPP model is selected or a Remote API endpoint + key is saved.
- Manually trigger the wizard: in Settings → Advanced → "Re-run First-Time Setup".
- If the data directory was manually set on a previous run, the wizard is suppressed. You can reset by clearing the `root_path` (or `root_path_beta`) key in SharedPreferences (use a SQLite browser on the prefs file or delete the entire FrontPorchAI folder).

The wizard also downloads the embedding sidecar binary and KoboldCPP if you choose local mode.

---

## AI / Generation Issues

### KoboldCpp won't start

**Diagnosis and recovery (core logic in `lib/services/kobold_service.dart` + `BackendManager`):**

1. **Port already in use (5001)**:
   - The app auto-kills orphaned KoboldCPP processes on startup (`reconnectIfAlive` + `killOrphanedBackend` using `taskkill` / `pkill`).
   - If it still fails:
     - Windows: `netstat -ano | findstr :5001` then `taskkill /PID <pid> /F`
     - macOS/Linux: `lsof -i :5001` or `sudo kill -9 $(lsof -t -i:5001)`

2. **Missing executable**:
   - `BackendManager.checkBackendAvailability()` looks in `<data>/koboldcpp_bin/`.
   - Click **"Download KoboldCPP"** in Settings → KoboldCPP Backend.
   - Verify the correct binary name was downloaded (`koboldcpp.exe`, `koboldcpp-linux-x64`, `koboldcpp-mac-arm64`, `koboldcpp-linux-x64-rocm`, etc.).

3. **Insufficient permissions**:
   - macOS/Linux: the app runs `chmod +x` and `xattr -cr` (to clear quarantine) automatically.
   - Manually: `chmod +x koboldcpp*` inside the bin folder.
   - On some Linux distros you may need `sudo setcap cap_sys_admin+ep koboldcpp-linux-x64` for `--usemlock`.

4. **GPU driver issues**:
   - NVIDIA: install latest CUDA + reboot.
   - AMD: ROCm (Linux only) — set the ROCm toggle in Settings; the app will pick `koboldcpp-linux-x64-rocm`.
   - Intel Macs: local mode is disabled by design.
   - Force CPU fallback by choosing the `nocuda` binary.

Check the **Kobold Logs** dialog (real-time stdout/stderr from the Process) for the exact KoboldCPP error message (e.g., "failed to load model", "CUDA out of memory", "port bind failed").

After fixing, click **Start Backend** or enable "Autostart Backend".

### Generation is extremely slow

**Performance tuning (arguments passed by `KoboldService.startKobold`):**

1. **Model larger than VRAM**:
   - Lower **GPU Layers** (Settings → Model Settings) until speed jumps from <1 t/s to 15–30 t/s.
   - Use a more quantized model (Q4_K_M or Q5_K_M instead of Q8_0 or FP16). The VRAM estimator in the model picker helps.

2. **Wrong GPU backend**:
   - NVIDIA: ensure `--usecublas <gpuId>` is passed (the app now forces the correct GPU ID to avoid iGPU on multi-GPU systems).
   - AMD: enable ROCm toggle + `--usehipblas`.
   - macOS Apple Silicon: Metal is automatic (`koboldcpp-mac-arm64`).
   - Intel/AMD iGPU: fall back to the `nocuda` binary and accept CPU speeds.

3. **Swap thrashing / RAM pressure**:
   - Enable **mlock** (Settings → Advanced → "Prevent model paging") — prevents the OS from swapping model weights to disk.
   - Close browsers, IDEs, and other large apps.
   - Reduce **Context Size** or enable KV cache quantization (`--quantkv`).

4. **Recommended settings for speed**:
   - Flash Attention: ON (CUDA/Metal only)
   - KV Quantization: 4-bit or 8-bit
   - BLAS batch size: 1024–2048 for large VRAM cards
   - Use `.kcpps` presets that were tuned for your hardware

Watch the real-time token/s counter in the chat input area. If it stays below ~5 t/s on a modern GPU, the model is too big or running on the wrong device.

### Empty responses

**Root causes and fixes (generation path in `ChatService` + Kobold `/api/extra/generate/stream`):**

1. **Stop sequence triggered immediately**:
   - Common when the model sees its own name or a newline as a stop string.
   - Go to **Chat Settings → Generation → Stop Sequences** and remove overly aggressive entries (e.g., just `\n` or the character's name).
   - The app also sends a dynamic stop list derived from the character card.

2. **System / character prompt conflict**:
   - An extremely long or contradictory system prompt can cause the model to emit an EOS token right away.
   - Temporarily set System Prompt to the built-in default in Settings.

3. **Context window full / truncation**:
   - When the prompt + history exceeds the model's context, KoboldCPP may truncate in a way that leaves only the stop tokens.
   - Reduce **Context Size** or enable **"Smart Context"** (the app's `SessionGenSettings.resolveContextSize`).

4. **Model incompatibility**:
   - Some GGUF quants or fine-tunes have broken EOS handling.
   - Test with a known-good model (e.g., a Q4_K_M Llama-3 or Qwen2.5).
   - Switch temporarily to a Remote OpenAI-compatible endpoint to isolate whether the problem is local KoboldCPP or the model file.

If the log shows "Generation finished with 0 tokens", the model refused to continue — usually a stop-sequence or grammar issue.

### Model won't load (OOM error)

**Out-of-memory handling (KoboldCPP startup + VRAM estimator):**

1. **Immediate workaround**:
   - In the model picker / Settings, lower **Context Size** first (4096 → 2048 or 1024). Context uses a lot of VRAM even before the model weights.
   - Reduce **GPU Layers** to a value that fits (the app will still run the rest on CPU).

2. **Quantization**:
   - Prefer **Q4_K_M** or **Q5_K_M** over Q8_0 or FP16. The difference in quality is small; the VRAM saving is massive (~50%).
   - The built-in VRAM estimator (`lib/utils/vram_estimator.dart`) shows estimated usage before you load.

3. **System RAM / swap**:
   - On Linux, increase swap or run with `--mlock` disabled if you are on the edge.
   - Close all other applications. On Apple Silicon the unified memory is shared; watch Activity Monitor.

4. **Recovery after OOM crash**:
   - KoboldCPP often leaves a partially loaded state. Use the **Stop Backend** button, wait 5 seconds, then **Start Backend** again.
   - If the binary itself crashed, delete it and re-download.

The app never auto-downgrades quantization for you — you must choose a smaller quant or reduce context/layers manually.

### GPU not detected

**GPU backend detection logic (`BackendManager._init` and `KoboldService.startKobold`):**

1. **NVIDIA (CUDA)**:
   - The app runs `nvidia-smi` at startup. If it succeeds, it downloads `koboldcpp-linux-x64` and passes `--usecublas <gpuId>`.
   - Verify with `nvidia-smi` in terminal. Reboot after driver install.
   - Multi-GPU systems: the app now explicitly passes the GPU ID from Settings → Hardware to avoid silently using the integrated GPU.

2. **AMD (ROCm / HIP)**:
   - On Linux only. The app checks `rocminfo`. You can override the auto-detection with the "Use ROCm" toggle in Settings.
   - Requires ROCm installed and the `koboldcpp-linux-x64-rocm` binary.
   - Flash Attention is disabled for ROCm (`--noflashattention`).

3. **Intel ARC**:
   - Use the Vulkan path if available, or fall back to the `nocuda` CPU binary.
   - OneAPI / Level-Zero drivers must be installed.

4. **macOS**:
   - Apple Silicon (`arm64`): `koboldcpp-mac-arm64` + Metal (automatic, no flag needed).
   - Intel Macs: explicitly unsupported for local inference (`isIntelMac` check). Use Remote API only.

**Diagnostic**:
- Open **Settings → KoboldCPP Backend → Hardware Detection** (or look at the status line under the backend card).
- The status shows "CUDA", "ROCm", or "CPU-only (nocuda)" based on the executable that was downloaded.

If the wrong binary was chosen, delete the files in `koboldcpp_bin/` and toggle the ROCm switch, then re-download.

---

## Chat Issues

### Messages not saving

**Persistence layer (`ChatService`, `AppDatabase` via Drift, `CharacterRepository`):**

1. **Disk full**:
   - The app writes to `<data>/characters/` (DB + images) and `<data>/chats/`.
   - Check free space; the DB can grow quickly with long histories and RAG embeddings.

2. **Database locked / concurrent access**:
   - Multiple app instances or cloud sync running at the same time can lock the SQLite file.
   - Close all other instances, wait 10 seconds, then relaunch.
   - Cloud sync performs `checkpoint()` + `PRAGMA wal_checkpoint(TRUNCATE)` before upload.

3. **Permission / path issues**:
   - On macOS/Linux, ensure the Documents folder is not read-only.
   - If you moved the data directory manually, re-select it in Settings → Data Directory and restart.

4. **Recovery**:
   - Messages are saved after every AI turn (`_saveMessage` and `_saveRealismState`).
   - If the last few messages are missing, the most recent backup (shown in the corruption overlay) usually contains them.

Check the console for "INSERT failed" or Drift errors. The session log (`session_log.txt`) also records high-level chat events.

### Character responses are cut off

**Truncation diagnosis (`SessionGenSettings`, `maxLength` passed to Kobold, stop sequences):**

1. **Max Response Length too low**:
   - In **Chat Settings** (or the per-chat gear icon) raise **Max Length** (default 180–300 tokens). For long RP, 400–600 is common.

2. **Context window exhausted**:
   - When history + system + RAG + realism state > context, the app trims from the oldest messages (`_trimContextIfNeeded`).
   - The trim may remove important earlier context, causing the model to stop early.
   - Solution: increase Context Size (if VRAM allows) or enable "Smart Context" trimming.

3. **Stop sequence appearing inside the response**:
   - The model sometimes generates the stop string mid-sentence (e.g. the character's name followed by `:`).
   - Remove or make the stop sequences less aggressive in Chat Settings → Generation.

4. **Model-specific**:
   - Some instruct-tuned models treat the end of the prompt as a hard stop.
   - Try a different model or add a "continue" instruction in the character card's "Post History Instructions".

You can also click the **"Continue"** button (if shown) on a truncated message — it appends another generation pass.

### Realism Engine eval fails

**Realism Engine internals (`lib/services/chat_service.dart` — GBNF grammars, dual-call vs one-shot):**

The Realism Engine issues constrained JSON generation calls before the main response. KoboldCPP's GBNF support is sometimes brittle.

**Immediate workarounds (in Settings → Realism Engine):**

1. **Enable "One-Shot Eval (Experimental)"**:
   - Fuses relationship + emotion + narrative + trust into a single LLM call (`_evaluateOneShotCall`).
   - Dramatically reduces the chance of grammar failure and halves the pre-generation latency.
   - Some weaker models may struggle with the longer prompt — test per model.

2. **Switch to Remote API**:
   - Remote OpenAI-compatible endpoints (OpenRouter, Groq, Together, etc.) almost never have grammar problems and are faster for evals.
   - The app automatically falls back to plain JSON prompting when using remote backends.

3. **Other mitigations**:
   - Lower the "Realism Eval Temperature" (0.3–0.5 recommended).
   - Disable individual eval types you don't need (e.g., turn off Trust Repair or Climax Detection).
   - Increase the realism eval timeout in Advanced settings.

4. **Diagnostic**:
   - Enable "Verbose Realism Logging" in Settings → Developer.
   - Look in the console for `[Realism:Emotion] Failed: ...` or GBNF parse errors.
   - The app is resilient: even if an eval fails, the conversation continues and the state is advanced heuristically (`_advanceRealismStateOnFailure`).

The GBNF grammars (`_kGbnfJsonObject`, `_kGbnfJsonStringArray`) are deliberately permissive to accept any valid flat JSON object.

### Memory / RAG not working

**RAG pipeline (`EmbeddingSidecar`, `EmbeddingService`, `chat_service.dart` RAG retrieval):**

The local memory system uses a Rust sidecar (port 5055) running `nomic-embed-text-v1.5` via ONNX Runtime.

**Step-by-step checks:**

1. **Embedding sidecar not running**:
   - On first launch the app starts `EmbeddingSidecar.start()` automatically.
   - Check status in **Settings → Memory / RAG**.
   - If it says "Error" or "Crashed":
     - The binary is at `<app>/embed_server/embed_server(.exe)`.
     - Manually run it from terminal to see the error: `./embed_server/embed_server`.
     - Common: missing `libonnxruntime.so` (bundled in release).

2. **ONNX model not downloaded**:
   - The sidecar downloads `nomic-embed-text-v1.5` on first use (progress shown in the RAG card).
   - It is stored inside the embed_server working directory or the user's data folder.
   - Delete the `embed_server` folder and restart to force re-download.

3. **Python confusion**:
   - The embedding sidecar is **Rust**, not Python (unlike Kokoro TTS / Whisper STT).
   - No pip packages are required for RAG.

4. **RAG not retrieving anything**:
   - Messages must be long enough and have semantic content.
   - Try the "Re-index All Chats" button in Settings → Memory.
   - Check the console for `[RAG:Chat] ✗ RAG retrieval failed`.

5. **Recovery**:
   - Stop the sidecar via the UI toggle, kill any leftover process (`pkill -f embed_server`), then restart it from Settings.
   - If the sidecar binary is missing after an update, re-run the first-time setup or copy it from a fresh release.

When working, you will see "RAG: X chunks retrieved" in the debug logs for relevant user messages.

---

## Voice Issues

### TTS not producing sound

**TTS architecture (`TtsService`, `KokoroEngine`, `audioplayers` + macOS `afplay` fallback):**

1. **Python / dependencies (development mode)**:
   - In dev builds the app runs `python3 kokoro_tts.py` (or `python` on Windows).
   - Install the required packages:
     ```bash
     pip3 install kokoro-onnx soundfile numpy
     ```
   - Ensure `python3` (or `python`) is in your `PATH`.

2. **Release / bundled mode**:
   - The app ships a PyInstaller one-dir bundle (`piper/kokoro_tts/kokoro_tts(.exe)`).
   - No Python install needed. If the wrapper is missing, the TTS engine will silently fall back and log an error.

3. **Model files missing**:
   - Kokoro downloads ~300 MB models on first use to `<data>/system/kokoro_models/`.
   - If download fails, delete the partial `.onnx` / `.bin` files and toggle TTS off/on.

4. **Per-character voices not working (especially with Piper or custom voices)**:
   - Voice assignments on individual characters (or group members) must match the **currently selected TTS engine**.
   - If you switch from Kokoro → Piper (or vice versa), previously assigned character voices may become incompatible.
   - The character voice picker now shows "(incompatible with ...)" warnings.
   - Fix: Open the character voice picker and re-assign a voice that matches your current engine (or choose "Use global default").

4. **No audio output device / muted**:
   - The app uses `audioplayers` package. On some Linux systems you must install `libgstreamer-plugins-base` or `pulseaudio-utils`.
   - On macOS it falls back to the `afplay` system command for the generated WAV.
   - Test by clicking the speaker icon on any message.

5. **Engine-specific**:
   - **Kokoro** (default): best quality.
   - **OpenAI / ElevenLabs**: require valid API key + internet.
   - **Piper**: legacy, requires `.onnx` voice models in the piper folder.

Check the console for "Kokoro stderr:" or "TTS: no voice configured". Also verify the correct voice is selected in Settings → Voice.

### STT / microphone not working

**STT pipeline (`SttService`, `record` package, Python Whisper helper `whisper_stt.py`):**

1. **OS microphone permission**:
   - **macOS**: System Settings → Privacy & Security → Microphone → grant access to "Front Porch AI".
   - **Windows**: Settings → Privacy → Microphone.
   - **Linux**: some distros require `pipewire` or `pulseaudio` and the app to be launched from a desktop entry (not pure terminal).

2. **Wrong input device**:
   - In **Settings → Voice → STT**, open the device dropdown and select the correct microphone.
   - The `AudioRecorder` from the `record` package enumerates `InputDevice`s.

3. **Whisper model not downloaded**:
   - First use downloads a Whisper model via the Python helper (similar to Kokoro).
   - The model is cached in the user's data directory under a `whisper` subfolder.
   - Delete it and re-trigger a recording to force re-download.

4. **Python helper not found (dev mode)**:
   - The helper script lives in the `piper/` directory alongside the TTS files.
   - Same PYTHONPATH logic as Kokoro TTS is used.

5. **Continuous call mode unstable**:
   - Adjust the **Silence Threshold** (higher = less sensitive) and **Buffer Sentence Count** in STT settings.
   - Background noise can cause false triggers; use a headset or lower the mic gain in the OS.

Test by using the mic icon in the chat input (push-to-talk). If transcription never appears, look for "STT transcription failed" in the console.

### Voice call mode unstable

**Continuous voice call loop (`SttService` + `ChatService` auto-send transcription):**

- The call mode records in a loop, transcribes when silence is detected, sends the text, waits for the AI reply (TTS), then listens again.
- **Background noise**: raise the Silence Threshold slider in Settings → Voice → STT.
- **Cloud STT latency**: if you are using a remote STT provider (not local Whisper), add a longer "Thinking" grace period in the call settings.
- **Buffer settings**: increase "Sentences before AI responds" so the character hears a full thought instead of fragmented sentences.
- **TTS playback interrupting** the mic: the app should mute the mic while speaking, but on some systems you may need to manually lower the mic volume during AI speech.

If the call gets stuck in "thinking" or "speaking", click the big red "End Call" button in the voice overlay. The underlying `CallStatus` enum prevents most deadlocks.

---

## Data Issues

### Database corruption

**Full recovery workflow (`main.dart:897`, `AppDatabase.integrityCheck`, `BackupService`, `DbReunificationService`):**

1. **Auto-detection**:
   - On every launch `PRAGMA quick_check` is run. Failure sets `_isDbCorrupt` and shows a full-screen red overlay listing available backups.

2. **Restore from overlay**:
   - Click any row (newest first). The app closes the current DB, replaces the file with the chosen backup, runs migrations, and restarts the UI.
   - All characters, chats, lorebooks, worlds, and realism state are restored.

3. **Manual backup location**:
   - Automatic backups are written to the same directory as the main `frontporch.db` (usually `<data>/` or `<data>/characters/`).
   - Filenames contain timestamps (e.g., `frontporch.db.bak.2026-05-15_14-03-22`).
   - You can also manually copy the `.db` file before risky operations.

4. **Prevention**:
   - Always use the in-app **Quit** / window close button (the app intercepts `preventClose` and performs a clean `checkpoint()` + `stopKobold()` + `EmbeddingSidecar` shutdown).
   - Avoid killing the process with Task Manager / `kill -9` while a generation or cloud sync is in progress.
   - Cloud sync also creates a backup immediately before downloading a remote DB.

After a successful restore you may still need to re-index RAG (`Settings → Memory → Rebuild Embeddings`).

### Missing character images

**Image handling (`CharacterRepository`, `StorageService.resolveCharacterImage`, `FileConsolidationService`):**

- Character images (PNG/JPG) are stored inside `<data>/characters/<uuid>/` or referenced by absolute path in the DB.
- **Path changed** (moved data folder, renamed drive, cloud sync between machines):
  - The app attempts best-effort resolution. If the file is gone, the character card shows a placeholder silhouette.
- **Fix**:
  1. Open the character in the editor.
  2. Re-upload the image (it will be copied into the correct per-character folder).
- **Orphaned files**:
  - The `FileConsolidationService` (run at every startup) cleans up stray images that no longer have a DB row.
  - You can safely delete any `.png` files inside `characters/` that do not belong to a card you care about.

Images are never deleted automatically when you delete a character (soft-delete first for 30 days), giving you a safety window.

### Cloud sync failing

**CloudSyncService + provider-specific logic (`GoogleDriveProvider`, `DatabaseMergeService`):**

1. **Connection / auth failures**:
   - Google Drive: re-authenticate (the OAuth token can expire). The app opens the browser consent screen.
   - WebDAV: verify host, username, password, and that the target folder is writable. Use `https://` not `http://` unless you have a self-signed cert configured.

2. **Schema version mismatch**:
   - The app stores a `sync_version` in the DB. On major schema changes the merge service may refuse to import an older backup.
   - Solution: update both machines to the exact same app version (including beta vs stable).

3. **Conflict resolution**:
   - When the same character/chat was edited on two devices, the `DatabaseMergeService` performs a last-writer-wins merge based on `updated_at` timestamps + UUIDs.
   - If a conflict is detected you will see a "Reunification" overlay after sync (`DbReunificationService`).
   - Choose which version to keep per item or let the newest win.

4. **Diagnostic steps**:
   - Open **Settings → Cloud Sync → View Sync Log**.
   - Common errors are printed with `[CloudSync]` tags.
   - Before uploading, the app always runs `checkpoint()` to flush the WAL so the `.db` file on the server is self-contained.

5. **Recovery**:
   - Disconnect the provider, delete the remote `frontporch.db` (or rename it), then force a fresh upload from the "good" machine.

Always keep at least one local backup before enabling sync on a new device.

### Beta vs stable data confusion

**Complete isolation logic (`StorageService`, `app_version.dart` `isPreRelease`):**

- **Beta builds** (`0.9.8-Beta`, any version containing "-Beta"): use `~/Documents/FrontPorchAI-Beta` and all SharedPreferences keys are prefixed with `beta_`.
- **Stable builds** (e.g. `0.9.8`): use `~/Documents/FrontPorchAI` with normal keys.

This guarantees a beta tester never accidentally corrupts a stable user's characters, chats, or settings.

**Migration between them**:
1. Close both apps.
2. Copy the entire `FrontPorchAI-Beta` folder to `FrontPorchAI` (or vice-versa).
3. Launch the target build.
4. In Settings → Data Directory, point it at the copied folder if needed.

**Note**: The two installs have completely separate KoboldCPP binaries, Kokoro models, embedding sidecars, and RAG indexes. You must re-download models in each.

This design is deliberate and documented in `StorageService._init` and `Claude.md` / `AGENTS.md`. Never try to point a stable build at a beta folder without copying — the prefs keys will clash.

---

## Platform-Specific

### Linux: wpewebkit missing

**In-app browser (Chub.ai import) requirement (`flutter_inappwebview` + `main_layout` / `home_page.dart`):**

- The Chub.ai "Browse & Import" feature (`_openChubBrowser`) uses an embedded WebView.
- On Linux this requires the WPE WebKit backend:
  ```bash
  sudo apt install wpewebkit-1.1 libwpewebkit-1.1-0
  # or the older
  sudo apt install libwpewebkit-1.0-0
  ```
- The official **AppImage** release bundles WPE and all other Linux deps — strongly recommended for users who don't want to manage native packages.

If the browser button is grayed out or the import fails with a WebView initialization error, install the package and restart. You can still manually download character cards from Chub and drag them into the app.

### Linux: Wayland flickering

**Display server workaround:**

Flutter on Linux + GTK window manager sometimes exhibits flickering, black bars, or incorrect scaling under native Wayland.

**Fix** (already documented in the placeholder and confirmed in practice):
```bash
GDK_BACKEND=x11 ./Front_Porch_AI
```

You can create a desktop entry or wrapper script that always sets this variable.

Many users report that the AppImage or a native `.deb` built against X11 works more reliably on hybrid Wayland/X11 distros (Ubuntu 22.04/24.04, Fedora, etc.). The `GDK_BACKEND=x11` trick forces the X11 backend and eliminates most visual glitches.

### macOS: Apple Silicon performance

**M-series optimization (BackendManager + KoboldCPP mac arm64):**

- The release `.app` for Apple Silicon ships the `koboldcpp-mac-arm64` binary.
- Metal GPU acceleration is **automatic** — no `--metal` flag is required or passed.
- The app detects `uname -m` == `arm64` at startup and chooses the correct download URL.

**Tips for best performance**:
- Use the native arm64 build (not the Intel Rosetta one).
- Enable **Flash Attention** and **KV Quantization** in Settings → Advanced (both are supported on Metal).
- Keep **mlock** enabled (default on macOS) to prevent the unified memory from paging model weights.
- For very large models (70B+), reduce context size or GPU layers; the unified memory architecture is powerful but not unlimited.

If you see "Intel Mac" warnings, you are running the x64 build under Rosetta — download the arm64 DMG or build from source on an M-chip machine.

### Windows: Antivirus false positive

**Why it happens**:

- The Windows release ships `koboldcpp.exe` (downloaded from the official KoboldCPP GitHub) plus the app's own `Front_Porch_AI.exe`.
- Neither binary is code-signed with an EV certificate (expensive for an open-source AGPL project).
- Windows Defender, Malwarebytes, Avast, etc. frequently flag unsigned AI/LLM executables.

**Fix**:
1. When Windows Defender blocks the download or the first launch, click "More info" → "Run anyway".
2. Add an exclusion for the entire install folder:
   - Windows Security → Virus & threat protection → Manage settings → Add or remove exclusions → Add the `Front Porch AI` folder and the `koboldcpp_bin` subfolder.
3. For corporate / strict environments, build from source yourself (`flutter build windows`) and sign the binary with your own certificate.

The source code is fully public on GitHub; the binaries contain only what is described in the build scripts. No telemetry or hidden miners are present.

---

## Getting More Help

- [Discord Community](https://discord.gg/e4tET6rpdv) — live help from users and developers
- [GitHub Issues](https://github.com/linux4life1/front-porch-AI/issues) — report bugs
- [FAQ](faq.md) — answers to common questions

