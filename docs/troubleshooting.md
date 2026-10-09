# Troubleshooting

When something goes wrong, this page is the fastest route back to chatting. Find your symptom, follow the fix.

> **Golden rule:** if the app is acting strange and you're about to try something drastic — don't delete anything. Your chats, characters, and a week of automatic database snapshots all live in your data folder ([where is it?](#where-is-my-data-folder)). The [Backups](#restoring-from-a-backup) system can put the database back the way it was.

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

### Web & Phone Access
- [The web app won't load on a phone or tablet](#the-web-app-wont-load-on-a-phone-or-tablet)
- [Locked out of the web login](#locked-out-of-the-web-login)

### The Stoop
- [Uploads and profile pictures are blocked](#uploads-and-profile-pictures-are-blocked)
- [Forgotten Stoop password](#forgotten-stoop-password)
- [A downloaded Place won't import](#a-downloaded-place-wont-import)

### Your Data
- [Where is my data folder?](#where-is-my-data-folder)
- [Restoring from a backup](#restoring-from-a-backup)
- [Database corruption](#database-corruption)
- [Nightly vs stable — two apps, two data folders](#nightly-vs-stable--two-apps-two-data-folders)
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

1. **Quit and relaunch — properly.** Close the app with its own close button (not force-quit), wait a few seconds, and start it again. A clean close does real work: it writes the last turn's Realism and Needs state to the database and shuts the AI engine down instead of orphaning it. Force-quitting mid-generation is how you lose the last exchange's state and end up with a leftover engine blocking the next launch.
2. **Update.** Many "known issues" are already fixed. Settings → **General** → **Check for Updates Now**. That button only appears where the app can update itself — Windows (installer builds), macOS, and the Linux **AppImage**. If you installed from `apt`, `dnf`, or the AUR, update the normal way (`sudo apt upgrade`, `sudo dnf upgrade`, `yay -Syu`). One exception to know about: the AUR package is a **full release behind** right now — `front-porch-ai-bin` is on 1.1.2 while apt and dnf serve 1.2.0, because the automatic push is being rejected at the AUR's end and I can't promise a fix date. So check your installed version rather than assuming `yay -Syu` moved you, and use the AppImage or `.tar.gz` from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases) if you need current. See the [install guide](install.md) for more.
3. **Launch from a terminal** so you can see error messages (RAG, engine, crashes):
   - **Windows:** open **cmd** (not by double-clicking the app), then:
     ```bat
     cd %LOCALAPPDATA%\Front Porch AI
     front_porch_ai.exe
     ```
     Leave that window open while you use the app — logs stream there. The GUI is a separate window; the command prompt staying “at a blinking cursor” while the app runs is normal on older builds, and on current builds you should see print lines as things happen (embeddings, RAG hits, KoboldCpp, etc.).

     If you need a console when starting from a shortcut/Explorer instead:
     ```bat
     front_porch_ai.exe --console
     ```
     That opens a dedicated console window.

     **Note:** builds before the Windows console fix could attach to cmd but still print nothing (stdout never rebound). Update to a build that includes that fix, or use a dev `flutter run -d windows` session if you’re on an older installer.
   - **macOS:** in Terminal: `/Applications/front_porch_ai.app/Contents/MacOS/FrontPorchAI` (stable package name) or `/Applications/FrontPorchAI-Rawhide.app/Contents/MacOS/FrontPorchAI` for nightlies.
   - **Linux:** run `front-porch-ai` if you installed a package, or the `front_porch_ai` binary / the AppImage directly.

   Whatever it prints when things go wrong is gold — include it if you ask for help.

---

## Startup Problems

### App won't launch

**Nothing happens, or it dies instantly.**

- **Another copy is already running.** Two copies of Front Porch AI can't share one database. If a previous run is still alive (or still shutting down), the new one can't open the file. Check your task manager for a stray `front_porch_ai` and close it.
- **Leftover AI engine from a previous run.** If the app was force-quit, KoboldCpp can be left running and hold onto its port. Clean up:
  - Windows: Task Manager → end any `koboldcpp` process (`koboldcpp.exe`, or `koboldcpp-oldpc.exe` on older CPUs).
  - macOS/Linux: `pkill -f koboldcpp`
- **Linux — missing system libraries.** Run it from a terminal; if it complains about a missing `.so` file, install the library it names (commonly GTK 3, libsecret, or GStreamer). The **AppImage** bundles everything and is the easy way out.
- **macOS — blocked by Gatekeeper.** See the [macOS note](#macos-damaged-warning-and-intel-macs).
- **Broken download/install.** Re-download the release and reinstall. Your data is safe — it lives in your Documents folder, not the install folder.

**If you get a window that says "Front Porch AI couldn't open its database"** — that's the app telling you exactly what's wrong. It's almost always one of three things: the disk is full, the app doesn't have permission to write to its data folder, or another copy is already running. Free up space, close the other copy, then reopen.

**If the web server was the problem, the app fixes it for you.** When the built-in web server fails to start, Front Porch AI turns it off so the next launch comes up clean. If your phone suddenly can't connect, that's why — re-enable it in Settings → Advanced → Web Server.

If it still won't start, **don't delete your data folder** — grab the terminal output and ask on [Discord](https://discord.gg/e4tET6rpdv).

### App crashes on startup

The most common cause is a **damaged database** — usually from a power cut or a force-quit mid-write. The good news: the app checks its database on every launch, and if it finds damage it shows a **Database Issue Detected** screen listing your automatic backups. Click one to restore — see [Database corruption](#database-corruption).

If there's no recovery screen and it just dies:

1. Launch from a terminal and read the error.
2. If the error mentions the AI engine or your GPU, switch to the **OpenAI-Compatible API** backend in Settings → Backend once you're in, or see [GPU not detected](#gpu-not-detected).
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

- **Check the logs first.** Two places show the engine's own words about what went wrong ("failed to load model", "out of memory", etc.):
  - In a chat: the **folder icon** in the row of buttons around the message box at the *bottom* of the chat — not the top bar (its tooltip says *Chat Management*) → **KoboldCpp Log**.
  - Settings → **Backend** → the **Process Logs** section at the bottom.
- **Engine not downloaded / half-downloaded:** Settings → **Backend** → **Koboldcpp Backend**. If it says *Status: Missing*, press **Download**. If it's there but old, the same button offers **Check for Updates** / **Update to v…**.
- **Something is already using its port** (5001). Usually a leftover engine from a crashed session:
  - Windows: `taskkill /F /IM koboldcpp.exe` — if that reports the process wasn't found, run `taskkill /F /IM koboldcpp-oldpc.exe` as well. On a CPU without AVX2 the app uses the `oldpc` build, so it's that name holding the port.
  - macOS/Linux: `pkill -f koboldcpp`
- **The model file can't actually be opened.** Cloud-synced folders are a classic trap: a OneDrive, iCloud Drive, or Dropbox "online-only" file looks present in your file browser but its contents aren't on the device, so the engine exits with a bare error code. The app now checks this before launching and explains it. The fix: right-click the models folder → **Always keep on this device**, or move your models somewhere outside the synced folder.
- **GPU driver trouble:** see [GPU not detected](#gpu-not-detected).
- **Intel Mac:** local models aren't supported on Intel Macs — use the **OpenAI-Compatible API** backend instead.

### Generation is extremely slow

Slow almost always means **the model doesn't fit in your GPU's memory**, so it's partly running on the much slower CPU:

1. **Leave Graphics memory on Automatic** (Settings → Advanced → Hardware & GPU). KoboldCpp then works out how much of the model fits on your graphics card and puts the rest in system memory. If you switched on **Set layers myself**, the number you typed may be too high: lower it, or switch back to Automatic.
2. **Use a smaller or more compressed model.** A Q4 version of a model needs roughly half the memory of a Q8 with barely any quality loss. **Manage Models → Search / Download** shows a size and VRAM estimate on every file, colour-coded as fits / tight / too large, before you download.
3. **Lower the context size.** Big context windows (16k+) eat GPU memory even before the model writes a word. It's the **Context Window** card in the same section, with quick-pick chips.
4. **Check the right GPU is being used** — on laptops and multi-GPU machines the app can be pointed at the wrong one. Settings → Advanced → **Advanced Launch Options** → **GPU ID**.
5. **Close other heavy apps** — games and browsers with lots of tabs compete for the same GPU memory.

Extras worth checking (Settings → Advanced → **Advanced Launch Options**, plus the Context Window card above it): **Flash Attention** is on by default and worth leaving on; **KV Cache Quantization** trades a sliver of quality for a large VRAM saving; and **Lock Weights in RAM (mlock)** stops the system from paging the model out to disk, which is what turns 20 tokens a second into half a token a second when RAM runs short. On Linux mlock needs root or `ulimit -l unlimited`, so if you haven't set that it simply won't take effect. All three apply on the next backend restart.

**If you see a "Slow performance expected on this PC" banner**, the app has worked out that this machine has no NVIDIA GPU *and* a CPU without AVX2. Local models will genuinely crawl no matter what you tune — a remote API is the realistic fix.

### Empty or instantly-finished replies

The character says nothing, or the reply ends after a word or two:

- **A stop sequence is firing immediately.** Stop sequences tell the model where to stop writing; an overly aggressive one (like a bare newline) can stop it instantly. The app already adds its own sensible ones behind the scenes — your persona's name, the character names — so you rarely need many of your own. Review yours in the chat sidebar's **Main Settings** → **Chat Settings** → **Stop Sequences**, or globally in Settings → **Generation** → **Stop Sequences**, and remove suspicious entries.
- **The context is completely full.** If the conversation plus character info exceeds the model's context window, there's no room left to reply. Lower what's injected or raise context size.
- **The model file is broken or badly converted.** Test with a well-known model — if that one works, the other file is the problem.
- **Test with a remote API** — if remote works and local doesn't, the issue is the local model or engine, not your character or settings.

### Model won't load — out of memory

- **Lower the context size first** — context can cost gigabytes before the model even loads.
- **Lower GPU Layers** — the rest of the model runs on CPU (slower, but it loads).
- **Pick a more compressed version** (Q4 instead of Q6/Q8) or a smaller model.
- After an out-of-memory crash, stop the engine, wait a few seconds, then start it again so it comes up clean (Settings → Backend → **Stop Backend** / **Start Backend**).

The app estimates memory needs before you download a model — trust the estimate; if it says "tight", it will be.

### GPU not detected

- **NVIDIA:** run `nvidia-smi` in a terminal. If that fails, your driver needs installing/updating — reboot afterwards, then relaunch Front Porch AI (it re-detects your hardware on every launch).
- **AMD on Linux:** see [the AMD note](#linux-amd-gpu-not-being-used) — it's almost always group permissions.
- **AMD on Windows / Intel GPUs:** the app uses Vulkan, which works out of the box with current drivers.
- **Apple Silicon:** Metal acceleration is automatic — nothing to configure.
- **Intel Macs:** local models are not supported (no Metal GPU support for this workload) — the app tells you, but you're the one who switches: Settings → **Backend** → **OpenAI-Compatible API**.

**To see what the app actually chose:** Settings → Advanced → Hardware & GPU shows a line like *Acceleration: Automatic — Vulkan (AMD GPU detected)*. If it says **Manual** and picked the wrong thing, press **Reset to Automatic**. The manual chips live under **Advanced: manual backend override** in the same place if you really want to force one.

### Realism evaluations come back empty

Some local models struggle with the Realism Engine's short background questions and return nothing (bond/trust/mood chips stop updating). Fixes, in order of effectiveness:

1. Turn on **One-Shot Eval** — in a chat, open the sidebar's **Character State** section and press the sliders icon (*Simulation settings*). One combined question instead of several works better on many models. It's marked experimental and can be a little less precise below about 8B parameters, but it's usually the difference between "works" and "nothing".
2. Try a different model — evaluation reliability varies a lot between models and compression levels.
3. Remote APIs essentially never have this problem, if you have one configured.

The conversation itself keeps working even when evaluations fail — you just lose that turn's state updates.

**If an evaluation gets stuck**, the processing panel has a red **Cancel Realism** button. Pressing it aborts the evaluation and returns you to the chat; nothing is damaged.

---

## Chat Problems

### Replies get cut off mid-sentence

- **Raise Max Output Tokens** — in the chat sidebar's **Main Settings** → **Chat Settings**, or globally in Settings → **Generation** → **Output Limits**. For long roleplay scenes, 400–600 is common.
- **Press Continue** on the truncated message — the down-arrow button in the message's button row (tooltip: *Continue generation*) picks up where it stopped.
- **A stop sequence fired mid-reply** — e.g. the character's name with a colon appearing inside the text. Trim aggressive stop sequences.
- If it happens constantly in very long chats, the context is overflowing — the oldest messages get trimmed to make room, and some models handle that gracelessly. Raising the context size helps, and the Journal's "Where we are" recap keeps the story straight even when old messages fall out.

### Memory / RAG isn't working

Long-term memory pulls older parts of a long conversation back into context by turning text into searchable meaning. That conversion happens right inside the app — no internet, nothing extra to install.

**Where the controls are depends on the chat, and this is the single most common reason people think memory is broken:**

Memory (RAG) has a master switch that is off until you turn it on and download the embedding model. Once it is on, group chats use it too and are enabled by default; the sidebar Memory (RAG) panel itself only appears in one-on-one chats, and groups are configured under Group Settings → Memory & RAG.

- **1:1 chats:** the chat sidebar, under **Journal & Memory** → **Memory (RAG)**. That panel is where the master switch lives, so if you only ever chat in groups, open a one-on-one chat once to turn it on — or use the web/mobile UI, which carries the same switch.
- **Group chats:** the group's own controls live in **Group Settings** (the button just below **Main Settings** at the top of the chat sidebar) → the **Memory & RAG** tab. That's where the group's on/off switch, **Memories per turn**, the **RAG memory budget**, and a per-character priority slider are. That switch only ever takes memory *away*: turning it off skips retrieval for this group even when the master switch is on, and turning it on can't make up for a master switch that's still off.

A few things can trip it:

- **Check its status.** In the 1:1 panel, under the toggle there's a coloured dot: *Memory engine ready*, *Starting…*, or *Model not downloaded*.
- **First use downloads a model** — about 550 MB, once, with a progress bar. Give it time on a slow connection.
- **Stuck?** Toggle Memory (RAG) off and back on; if it stays stuck, restart the app.
- **Memories exist but aren't recalled:** retrieval needs *meaningful* content to match on — one-word messages don't give it much. In the 1:1 panel, **Settings** (the sliders icon) raises **Memories per turn** and the **Window size** of each remembered chunk; in a group, **Memories per turn** is in the **Memory & RAG** tab. Window size is one global setting shared by every chat, so changing it in one place changes it for all of them.
- **Waiting for a character to bring up something from an *earlier chat*? That won't happen, on purpose.** A character's own memories are scoped to the chat they were made in — a match from a different chat with that same character is deliberately skipped, so a fresh start can't drag in a storyline or a location you left behind. The Journal's memory cards work the same way. Two things *are* meant to cross chats: the opt-in **Sources** list in the 1:1 panel (press **Sources** and tick another character to let this one draw on *their* memories), and the Data Bank, which exists to be shared knowledge.

---

## Voice Problems

### TTS not producing sound

- **First use = model download.** The default voice engine (Kokoro) downloads roughly 380 MB of voice files the first time. Watch for the progress indicator and give it a minute.
- **Check the engine and voice** in Settings → **Voice & Media** → **Text-to-Speech** → **Configure**. Cloud engines (ElevenLabs, OpenAI) need a valid API key and internet.
- **A character suddenly sounds "generic".** Characters can carry their own voice (either assigned when you built a group, or baked into the card you imported). If that voice belongs to a different engine than the one you're using now — say the card wants a Kokoro voice while you've switched to Piper — the app can't play it and quietly uses your global voice instead. Either switch the engine back, or set a global default you're happy with under **Text-to-Speech** → **Configure**. Per-member voices for a group are picked on the group setup screen, and those dropdowns only ever list voices that work with your current engine.
- **A custom Piper voice won't import.** Front Porch AI can import raw Piper voices (desktop only — there's deliberately no web importer). Two rules trip people up: the `.onnx` model needs its matching `.onnx.json` config sitting **next to it** with the same name, and a voice whose name is already installed is refused — rename the file to bring it in under a different name. The import button is **Add custom voice**, top-right of the **Voice Model Browser**.
- **Linux audio:** if nothing in the app plays sound, your system may be missing GStreamer plugins — install your distro's `gstreamer` "good/base" plugin packages.

### Microphone / speech-to-text not working

1. **OS permission first:**
   - macOS: System Settings → Privacy & Security → Microphone → allow Front Porch AI.
   - Windows: Settings → Privacy → Microphone.
   - Linux: make sure PipeWire/PulseAudio is running and the mic works in other apps.
2. **Right device selected?** Settings → **Voice & Media** → **Voice Input (STT)** → pick your actual microphone (or leave it on *System Default*).
3. **First use downloads the speech-recognition model** (Whisper) — one-time. The size depends on which you pick: Tiny (~105 MB, fastest), Base (~155 MB, balanced), or Small (~360 MB, best accuracy). If transcription is inaccurate, moving up a size is the single biggest improvement.
4. Test with the push-to-talk mic button in the chat input; if the transcription never appears, launch from a terminal and look for the error.

### Voice call mode is unstable

Voice calls listen, wait for you to pause (about 2 seconds of silence), transcribe, and send. The background-noise level is measured fresh during the first second and a half of every call — that's the "Calibrating…" moment.

- **Noisy room / fan / keyboard:** use a headset; lower mic gain in your OS.
- **It keeps mishearing the room as speech:** end the call and start a new one — that re-measures the background noise.
- **It cuts you off while you think:** pause less than two seconds mid-thought, or press **Send** in the call screen to control it manually. **Mute** stops it listening entirely while you deal with something else.
- **It's stuck "thinking" or "speaking":** press **End** and start over — no harm done.

---

## Web & Phone Access

### The web app won't load on a phone or tablet

The desktop app serves the web/mobile UI itself, on port **8085** by default. Turn it on in Settings → **Advanced** → **Web Server** → **Enable Web Server**; a guided setup walks you through how to reach it.

When the browser just spins:

- **Check it's actually running.** That same panel shows **Status: Running** or **Stopped**, and — once it's up — the exact address to type, like `http://192.168.1.20:8085`.
- **macOS 15 and newer asks permission.** The first time the server serves over your network, macOS shows a **Local Network** prompt. If you dismissed it, the phone will never connect: System Settings → Privacy & Security → **Local Network** → switch Front Porch AI on.
- **Firewalls.** On Windows, allow Front Porch AI through Windows Defender Firewall on **private** networks. On Linux, open the port in `ufw`/`firewalld` if you run one.
- **Same network?** Phone on mobile data, or on a "guest" Wi-Fi network that isolates devices, won't see your computer. For access from outside the house, use the Tailscale option in the guided setup rather than opening your router.
- **The server turned itself off.** If a previous start failed, the app disables the web server so it can't wedge your next launch. Flip the switch back on.
- **Port already taken?** Change the **Port** field in that panel and reconnect using the new number.

### Locked out of the web login

The web interface has its own username and password, separate from everything else — and **your desktop is the recovery key**. Settings → **Advanced** → **Web Server** → **Login**:

- **Sign out all devices** — kicks every browser session without changing your password. Good if you left yourself signed in somewhere you shouldn't have.
- **Reset web login…** — erases the web username, password and 2FA and signs everything out. The next browser visit shows the first-run setup page so you can create a new login. Your characters, chats and settings are untouched.

Day-to-day changes (username, password, two-factor) are made from the web UI's own Account page.

---

## The Stoop

The Stoop is the built-in community hub for sharing character, group, and Place cards. It's part of the normal app — sidebar → **The Stoop** — and it's opt-in and 18+.

### Uploads and profile pictures are blocked

**Confirm your email.** Browsing and downloading work the moment you sign in, but a confirmed email address is required for uploading and sharing your own cards, and for setting a profile picture.

If you never got the message, The Stoop shows an amber banner with a **Send it again** button. Check your spam folder first — and if you just asked, give it a couple of minutes, because repeat requests are rate-limited and the app will tell you to wait.

### Forgotten Stoop password

On the sign-in screen, press **Forgot password?**, enter your account email, and press **Email me a link**. The link opens in your browser and is good for 45 minutes. For your privacy the app gives the same answer whether or not the address has an account, so a "sent" message isn't proof the address is registered.

### A downloaded Place won't import

Places (Worlds) can be shared on The Stoop and import themselves when you download them — lore, climate, traits and cover art all in one `.fpworld` package.

Importing a `.fpworld` file needs **Front Porch AI 1.2 or newer**. On 1.1.2 and older the format simply isn't understood, so a downloaded Place won't open. Update and try again. (Places themselves aren't new — they've been in the app since 1.0. It's the portable `.fpworld` package, the thing that lets a Place travel between installs and across The Stoop, that arrived in 1.2.) To import one you were sent as a file instead, use the import button on the **Worlds** page.

---

## Your Data

### Where is my data folder?

Everything — characters, chats, memories, backups, models — lives in one folder:

- **Windows:** `Documents\FrontPorchAI\`
- **macOS / Linux:** `~/Documents/FrontPorchAI/`
- Nightlies use **`FrontPorchAI-Beta`** instead (leftover name).

**Not sure? The app will tell you.** Settings → **Advanced** → **Storage Configuration** shows the exact **Data Directory** path. The pencil icon next to it relocates your database, characters, chats, worlds, models and the AI engine to a new home (an external drive, a bigger disk) and reopens everything from there — no restart, no manual copying.

Inside the folder: the database and your character images are under `KoboldManager` (with `backups` sitting right next to the database); downloaded AI models are in `models`; the AI engine is in `koboldcpp_bin`; and `chats`, `worlds`, `groups` and `custom_backgrounds` hold the rest. **Copying the whole folder = a complete backup of everything.**

**If you pointed the data folder at a drive that isn't plugged in**, don't re-import anything and don't change the setting. When the chosen folder can't be written to at launch, the app quietly uses the default location for that session instead of refusing to start — so things can look empty or missing. Your setting is *not* overwritten; reconnect the drive and relaunch.

### Restoring from a backup

The app automatically snapshots **the database** — your chats, messages, character entries, Realism state and worlds — **every 30 minutes**, and keeps the 10 most recent snapshots *plus* one per day for the last 7 days, so you can undo this afternoon's accident or roll back to last Tuesday.

- **If the database is damaged**, a recovery screen appears at launch — click a backup to restore it. Done.
- **To restore manually, or to make an extra backup before doing something risky**, open **Backups & Restore** in the sidebar. Each snapshot is listed with its date and size, with **Restore** and delete buttons.
- Restoring reloads your library on the spot — **no app restart needed**. If the reload doesn't take, the app tells you so and asks you to close and reopen Front Porch AI; the restored database is already written to disk at that point, so it comes back up restored.
- **A snapshot is the database file and nothing else.** Portraits and other picture files sit beside the database on disk and are never inside a backup. The practical consequence: a backup will **not** bring back a character you deleted, because deleting one also removes its image file, and no restore puts that back. If there's any chance you'll want a character again, right-click its card on the home grid and **Export PNG** first.
- Backups live in `KoboldManager/backups/` inside your data folder, named by date and time, if you ever want to copy them elsewhere.

> **Nightlies:** the **Backups & Restore** page opens but its contents are replaced by a notice, so there is no way to browse or roll back a snapshot there. The automatic snapshots themselves keep running — the 30-minute timer fires on every build. The launch recovery screen still works, so a damaged nightly database can still be rescued, and nightly snapshots pile up as normal in `FrontPorchAI-Beta/KoboldManager/backups/`.

### Database corruption

Usually caused by a power cut, disk-full, or force-quitting during a write.

1. On the next launch the app runs an integrity check and, if it finds trouble, shows a **Database Issue Detected** screen listing your backups newest-first. Click one to restore; characters, chats, and Realism state all come back. There's also a **Continue Without Restoring** option if you'd rather look around first.
2. If even that screen won't appear, your backups are still sitting safely in `KoboldManager/backups/` — ask on [Discord](https://discord.gg/e4tET6rpdv) and I'll walk you through it.

**Prevention:** close the app with its own close button (it shuts the database down cleanly), and don't force-kill it mid-generation.

### Nightly vs stable — two apps, two data folders

Nightlies are **fully isolated** from stable on purpose: separate `FrontPorchAI-Beta` folder (leftover name), separate settings, separate models. A nightly can never damage your stable library — but it also means:

- Characters don't automatically appear in both. On its first launch, a nightly offers to import a copy of your stable data; take it or skip it, but it's a *copy* either way — the two never sync afterwards.
- Models must be downloaded in each, or copied between the two `models` folders by hand.
- To move data manually: close both apps, copy the folder contents across, relaunch.
- On nightlies the Backups & Restore page opens but its contents are replaced by a notice, so there is no way to browse or roll back a snapshot there. The automatic snapshots themselves keep running (see above).

### Missing character images

If a character's portrait shows a placeholder silhouette, the image file moved or the data folder path changed. Portraits are managed in the **Avatar Gallery** — on the home grid, **right-click** the character's card (that's the only way to open its menu; there's no ⋮ button) and choose **Avatar Gallery**. In a chat it's also under **Main Settings** at the top of the sidebar. Add the picture again there and it's copied into the right place permanently. The Edit Character screen shows the portrait but deliberately can't change it, so nothing is destroyed by accident.

If a lot of things look wrong at once — leftover entries from characters you deleted, portraits pointing nowhere — run Settings → **Advanced** → **Database Maintenance** → **Scan & Clean**. It finds orphaned avatars, objectives, data bank entries and memory embeddings and repairs broken cross-references, and it shows you what it found before changing anything.

---

## Platform Notes

### Linux: flickering or visual glitches

Almost always Wayland. Force X11 mode:

```bash
GDK_BACKEND=x11 ./front_porch_ai
```

If that cures it, bake the variable into your launcher or desktop entry.

### Linux: AMD GPU not being used

AMD cards are accelerated with **Vulkan** by default, which works well on most consumer hardware and needs nothing configured. For that (and for ROCm) your user must be able to reach the GPU device nodes, which means being in the `render` and `video` groups:

```bash
sudo usermod -aG render,video $USER
```

Log out and back in, then relaunch the app.

**ROCm is deliberately never chosen automatically** — "the driver offers ROCm" and "ROCm works with this card" are different questions, and guessing wrong means the engine crashes at launch instead of just being slower. It's an opt-in under Settings → Advanced → Hardware & GPU → **Advanced: manual backend override**. You don't need to install ROCm yourself: picking it downloads KoboldCpp's ROCm build, which brings its own, and the status shows the download. If the chip is greyed out, or the app says your account can't use the card yet, **Why can't I use ROCm?** next to it says what to do.

### macOS: "damaged" warning, and Intel Macs

- **"App is damaged and can't be opened":** you shouldn't see this on current releases — Front Porch AI is code-signed and **notarized by Apple**, so Gatekeeper opens it cleanly. If it appears you're probably on an old build: grab the current `.pkg` installer from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases). (The `.pkg` is now the only macOS download; the old unsigned `.dmg` is retired.) As a last resort you can clear the quarantine flag:
  ```bash
  xattr -cr "/Applications/FrontPorchAI.app"
  ```
  (Adjust the app name/path to match yours.)
- **Intel Macs:** local AI models aren't supported (Apple Silicon's Metal acceleration is required). The app greys out the **Local (KoboldCPP)** option and shows a banner saying so — but it does *not* switch you over by itself, so nothing works until you make the change: Settings → **Backend** → **OpenAI-Compatible API**, then fill in your API details. Everything else in the app runs normally.
- **Apple Silicon tips:** Metal acceleration is automatic. Memory is shared between CPU and GPU, so close heavy apps when running larger models, and prefer Q4/Q5 versions.

### Windows: antivirus false positive

Unsigned open-source AI executables get flagged sometimes — the Windows build and its AI engine aren't signed with an expensive corporate certificate, and antivirus vendors are jumpy about anything that runs models.

1. If SmartScreen blocks the first launch: **More info → Run anyway**.
2. If your antivirus quarantines the AI engine: add an exclusion for your `FrontPorchAI` data folder — the engine lives in `FrontPorchAI\koboldcpp_bin`.
3. Skeptical? Good instinct — the entire source code is [public on GitHub](https://github.com/linux4life1/front-porch-AI), and you can build it yourself.

---

## Getting More Help

- **[Discord](https://discord.gg/e4tET6rpdv)** — the fastest help, from me and from the community.
- **[GitHub Issues](https://github.com/linux4life1/front-porch-AI/issues)** — for reproducible bugs.
- **[FAQ](faq.md)** — for the "how does this work?" questions.

If you run a **nightly** and one of the built-in engines fails — Kokoro or Piper voices, voice input, character expressions, memory embeddings, or Draw Things image generation — you'll get an amber notice with a **Copy details** button. Please press it and paste the result on Discord. Those notices only appear on early builds, and they exist precisely so a quietly broken feature doesn't stay quiet.

When you ask, include: your OS, app version, what you did, what happened, and (ideally) the terminal output. That usually turns a week of guessing into a five-minute fix.
