# Troubleshooting

When something goes wrong, this page is the fastest route back to chatting. Find your symptom, follow the fix.

> **Golden rule:** if the app is acting strange and you're about to try something drastic — don't delete anything. Your chats, characters, and a week of automatic backups all live in your data folder ([where is it?](#where-is-my-data-folder)). The [Backups](#restoring-from-a-backup) system can undo most disasters.

---

## Table of Contents

### First Aid
- [Three things to try first](#three-things-to-try-first)

### Startup Problems
- [App won't launch](#app-wont-launch)
- [App crashes on startup](#app-crashes-on-startup)
- [Blank or white screen](#blank-or-white-screen)

### AI & Generation Problems
- [The AI engine won't start](#the-ai-engine-wont-start)
- [Generation is extremely slow](#generation-is-extremely-slow)
- [Empty or instantly-finished replies](#empty-or-instantly-finished-replies)
- [Model won't load — out of memory](#model-wont-load--out-of-memory)
- [GPU not detected](#gpu-not-detected)
- [Realism evaluations come back empty](#realism-evaluations-come-back-empty)

### Chat Problems
- [Replies get cut off mid-sentence](#replies-get-cut-off-mid-sentence)
- [Memory / RAG isn't working](#memory--rag-isnt-working)

### Voice Problems
- [TTS not producing sound](#tts-not-producing-sound)
- [Microphone / speech-to-text not working](#microphone--speech-to-text-not-working)
- [Voice call mode is unstable](#voice-call-mode-is-unstable)

### Your Data
- [Where is my data folder?](#where-is-my-data-folder)
- [Restoring from a backup](#restoring-from-a-backup)
- [Database corruption](#database-corruption)
- [Beta vs stable — two apps, two data folders](#beta-vs-stable--two-apps-two-data-folders)
- [Missing character images](#missing-character-images)

### Platform Notes
- [Linux: flickering or visual glitches](#linux-flickering-or-visual-glitches)
- [Linux: AMD GPU not being used](#linux-amd-gpu-not-being-used)
- [macOS: "damaged" warning, and Intel Macs](#macos-damaged-warning-and-intel-macs)
- [Windows: antivirus false positive](#windows-antivirus-false-positive)

### Still Stuck?
- [Getting more help](#getting-more-help)

---

## First Aid

### Three things to try first

1. **Quit and relaunch — properly.** Close the app with its own close button (not force-quit), wait a few seconds, and start it again. This cleanly restarts the AI engine and helper processes, which cures a surprising amount.
2. **Update.** Check you're on the latest version — many "known issues" are already fixed.
3. **Launch from a terminal** so you can see error messages:
   - **Windows:** open the install folder, then run `front_porch_ai.exe` from a Command Prompt opened there.
   - **macOS:** in Terminal: `/Applications/FrontPorchAI.app/Contents/MacOS/FrontPorchAI` (adjust if your install is named differently)
   - **Linux:** run the binary or AppImage from a terminal.

   Whatever it prints when things go wrong is gold — include it if you ask for help.

---

## Startup Problems

### App won't launch

**Nothing happens, or it dies instantly.**

- **Leftover processes from a previous run.** If the app was force-quit, the AI engine can be left running and block the next launch. Clean up:
  - Windows: Task Manager → end any `koboldcpp` or `front_porch` processes.
  - macOS/Linux: `pkill -f koboldcpp`
- **Linux — missing system libraries.** Run it from a terminal; if it complains about a missing `.so` file, install the library it names (commonly GTK 3, libsecret, or GStreamer). The **AppImage** bundles everything and is the easy way out.
- **macOS — blocked by Gatekeeper.** See the [macOS note](#macos-damaged-warning-and-intel-macs).
- **Broken download/install.** Re-download the release and reinstall. Your data is safe — it lives in your Documents folder, not the install folder.

If it still won't start, **don't delete your data folder** — grab the terminal output and ask on [Discord](https://discord.gg/e4tET6rpdv).

### App crashes on startup

The most common cause is a **damaged database** — usually from a power cut or a force-quit mid-write. The good news: the app checks its database on every launch, and if it finds damage it shows a recovery screen listing your automatic backups. Click one to restore — see [Database corruption](#database-corruption).

If there's no recovery screen and it just dies:

1. Launch from a terminal and read the error.
2. If the error mentions the AI engine or your GPU, switch to **Remote API mode** in Settings once you're in, or see [GPU not detected](#gpu-not-detected).
3. Kill leftover processes (see above) and try again.

### Blank or white screen

The window opens but shows nothing, or flickers badly:

- **Linux on Wayland:** force the X11 mode, which fixes most rendering glitches:
  ```bash
  GDK_BACKEND=x11 ./front_porch_ai
  ```
  (Add that to a launcher/desktop entry if it helps.)
- **Unusual display scaling:** try changing your monitor scaling, or adjust the app's interface scale in Settings once you can get in.
- If the window frame and sidebar draw but the middle is blank, click **Home** in the sidebar — the problem is usually one specific page, and knowing which one makes it easy for me to fix. Please report it!

---

## AI & Generation Problems

### The AI engine won't start

Front Porch AI manages a local AI engine (a program called **KoboldCpp**) for you. When it won't start:

- **Check the logs first.** Settings → the KoboldCpp section → **View Kobold Logs** shows the engine's own words about what went wrong ("failed to load model", "out of memory", etc.).
- **Engine not downloaded / half-downloaded:** use the download button in Settings to fetch it again.
- **Something is already using its port** (5001). Usually a leftover engine from a crashed session:
  - Windows: `taskkill /F /IM koboldcpp.exe`
  - macOS/Linux: `pkill -f koboldcpp`
- **GPU driver trouble:** see [GPU not detected](#gpu-not-detected).
- **Intel Mac:** local models aren't supported on Intel Macs — use Remote API mode instead.

### Generation is extremely slow

Slow almost always means **the model doesn't fit in your GPU's memory**, so it's partly running on the much slower CPU:

1. **Lower GPU Layers** until it fits — speed often jumps from a crawl to fast in one step.
2. **Use a smaller or more compressed model.** A Q4 version of a model needs roughly half the memory of a Q8 with barely any quality loss. The Model Hub shows size estimates before you download.
3. **Lower the context size.** Big context windows (16k+) eat GPU memory even before the model writes a word.
4. **Check the right GPU is being used** — on laptops and multi-GPU machines the app can be pointed at the wrong one; check the hardware section in Settings.
5. **Close other heavy apps** — games and browsers with lots of tabs compete for the same GPU memory.

Extras worth turning on if your hardware supports them (Settings → Advanced): **Flash Attention** and **KV cache quantization** both save memory, and **mlock** stops the system from swapping the model out to disk.

### Empty or instantly-finished replies

The character says nothing, or the reply ends after a word or two:

- **A stop sequence is firing immediately.** Stop sequences tell the model where to stop writing; an overly aggressive one (like a bare newline or the character's own name) can stop it instantly. Review them in the chat's generation settings and remove suspicious entries.
- **The context is completely full.** If the conversation plus character info exceeds the model's context window, there's no room left to reply. Lower what's injected or raise context size.
- **The model file is broken or badly converted.** Test with a well-known model — if that one works, the other file is the problem.
- **Test with a remote API** — if remote works and local doesn't, the issue is the local model or engine, not your character or settings.

### Model won't load — out of memory

- **Lower the context size first** — context can cost gigabytes before the model even loads.
- **Lower GPU Layers** — the rest of the model runs on CPU (slower, but it loads).
- **Pick a more compressed version** (Q4 instead of Q6/Q8) or a smaller model.
- After an out-of-memory crash, stop the engine, wait a few seconds, then start it again so it comes up clean.

The app estimates memory needs before you download a model — trust the estimate; if it says "tight", it will be.

### GPU not detected

- **NVIDIA:** run `nvidia-smi` in a terminal. If that fails, your driver needs installing/updating — reboot afterwards and re-run hardware detection in Settings.
- **AMD on Linux:** see [the AMD note](#linux-amd-gpu-not-being-used) — it's almost always group permissions.
- **AMD on Windows / Intel GPUs:** the app uses Vulkan, which works out of the box with current drivers.
- **Apple Silicon:** Metal acceleration is automatic — nothing to configure.
- **Intel Macs:** local models are not supported (no Metal GPU support for this workload) — the app will tell you and you can use Remote API mode.

If the wrong option was picked, delete the engine's downloaded files via Settings and re-download — the app will re-detect your hardware.

### Realism evaluations come back empty

Some local models struggle with the Realism Engine's short background questions and return nothing (bond/trust/mood chips stop updating). Fixes, in order of effectiveness:

1. Turn on **One-Shot Eval** in the Realism settings — one combined question instead of several works better on many models.
2. Try a different model — evaluation reliability varies a lot between models and compression levels.
3. Remote APIs essentially never have this problem, if you have one configured.

The conversation itself keeps working even when evaluations fail — you just lose that turn's state updates.

---

## Chat Problems

### Replies get cut off mid-sentence

- **Raise Max Response Length** in the chat's generation settings — for long roleplay scenes, 400–600 tokens is common.
- **Press Continue** on the truncated message — the model picks up where it stopped.
- **A stop sequence fired mid-reply** — e.g. the character's name with a colon appearing inside the text. Trim aggressive stop sequences.
- If it happens constantly in very long chats, the context is overflowing — the oldest messages get trimmed to make room, and some models handle that gracelessly. A summary or higher context size helps.

### Memory / RAG isn't working

Long-term memory ("the character remembered something from last week!") converts text to searchable meaning right inside the app — no internet, no helper programs, nothing extra to install. A few things can still trip it:

- **Check its status** in Settings → Memory. It should say ready.
- **First use downloads a small model** — give it a moment to finish.
- **Stuck?** Toggle memory off and back on in Settings; if it stays stuck, restart the app.
- **Memories exist but aren't recalled:** memory retrieval needs *meaningful* content to match on — one-word messages don't give it much. Look for the re-index option in the memory settings to rebuild the index if it seems out of date.

---

## Voice Problems

### TTS not producing sound

- **First use = model download.** The default voice engine (Kokoro) downloads about 300 MB of voice files the first time. Watch for the progress indicator and give it a minute.
- **Check the engine and voice** in Settings → Voice. Cloud engines (ElevenLabs, OpenAI) need a valid API key and internet.
- **Character voice mismatch:** if you switched engines (say Kokoro → Piper), a voice assigned to a character under the old engine won't play — the voice picker flags incompatible ones. Re-assign or use the global default.
- **Linux audio:** if nothing in the app plays sound, your system may be missing GStreamer plugins — install your distro's `gstreamer` "good/base" plugin packages.

### Microphone / speech-to-text not working

1. **OS permission first:**
   - macOS: System Settings → Privacy & Security → Microphone → allow Front Porch AI.
   - Windows: Settings → Privacy → Microphone.
   - Linux: make sure PipeWire/PulseAudio is running and the mic works in other apps.
2. **Right device selected?** Pick your actual microphone in Settings → Voice.
3. **First use downloads the speech-recognition model** (Whisper) — one-time, be patient.
4. Test with the push-to-talk mic button in the chat input; if the transcription never appears, launch from a terminal and look for the error.

### Voice call mode is unstable

Voice calls listen, wait for you to pause (~2 seconds of silence), transcribe, and send. The background-noise level is measured fresh at the start of every call.

- **Noisy room / fan / keyboard:** use a headset; lower mic gain in your OS.
- **It keeps mishearing the room as speech:** end the call and start a new one — that re-measures the background noise.
- **It cuts you off while you think:** pause less than two seconds mid-thought, or just press **Send** in the call screen to control it manually.
- **It's stuck "thinking" or "speaking":** press End Call and start over — no harm done.

---

## Your Data

### Where is my data folder?

Everything — characters, chats, memories, backups, models — lives in one folder:

- **Windows:** `Documents\FrontPorchAI\`
- **macOS / Linux:** `~/Documents/FrontPorchAI/`
- Beta/nightly builds use **`FrontPorchAI-Beta`** instead.

The database and character cards are in the `KoboldManager` subfolder (with `backups` right next to the database); your downloaded AI models are in `models`. **Copying the whole folder = a complete backup of everything.**

### Restoring from a backup

The app automatically snapshots your database **every 30 minutes** and keeps the 10 most recent snapshots *plus* one per day for the last 7 days — so you can undo this afternoon's accident or roll back to last Tuesday.

- **If the database is damaged**, a recovery screen appears at launch — click a backup to restore it. Done.
- **To restore manually or make an extra backup**, use the backup options in Settings.
- Backups live in `KoboldManager/backups/` inside your data folder, named by date and time, if you ever want to copy them elsewhere.

### Database corruption

Usually caused by a power cut, disk-full, or force-quitting during a write.

1. On the next launch the app detects the damage and shows the **backup restore screen** — newest first. Click to restore; characters, chats, and Realism state all come back.
2. If even that screen won't appear, your backups are still sitting safely in `KoboldManager/backups/` — ask on [Discord](https://discord.gg/e4tET6rpdv) and I'll walk you through it.

**Prevention:** close the app with its own close button (it shuts the database down cleanly), and don't force-kill it mid-generation.

### Beta vs stable — two apps, two data folders

Beta and nightly builds are **fully isolated** from stable on purpose: separate `FrontPorchAI-Beta` folder, separate settings, separate models. A beta can never damage your stable library — but it also means:

- Characters don't automatically appear in both. (On first launch, a beta build may offer to import a copy of your stable data.)
- Models must be downloaded in each, or copied between the two `models` folders by hand.
- To move data manually: close both apps, copy the folder contents across, relaunch.

### Missing character images

If a character's portrait shows a placeholder silhouette, the image file moved or the data folder path changed. Open the character in the editor and re-add the image — it gets copied into the right place permanently.

---

## Platform Notes

### Linux: flickering or visual glitches

Almost always Wayland. Force X11 mode:

```bash
GDK_BACKEND=x11 ./front_porch_ai
```

If that cures it, bake the variable into your launcher or desktop entry.

### Linux: AMD GPU not being used

For ROCm acceleration your user must be in the `render` and `video` groups:

```bash
sudo usermod -aG render,video $USER
```

Log out and back in, then re-run hardware detection in Settings. If ROCm won't cooperate, the Vulkan fallback still gives good GPU acceleration on most AMD cards.

### macOS: "damaged" warning, and Intel Macs

- **"App is damaged and can't be opened":** you shouldn't see this on current releases — Front Porch AI is code-signed and **notarized by Apple**, so Gatekeeper opens it cleanly. If it appears you're probably on an old build: grab the current `.pkg` installer from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases). As a last resort you can clear the quarantine flag:
  ```bash
  xattr -cr "/Applications/FrontPorchAI.app"
  ```
  (Adjust the app name/path to match yours.)
- **Intel Macs:** local AI models aren't supported (Apple Silicon's Metal acceleration is required) — the app runs fine in **Remote API mode** with OpenRouter or similar.
- **Apple Silicon tips:** Metal acceleration is automatic. Memory is shared between CPU and GPU, so close heavy apps when running larger models, and prefer Q4/Q5 versions.

### Windows: antivirus false positive

Unsigned open-source AI executables get flagged sometimes — the app and its AI engine aren't signed with an expensive corporate certificate, and antivirus vendors are jumpy about anything that runs models.

1. If SmartScreen blocks the first launch: **More info → Run anyway**.
2. If your antivirus quarantines the AI engine: add an exclusion for the `FrontPorchAI` data folder (that's where the engine lives).
3. Skeptical? Good instinct — the entire source code is [public on GitHub](https://github.com/linux4life1/front-porch-AI), and you can build it yourself.

---

## Getting More Help

- **[Discord](https://discord.gg/e4tET6rpdv)** — the fastest help, from me and from the community.
- **[GitHub Issues](https://github.com/linux4life1/front-porch-AI/issues)** — for reproducible bugs.
- **[FAQ](faq.md)** — for the "how does this work?" questions.

When you ask, include: your OS, app version, what you did, what happened, and (ideally) the terminal output. That usually turns a week of guessing into a five-minute fix.
