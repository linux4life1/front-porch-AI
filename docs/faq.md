# Frequently Asked Questions

---

## Table of Contents

### General
- [Is Front Porch AI free?](#is-front-porch-ai-free)
- [Is my data private?](#is-my-data-private)
- [What platforms are supported?](#what-platforms-are-supported)
- [Do I need an internet connection?](#do-i-need-an-internet-connection)

### AI & Models
- [What AI models can I use?](#what-ai-models-can-i-use)
- [How do I choose a model?](#how-do-i-choose-a-model)
- [Can I use OpenAI / Claude / Google models?](#can-i-use-openai--claude--google-models)
- [Why is the AI slow?](#why-is-the-ai-slow)
- [Why does the AI give repetitive answers?](#why-does-the-ai-give-repetitive-answers)

### Characters
- [Where can I find characters?](#where-can-i-find-characters)
- [How do I import characters from SillyTavern?](#how-do-i-import-characters-from-sillytavern)
- [Why isn't my character acting right?](#why-isnt-my-character-acting-right)

### Voice
- [Why isn't TTS working?](#why-isnt-tts-working)
- [How do I improve voice quality?](#how-do-i-improve-voice-quality)
- [Why does voice call mode keep triggering?](#why-does-voice-call-mode-keep-triggering)

### Realism Engine
- [What is the Realism Engine?](#what-is-the-realism-engine)
- [Does the Realism Engine slow down chat?](#does-the-realism-engine-slow-down-chat)
- [How do I reset a character's bond/trust?](#how-do-i-reset-a-characters-bondtrust)

### Technical
- [How do I back up my data?](#how-do-i-back-up-my-data)
- [Where is my data stored?](#where-is-my-data-stored)
- [How do I fix a corrupted database?](#how-do-i-fix-a-corrupted-database)
- [Can I run Front Porch AI on a server?](#can-i-run-front-porch-ai-on-a-server)

---

## General

### Is Front Porch AI free?

Front Porch AI is completely free and open-source under the **AGPL-3.0-or-later** license (v0.9.0 and later; see `lib/app_version.dart` and the LICENSE file). You can download, use, modify, and redistribute it at no cost. Optional third-party services such as OpenRouter (for remote models) and ElevenLabs (for premium TTS) have their own paid plans if you choose to use them.

### Is my data private?

**Yes for local use.** When running local models via KoboldCpp:

- All chat processing, embeddings, and TTS happen on your machine.
- No prompts, chats, or character data are ever sent to Front Porch AI servers (there are none).

When you enable **remote APIs** (OpenRouter, etc.) or cloud TTS (ElevenLabs, OpenAI), your prompts are sent to those providers — review their privacy policies.

**Cloud Sync** (optional) uploads your files only to **your own** Google Drive or WebDAV/Nextcloud account. Credentials stay local; developers have zero access. Data is not end-to-end encrypted by the app before upload (use a provider with encryption-at-rest if desired).

Front Porch AI includes **no telemetry, analytics, or crash reporting**.

### What platforms are supported?

- **Windows** 10/11 
- **macOS** 12+ (Intel and Apple Silicon native .dmg)
- **Linux** (Debian/Ubuntu .deb, Arch AUR, AppImage, or manual build)

All platforms include the Rust embedding server and Python sidecar support.

### Do I need an internet connection?

- **Fully offline capable**: After the initial download of KoboldCpp + a GGUF model, local chats, RAG memory, local TTS (Kokoro/Piper), and everything else work without internet.
- **Requires internet**:
  - Remote LLM APIs (OpenRouter, etc.)
  - Cloud sync (Google Drive / WebDAV)
  - Cloud TTS engines (ElevenLabs, OpenAI TTS)
  - Chub.ai browser import (embedded webview)
  - Model Hub downloads

You can freely switch between offline and online modes at any time.

---

## AI & Models

### What AI models can I use?

**Local (recommended for privacy):**
- Any **GGUF** format model that runs in KoboldCpp (powered by llama.cpp).
- Supported architectures: Llama 2/3/3.1/3.2/3.3, Mistral, Mixtral, Qwen2/Qwen2.5/Qwen3, Phi-3/4, Gemma, Command-R, Yi, DeepSeek, etc.
- All quantization levels (Q2_K, Q3_K_M, Q4_K_M, Q5_K_M, Q6_K, Q8_0, etc.).
- The built-in **Model Hub** lets you browse and download popular models directly.

**Remote (via OpenRouter or custom OpenAI-compatible endpoint):**
- GPT-4o, Claude 3.5/4, Gemini 1.5/2.0, DeepSeek, Grok, Llama-3.1-405B, and hundreds more.
- Configure in **Settings → AI Settings → Remote API**.

**Hardware guidance** (approximate VRAM for Q4_K_M + 8k context):
- 6–8 GB VRAM → 7B–9B models (excellent for most characters)
- 12–16 GB VRAM → 13B–34B models
- 24+ GB VRAM → 70B+ or MoE models


### How do I choose a model?

1. Run the **Hardware Detection** tool in Settings → AI Settings (it auto-detects CUDA/ROCm/Metal/Vulkan and suggests safe GPU layer counts).
2. Start with a **7B–13B Q4_K_M or Q5_K_M** model — they offer the best speed/quality balance on consumer GPUs.
3. Larger models (34B–70B) give better reasoning and character consistency but need more VRAM or offloading.
4. Reasoning/thinking models (Qwen3, DeepSeek-R1, etc.) work great but are slower — enable "Thinking Mode" handling in Advanced settings.
5. Test a few models; personality and writing style vary dramatically between families.

Use the VRAM estimator in the Model Hub to see if a model will fit your GPU before downloading.

### Can I use OpenAI / Claude / Google models?

**Yes.** Front Porch AI has first-class **OpenRouter** integration (Settings → AI Settings → Remote API). 

- One API key gives you access to virtually every major model (Claude 3.5 Sonnet, GPT-4o, Gemini 1.5 Pro, Llama-405B, etc.).
- You can also point directly at any OpenAI-compatible endpoint (Nano-GPT, Together.ai, Fireworks, local vLLM/Ollama with OpenAI shim, etc.).
- Remote models work seamlessly with the Realism Engine, RAG memory, TTS, and all other features.

### Why is the AI slow?

Common causes and fixes:

- **Model too large** for your VRAM → the app is forced to offload layers to RAM or CPU. Solution: smaller model, higher quantization (Q3/Q4), or lower context size.
- **Too many GPU layers** requested → lower the "GPU Layers" slider.
- **CPU-only mode** → run Hardware Detection again or manually select a Vulkan/ROCm/Metal backend.
- Very high context (16k–32k) or large batch size.
- Background downloads, cloud sync, or Python TTS processes competing for resources.

The app shows real-time VRAM usage and token/speed stats in the status bar.

### Why does the AI give repetitive answers?

Try these adjustments (in **Chat Settings** or **Generation Settings**):

- Increase **Temperature** (0.8–1.1 is usually good for roleplay).
- Raise **Repetition Penalty** (1.05–1.15) or **Frequency Penalty**.
- Lower **Top-P** or **Min-P** slightly to increase variety.
- Check the character card — weak or missing **Message Examples** often cause repetition.
- Some models are inherently repetitive at low quantizations.
- Enable **XTC Sampling** (in Advanced) for more creative output.

A good system prompt and a few high-quality example dialogues in the card usually eliminate repetition entirely.

---

## Characters

### Where can I find characters?

- **Chub.ai** — Largest public library (use the in-app browser or download PNG cards).
- **Community Discord** — Share and request characters (link in-app).
- **RisuAI, Backyard AI, SillyTavern** users — Export their V2 cards (PNG or JSON) and import directly.
- **Built-in AI Character Creator** — Generate high-quality cards from a short concept (multiple modes: Automated, Quick, Guided).
- **Manual creation** — Full 6-step wizard with avatar upload, lorebook editor, and Realism Engine defaults.
- Your own creations — everything you make or edit is saved as standard V2.5 PNG cards (fully portable).

### How do I import characters from SillyTavern?

**Directly supported.** SillyTavern V2/V2.5 cards (both PNG with embedded `chara` chunk and standalone JSON) import perfectly:

1. Drag & drop the `.png` or `.json` file onto the character grid, or
2. Click **Import** → choose PNG/JSON (multi-select supported), or
3. Use the Chub.ai browser inside the app (downloads and imports in one step).

BYAF (Backyard AI) archives are also supported via a dedicated importer. After import you can assign tags and folders. Front Porch AI also reads and preserves any third-party extensions + its own `front_porch` Realism Engine section.

### Why isn't my character acting right?

Typical causes and solutions:

- **Weak character card** — Missing or low-quality **Message Examples** (few-shot dialogues) is the #1 culprit. Add 4–8 good exchanges.
- **Model too small / low quality** — 7B models can struggle with complex or subtle personalities. Try a 13B+ or a better 7B (e.g., Llama-3.1-8B or Qwen2.5-14B).
- **Temperature / sampling wrong** — Too low = robotic; too high = random. Start at 0.85–1.0 + 1.1 repetition penalty.
- **System prompt conflict** — The global system prompt in Settings can override card instructions. Try the per-character System Prompt field.
- **No lorebook / world context** — Attach relevant lore or a World for consistent world-building.
- **Realism Engine off** — Turn it on (per-character or globally) for much richer emotional memory and relationship progression.

Test the card in a new chat. Use the **Director Mode** (auto-play) to quickly evaluate behavior.

---

## Voice

### Why isn't TTS working?

Most common reasons:

- **Python not installed** or not in PATH (required for local engines).
- Missing Python packages: run `pip install kokoro-onnx soundfile faster-whisper`.
- Wrong engine selected in **Settings → Voice → TTS Engine** (Kokoro is the default local engine; Piper is also available).
- For cloud engines (ElevenLabs, OpenAI): API key not entered or invalid.
- On Linux: missing system audio libraries for microphone recording (install `portaudio19-dev` or the equivalent dev package for the `record` Flutter plugin used by `SttService`). This primarily affects Voice Call / STT, not pure TTS playback.
- For Piper TTS on Linux you may also need espeak-ng or the specific Piper voice files.

The app will show clear error messages in the Voice settings panel and console (plus Python stderr from the sidecar scripts). Kokoro works out-of-the-box on Windows/macOS/Linux once `pip install kokoro-onnx soundfile` (and the ONNX model files) are present. The TTS engines are in `lib/services/tts_service.dart`, `kokoro_engine.dart`, `openai_tts_engine.dart`, `elevenlabs_tts_engine.dart`, and the Python helpers in the repo root.

### How do I improve voice quality?

- **Best quality (paid)**: ElevenLabs — select any of their voices; extremely natural prosody and emotion.
- **Best free local**: **Kokoro-ONNX** (default) — surprisingly good for its size. Adjust speed, pitch, and emotion in the per-character or global TTS settings.
- **Piper**: Fast, lightweight, many voices. Good when you want many different character voices.
- **Per-character voices**: Assign a specific TTS voice (or ElevenLabs voice ID) directly on the character card (stored in the V2 card's `tts_voice` field and `front_porch` extensions) — it overrides the global default. See `CharacterCard.ttsVoice` and `v2_card_service.dart` parsing.
- **No automatic emotion-aware TTS** is currently implemented. The Realism Engine's emotion/arousal/bond state is **not** fed into TTS engines (Kokoro, Piper, ElevenLabs, or OpenAI) to modulate prosody, pitch, or style. Some engines (especially ElevenLabs) expose manual style/emotion parameters you can set globally or per-character, but there is no automatic coupling to Realism state. (This is a missing integration, not a documented feature.)

Many users run Kokoro for everyday use and switch to ElevenLabs only for important scenes. The Kokoro engine lives in `lib/services/kokoro_engine.dart` + `kokoro_tts.py` (requires `kokoro-onnx` + `soundfile`). Piper uses `piper_entry.py`.

### Why does voice call mode keep triggering?

Voice Call mode uses **silence detection** on the microphone input:

- It samples ambient noise for ~1.5 seconds on start to set a noise floor.
- Once it hears speech (amplitude > 1.8× noise floor), it waits for **2 seconds of continuous silence** before automatically sending the transcription and triggering the AI reply.

If it keeps triggering too early or too late:

- The silence detection parameters are **hardcoded** in the STT service: noise floor is the 75th percentile of ~1.5 seconds of ambient samples taken on call start; speech is anything >1.8× that floor; auto-send triggers after exactly **2 seconds** of continuous silence below threshold. There are currently **no sliders** for threshold multiplier or silence duration in Settings → Voice → STT Settings.
- To re-calibrate the noise floor, end the call and start a fresh Voice Call (it always re-samples on entry). There is **no "Re-sample" button** in the call overlay.
- Use a better microphone or headset (built-in laptop mics pick up fan/keyboard noise easily).
- Lower the microphone input gain in your OS.
- In the call overlay there is always a manual **Send** button (visible when listening/recording) that bypasses silence detection entirely. You can also disable `autoSendTranscription` behavior for non-call STT.

The implementation lives in `lib/services/stt_service.dart` (`_calibrateNoiseFloor`, `_startAmplitudeMonitor`, `_silenceThresholdMultiplier = 1.8`, `_silenceDuration = 2s`, and the Timer logic in amplitude polling).

---

## Realism Engine

### What is the Realism Engine?

See the dedicated [Realism Engine](realism-engine.md) guide — it is the authoritative deep dive (361+ lines, method-by-method breakdown). 

**Brutally short version:** Optional per-character / per-chat system (default **off**) that makes characters remember and evolve their relationship with you across sessions. Without it, every chat is stateless and characters have goldfish memory. With it:

- Tracks short-term + long-term bond (-300…+300), trust (-100…+100), nuanced emotions + intensity, arousal + NSFW refractory cooldown, time-of-day / day count, fixations (3-turn intrusive thoughts), spatial stance, chaos pressure, primary objectives, and more.
- All state lives in the `sessions` table of the SQLite DB (persisted with the chat history).
- After every user message (and on greeting/retroactive catch-up) it runs dedicated LLM evaluation calls (see the slowdown FAQ above) whose outputs are injected back into future system prompts via many `_get*Injection` helpers in `chat_service.dart`.
- Companion `expression_classifier.dart` (LLM + optional ONNX classifier) maps emotions to the 30 sprite/expression labels.
- Also powers Director Mode pacing, Chance Time (Chaos Mode) random events, character evolution fields in the card, etc.

It is **not** free. It costs 1–4 extra LLM inferences per turn depending on backend and One-Shot setting. It is the single most complex piece of the entire app. Read the real doc before complaining that "my character doesn't remember me."

### Does the Realism Engine slow down chat?

**Yes, significantly on local KoboldCpp backends — more than the marketing gloss suggests.**

**How it actually works (see `lib/services/chat_service.dart` for the gory details):**
- Before the main AI response is generated for a user message (and on post-greeting / retroactive baseline), the engine issues **multiple separate LLM "evaluation" inference calls**.
- In normal mode (One-Shot disabled) for **local KoboldCpp** (the most common setup): **four sequential calls** because Kobold is single-threaded:
  1. `_evaluateRelationshipCall` (bond/trust tiers, fixation, objectives)
  2. `_evaluateEmotionalStateCall` (emotion label + intensity)
  3. `_evaluatePhysicalStateCall` (arousal, NSFW cooldown, spatial stance, time-of-day)
  4. `_evaluateNarrativeCall` (scene summary, time passage)
- Each eval feeds the last 3–6 messages + character personality snippet into the LLM with a specialized system prompt and parses the JSON response to mutate internal state (persisted in the `sessions` table).
- For **remote OpenAI-compatible / OpenRouter** backends: the four calls are fired with `Future.wait` (parallel) so wall-clock cost is closer to one generation.
- When **One-Shot Eval Mode** is enabled (`_storageService.realismOneShotEval`): everything is fused into a **single** `_evaluateOneShotCall` that asks the model for all fields at once (shorter prompt, one prefill). This is the main mitigation, but some models handle the longer combined prompt poorly.
- There is **no support for a separate "eval model" or dedicated fast model** for these calls — they always use whatever LLM/backend is currently selected for chat. (The "fast dedicated eval model" suggestion in older docs is not implemented.)
- Additional Realism features (Chaos Mode / Chance Time, Fixation, NSFW cooldown decay, mood inertia, autonomous objectives, expression classification via `expression_classifier.dart`) add more prompt injection and occasional extra logic but not always extra full LLM calls.

**Realistic impact:**
- Fast 7B–13B Q4/Q5 local Kobold on good GPU: +3–8+ seconds per turn (4 evals × small context).
- Larger models or CPU offload: much worse.
- Remote API or one-shot + small/fast model: +1–3s is more realistic.
- The evaluations are "lightweight" only relative to a full 1k+ token creative reply; they are still full forward passes.

**Mitigations that actually exist today:**
- Turn on **One-Shot Eval Mode** (global in Settings or per-chat).
- Use a fast, small, high-throughput model for everything (including evals).
- Disable Realism entirely for that character/chat if the cost isn't worth it for a given scene.
- For remote users: the parallelization helps a lot.
- The engine only runs when `_realismEnabled` is true for the active character/session.

See the full `docs/realism-engine.md` (especially Performance Considerations and the method list in chat_service.dart) for exact prompt templates, state ranges, injection functions (`_getRelationshipInjection`, etc.), and expression classifier details (ONNX + LLM fallback). The FAQ version here is deliberately blunt because the previous one was misleading.

### How do I reset a character's bond/trust?

- **Easiest and only reliable way today**: Start a **new chat** with the character. On the first message (or post-greeting), the engine seeds fresh state from the character's saved initial Realism values (or global defaults if none). See `chat_service.dart` `_runPostGreetingEval` and character seeding logic.
- There is **no "Reset Realism State" button** in Chat Settings (the gear icon dialog — `chat_settings_dialog.dart` — has zero Realism controls or reset UI).
- You **can** edit the character's **initial** Realism values (short-term/long-term bond, trust, starting emotion, time of day, day count, etc.) in the full character editor (`edit_character_page.dart`) under the Realism tab / `realism_form_section.dart`. These only affect *new* chats started after the edit; existing chat sessions keep their historical state forever (stored per-session in the DB).
- Old chat history / messages are never mutated by resets. Realism state lives in the `sessions` table alongside the message list.

If you really need to "reset" an ongoing chat's Realism state without starting over, your only current options are manual DB surgery or exporting/importing the character (which doesn't carry per-chat session state). This is a known UX gap.

---

## Technical

### How do I back up my data?

Front Porch AI has robust automatic backup built in:

- **Auto-backup** runs every **10 minutes** (always enabled) and keeps the most recent **10** timestamped copies (pruning happens automatically). Backups live in `KoboldManager/backups/` next to the `front_porch.db`.
- The WAL (write-ahead log) is checkpointed before every backup so the .db file is self-contained.
- You can manually trigger a backup at any time via the button in **Settings → Cloud Sync & Backup** (or the web server API).
- Cloud sync (Google Drive / WebDAV) does **not** automatically create an extra backup before each operation in the current implementation — create one manually beforehand if you want a safety snapshot.
- Restoring is as simple as selecting a backup in the corruption recovery overlay (on launch after integrity failure) or via the in-app restore dialog. The app closes the live DB, copies the backup over, removes stale WAL/SHM files, and reopens.

**Cloud Sync** (Google Drive or WebDAV/Nextcloud) gives you an off-device copy. You can also simply copy the entire `FrontPorchAI` (or `FrontPorchAI-Beta`) folder.

Restoring is as simple as replacing the `.db` file or using the in-app restore dialog.

### Where is my data stored?

All data lives in a single user-controlled root folder:

- **Windows**: `Documents\FrontPorchAI\` (or `FrontPorchAI-Beta\` for beta builds)
- **macOS**: `~/Documents/FrontPorchAI/` (or `FrontPorchAI-Beta/`)
- **Linux**: `~/Documents/FrontPorchAI/` (or `FrontPorchAI-Beta/`)

Inside you will find:
- `KoboldManager/` — the SQLite database (`front_porch.db` or `front_porch_beta.db` for pre-releases) + `backups/` subfolder (timestamped DB copies) + `Characters/` subfolder (all PNG character cards and per-character `avatars/` folders)
- `models/` — your GGUF model files (and `koboldcpp_bin/` for the KoboldCpp binaries)
- `chats/` — per-character and group chat history
- `worlds/`, `lorebooks/`, `custom_backgrounds/`, etc.
- Beta builds (`FrontPorchAI-Beta`) deliberately use a completely isolated directory tree.

You can change the root location at any time in **Settings → Storage**. Beta builds deliberately use a completely separate directory so they never touch your stable data.

### How do I fix a corrupted database?

The app is very resilient:

1. On launch, it automatically detects SQLite corruption or schema issues.
2. A **Backup Restore overlay** appears listing all available timestamped backups (newest first).
3. Simply click any backup to restore it instantly.
4. If you need to go further back, the `backups/` folder contains every copy (up to 10 + manual ones).

**Prevention tips**:
- Always let the app shut down cleanly (avoid force-quitting during a write).
- Cloud Sync + periodic manual copies give additional safety.
- The WAL (write-ahead log) is checkpointed before every backup.

Manual repair with `sqlite3` tools is rarely needed.

### Can I run Front Porch AI on a server?

**Yes.** The app includes a built-in **Web Server** mode (shelf-based HTTP server):

- Enable it in **Settings → Advanced tab → Web Server** section (port default 8085, optional PIN).
- It exposes a browser-accessible interface (chat, character management, some API endpoints) over HTTP at `http://localhost:PORT` (or LAN IP).
- Useful for home server / NAS / headless machine access from phones/tablets/laptops on your LAN (or via reverse proxy + HTTPS / auth).
- Full REST-ish API surface for characters, chats, backups, etc. (see `web_server_service.dart` and the JS in `assets/web/`).

**Important limitations**: The heavy lifting (KoboldCpp inference, Python TTS sidecars `kokoro_tts.py`/`whisper_stt.py`, Rust embedding server, all LLM calls) still runs on the **host machine** where the Flutter desktop app is running. This is remote-*UI* access only, not a true headless server daemon. You still need the desktop app (or a running instance) on the machine with the GPU/models. The web UI is a convenience layer on top of the same `ChatService`, `CharacterRepository`, etc.

Implemented in `lib/services/web_server_service.dart` + `lib/services/storage_service.dart` (webServerEnabled, port, pin). Start/stop is driven from the settings toggle.

