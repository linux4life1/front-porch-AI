# Release Notes

Front Porch AI ships often: a stable release every few weeks, patch releases in between, and a nightly Rawhide build most days.

**The current stable release is v1.3.1, "Clock In", released 2026-08-26.**

This page is the long-form history — the headlines of every release, newest first. The [GitHub Releases page](https://github.com/linux4life1/front-porch-ai/releases) is always the complete and most up-to-date record, and it is also where the nightly builds live.

**Nightly builds** (Rawhide) keep their data in a completely separate `FrontPorchAI-Beta` folder (leftover name) with their own settings, so they never touch a stable installation.

---

## Table of Contents

- [v1.3.1 — Clock In](#v131--clock-in)
- [v1.3 — Check Your Pockets](#v13--check-your-pockets)
- [v1.2 — Occupy Mars](#v12--occupy-mars)
- [v1.1 Series](#v11-series)
- [v1.0 — Stay Awhile and Listen](#v10--stay-awhile-and-listen)
- [Things Named Below That No Longer Exist](#things-named-below-that-no-longer-exist)
- [v0.9.9 Series](#v099-series)
- [v0.9.8 Stable](#v098-stable)
- [v0.9.8-Beta Series](#v098-beta-series)
- [v0.9.7 Series](#v097-series)
- [v0.9.6 Series](#v096-series)
- [v0.9.0 – v0.9.5](#v090--v095)
- [v0.8 Series](#v08-series)
- [Earlier Versions (v0.7 and below)](#earlier-versions-v07-and-below)
- [How to View Full Changelog](#how-to-view-full-changelog)

---

## v1.3.1 — Clock In

**Released:** 2026-08-26 (v1.3.1) — current stable

- 🕘 **They clock in** — occupation, which weekdays, hours on the job. Skip a turn and the banner says they're at work. A night skip lets them rest.
- 🕰️ **Time is said first, then they write** — the prompt tells them what time it is; after the reply the clock decides how much passed. Continue does not tick.
- 👤 **With you is a yes or a no** — scored after they speak, not assumed.
- 🛠️ **Built on Flutter 3.47** — current stable Flutter. macOS 12 Monterey is the floor.

Fixes and improvements in the same cut: Chat History rename no longer wipes Porch Life; Continue keeps the speaker; group gifts rewind on both sides; deleting a group or character takes diary, growth, and Data Bank with them; custom seasons on Places; gist-first memory; alternate greetings seed Realism and Needs; phone fork, sampler row, and honest Stoop groups/worlds; Tailscale login asks for the web password; light-mode paper is readable.

---

## v1.3 — Check Your Pockets

**Released:** 2026-08-16 (v1.3.0)

- 🎁 **Pockets & Wardrobe** — they have pockets, clothes, and a set-aside pile. Hand them something, take it back, they can pass it to someone else. Authors can send them into a chat already dressed and carrying things. The Journal keeps a Belongings tab of where things went. Own switch — does not need the Realism Engine.
- ✨ **AI Enhance** — grow a character from a real chat. Walks you through it, and can bring those chats along.
- 🏡 **Porch Life** — one Settings home for every living-character switch, instead of hunting them across the app.
- 🎛️ **À la carte** — Journal, Chaos / Chance Time, the story clock, Pockets, and Objectives each have their own switch. Turn on what you want. Realism Engine is no longer the master key.
- 💛 **Likes & Dislikes** — give them tastes (thunderstorms, being interrupted) and they act on them.
- 🔥 **Intimate preferences get said** — not just scored in the background.
- 🌱 **Ambitions drive their quests** — long-term goals pick the next quest instead of sitting unused on the card.
- 🌧️ **A bad day that isn't about you** — optional, off by default. They can arrive tired, hungry, or weather-beaten from their own life.
- 📦 **Take a chat with you** — export as a Front Porch chat file or SillyTavern JSONL.
- ✍️ **Impersonate on the phone** — the same wand as desktop.

---

## v1.2 — Occupy Mars

**Released:** 2026-08-01 (v1.2.0)

- 🌍 **Worlds you can author, then share.** Places have been in the app since 1.0 — what 1.2 adds is a real climate and a way to move them between installs. Rename a place's weather conditions, give them emoji and flavor, set the temperature bands, and choose the **atmosphere and gravity**. Mars no longer comes with breathable air; volcano heat and Martian cold are real to the engine, and characters feel them, dress for them, and complain about them. Finished a place? Post it to The Stoop just like a character — upload and download both work — and a new chat inherits its character's world automatically. Places travel as `.fpworld` packages, and **opening one needs Front Porch AI 1.2 or newer**; older installs can't import them.

- 🗂️ **Folders finally hold group casts.** Groups can be dragged into folders and moved through the folder hierarchy exactly like individual characters always could, including from the multi-select toolbar.

- 🏡 **Profiles and avatars on The Stoop.** Your name now opens a real profile page: your picture, when you joined, followers and lifetime stats, a bio and up to four links, with your uploads underneath as an art grid. Every other creator gets the same page. Profile pictures require a **confirmed email address**, so drive-by accounts can't post pictures at all — the same confirmation is what unlocks sharing your own cards.

- 💾 **Restoring a backup no longer needs a restart.** The app picks the restored database straight back up instead of leaving parts of itself talking to the old one. If that hand-off ever fails it tells you so and asks you to close and reopen Front Porch AI — the backup is already on disk at that point either way.

Plus the usual bug fixes and speed improvements ported down from the nightly Rawhide builds.

---

## v1.1 Series

**Date range:** 2026-07-28

**v1.1.2 — "Faces That Stick" (2026-07-28)** — Avatar and gallery fixes, plus stability polish. The starred face is now the card face everywhere, placeholders get replaced by real art, a first upload is portrait-only, and gallery deletes refresh the right tile. "Our Story" no longer spins forever when opened mid-chat. Remote-backend users no longer download a local KoboldCpp binary they will never use. Hub downloads carrying a V2 `character_book` show their lore again. Stop truly ends a turn, an out-of-character time skip owns the clock instead of double-advancing it, and needs chips stop inventing full-value changes when a baseline was missing.

**v1.1.1 — Linux hotfix (2026-07-28)** — v1.1.0 shipped without its bundled SQLite engine, so Linux users saw "libsqlite3.so is missing" and were told their database was corrupted. **No data was ever damaged** — the app simply couldn't open it, and updating fixed it. Every Linux package was affected (`.deb`, `.rpm`, AppImage, tarball, AUR); macOS and Windows never were. The release pipeline now refuses to publish a Linux build that can't reach its database engine.

**v1.1.0 — "Weather Report" (2026-07-28)** — the "Living Time" wave, brought down from the nightlies.

### What v1.1 added

- 🌦️ **Real story weather, hour by hour** — every chat gets weather that changes through the day: fog burns off mid-morning, rain rolls in after lunch, storms break in the evening. Characters feel the shift mid-conversation, see fronts coming, and dress for the cold in words rather than numbers. Real temperatures with a daily curve show on the sidebar chip, in °C or °F.
- 💤 **Dreams** — when a story night passes, your character dreams a short, hazy scene woven from their Journal memories, mood, and the weather outside. Dreams land in the diary and can resurface later.
- 📖 **"Our Story"** — a browsable milestones timeline: first bond tier, trust repaired, promises kept and broken, objectives completed, with tap-to-jump receipts. On desktop and web.
- 🤝 **Promises leave scars** — commitments either of you make go into a ledger. Kept ones warm trust, broken ones crater it, open ones color the next reply.
- 🗓️ **A real story calendar** — chats run on a genuine calendar date and clock, with seasons that follow the actual month.
- 🌱 **Ambitions** — long-term goals that surface in the sidebar and pull scenes forward.
- 👋 **They notice when you've been gone** — come back after days away and you get a "Previously on…" recap; optionally the character mentions the absence in their own voice, once.
- 📚 **Turn any chat into a story** — one tap distills a session into a Porch Stories project, with a faithful mode that forbids inventing or reordering events.
- 🎨 **Per-chat visual themes** — ten presets (Galactic, Noir, Sakura, Steampunk…) plus full color customization per chat, on desktop and web alike. Community-contributed by dazpants1.
- 🧙 **An overhauled AI character creator** — a voice-first interview that asks better questions, three-stage lorebook generation with interconnected entries, optional dice and pick macros, and a veto gate on the portrait before the expression pack spends your time.
- ✂️ **Output Sanitizer** — automatic find & replace on model output: exact text or lightweight wildcards with capture groups, per-chat overrides, optional retroactive cleanup of saved history. Community-contributed by S-A-M-F.
- 🎙️ **Bring your own Piper voices** — import a Piper voice exactly as it downloads (the `.onnx` model with its `.onnx.json` config sitting next to it) and it appears alongside the built-in voices everywhere, with no conversion step of your own. Desktop-only by design — there is no web importer. (The v1.2 notes announced this as new; it actually landed here, in 1.1.0.)
- 🧠 **Deeper memory** — memories can hide verbatim recall behind them, retrieval stops parroting your own phrasing back, and duplicates stop crowding the prompt.
- 🩹 **A batch of long-standing bugs went down** — bond scores no longer quietly inflate on re-open, stale per-chat sampler overrides are healed automatically, Chaos Mode survives the session list, the speech-rate slider works for Piper and Kokoro, and same-name imports ask "keep both or replace?" instead of clobbering.
- 📦 **macOS: one clean installer** — the signed, Apple-notarized `.pkg` became the only macOS download; the legacy unsigned `.dmg` was retired.

---

## v1.0 — Stay Awhile and Listen

**Released:** 2026-07-18 (v1.0.0)

Five months and 1,600+ commits after the first push on 2026-02-14. Everything in 1.0 had been proving itself in nightly builds for months and landed in stable at once.

- 🏡 **The Stoop — a community character hub, built right in.** Browse, share, and download character and group cards without leaving the app, or from any browser at [hub.frontporchai.app](https://hub.frontporchai.app). Whole group casts travel with their lorebooks and realism state intact. It is opt-in and 18+, and the rest of the app stays entirely local.
- 📔 **Characters keep a real diary (The Journal).** Promises made, things they learned about you, moments that mattered — each memory stamped with the feeling behind it. Strong memories linger; faint ones can resurface when the conversation drifts back near them, once memory embeddings (RAG) are switched on. You can read it, edit it, and pin what matters. Nothing ever leaks between chats.
- 🌱 **Growth Rings — character growth you can see.** Instead of silent personality rewrites, every real change becomes a visible "ring" with receipts you can tap to jump to the moment it happened. Recurring growth becomes permanent; stale growth fades into a viewable past.
- 🎭 **One chat, a cast that changes.** Turn a solo chat into a group in place with `/join`, wave someone off with `/exit` (undo included), and collapse back to a clean one-to-one. Realism, needs, and memory carry across both ways.
- 🧭 **Lorebooks work the way their authors wrote them.** Import SillyTavern, Chub, NovelAI, AgnAI and RisuAI books through a preview wizard; conditional triggers, timers, chains, variety groups, and stateful macros all actually run.
- 🖼️ **The Image Studio was rebuilt.** Pick a subject and go; generate full expression packs from one portrait with an AI quality check, paint the current scene with `/image` right in chat, use reference images with a denoise slider, and connect ComfyUI with no node graphs.
- 📸 **Send your character a photo and they see it.** Vision models react to your pictures in character, any GGUF can gain sight via its mmproj file, and a fully local Photo Understanding helper covers text-only models. No cloud.
- 📱 **The web and phone app was rebuilt** — a proper installable app in the same warm look: chat, characters, stories, images, and the full Stoop from your phone. Much faster over slow connections, and it recovers by itself after your phone sleeps.
- 🛋️ **The warm-porch redesign** — the whole app speaks one cozy design language, and light mode finally looks right everywhere.
- 🧠 **The Realism Engine got deeper and far more reliable** — readings arrive as structured tool calls on capable models so chips stop stalling, characters hear their state as natural language instead of stat dumps, group chats match one-to-one exactly, and self-chosen goals become real quests with steps.
- ☕ **Your character keeps living while you're away** — turn on Dynamic Responses (or type `/afk`) and they quietly get on with their day, with time and needs following along.
- ⚡ **Faster, and honest about what it's doing** — long local chats reply dramatically sooner, the status bar shows real progress, your sampler settings and stop strings actually reach the model, and thinking models genuinely think on local KoboldCpp.
- 💾 **Smarter local backups replaced Cloud Sync** — rolling half-hourly and daily snapshots of your database, written by the database engine itself, with one-click restore. It is a database backup, not a whole-library one: the character image files on disk are not inside it, so a restore is not a way to undo deleting a character. Old PCs without AVX2 are supported automatically too.
- 🧹 **No more Python helpers.** Text-to-speech, speech-to-text, emotion classification and memory embeddings all moved inside the app, so there is no bundled helper program left to start and you never need to install Python. The local model itself is still its own program: on the default setup Front Porch AI downloads KoboldCpp and runs it as a local server, which you start and stop from inside the app.

---

## Things Named Below That No Longer Exist

Everything from here down is a record of what shipped at the time, not a description of the app today. A few things those entries mention have since been removed, so don't go hunting for them:

- **Cloud Sync is gone.** Automatic local backups replaced it in 1.0 — rolling half-hourly and daily snapshots of the database, with one-click restore. On nightlies the Backups & Restore page opens but its contents are replaced by a notice, so there is no way to browse or roll back a snapshot there. The automatic snapshots themselves keep running.
- **The separate helper programs are gone.** Earlier versions started standalone Python and Rust programs for speech, emotion classification, and memory embeddings. As of 1.0 all of that runs inside the app itself.
- **Summary and Fact Extraction became The Journal**, a real per-chat diary. Journal memories never cross between chats.
- **Character evolution became Growth Rings**, which show you what changed and why instead of silently rewriting the character. Scenario evolution retired along with it.
- **The old six-turn time gate is gone.** The story clock now advances on every turn.
- **The unsigned macOS `.dmg` is retired.** The signed, Apple-notarized `.pkg` is the only macOS download.

---

## v0.9.9 Series

**Date range:** 2026-06-13 – 2026-06-23

**v0.9.9.1.3 (2026-06-23)** — Character creation works on the native KoboldCpp backend; generate character avatars on the local backend too; Image Studio prompt fields no longer type backwards; cleaner large-model loading with more accurate VRAM estimates.
**v0.9.9.1.2 (2026-06-21)** — AI Character Creator fully restored and overhauled (the previous stable shipped it generating fake results that never saved), reliable first message and a portable `{{char}}` macro, bulk import of Backyard AI characters, subfolder phantom-duplicate fix.
**v0.9.9.1.1 (2026-06-20)** — Windows installer fixes: correct install folder, and stable/Beta/Nightly can coexist. Much faster macOS builds.
**v0.9.9.1 (2026-06-20)** — the largest release of the series: the Image Studio, plus a big reliability pass on Realism and Needs (details below).
**v0.9.9.0.1 (2026-06-13)** — Patch for a 0.9.9 Windows installer regression: stable paths are used explicitly, and bad desktop shortcuts left by the 0.9.9 installer are removed automatically. All user data stayed safe throughout.
**v0.9.9 (2026-06-13)** — Windows build fix for an MSVC deprecation.

**Key additions in v0.9.9.1**
- 🎨 **A first-class Image Studio** — one integrated studio instead of popups and separate dialogs, with buttons for Visualize Scene, Character Portrait, Chat Background and Custom, and models, LoRAs, style, steps and CFG all configurable inside. Visualize Scene pulls the most recent messages so images match what is actually happening. (Those separate modes were folded into the rebuilt Image Studio in 1.0.)
- 🧠 **Realism and Needs got dramatically more reliable** — bond, trust and lust changes consistently appear in chips; manual Needs reprocessing is safe and non-destructive; group chats correctly track per-speaker needs, decay and scene rewards; a dedicated Needs tab in group settings with editable per-character baselines.
- ✨ **Editors got live syntax highlighting** (amber dialogue, actions, teal macros) with spellcheck and no typing lag, preserved in fullscreen. SillyTavern-style macros work inside cards, scenarios and lorebooks, and the lorebook editor is unified across the whole app.
- 📤 **Other polish** — export user personas as SillyTavern-compatible JSON, a database cleanup tool for orphaned records, 2×2 character previews on folder cards, and a fix for Windows maximized-window ghosting.

---

## v0.9.8 Stable

**Released:** 2026-05-16 (v0.9.8), with v0.9.8.0.1 and v0.9.8.0.2 the same day and v0.9.8.1 on 2026-05-19

The stable release of everything in the 0.9.8 beta series below:

- Character Expressions (ONNX and LLM powered).
- Significant Realism Engine improvements — bond widened to ±300, arousal to ±100, and far more reliable evaluations.
- A robust Kokoro text-to-speech worker pool with reliable verbatim narration.
- `.kcpps` preset support and centralized context management.
- Custom chat backgrounds, Google Fonts, per-character bubble colors.
- Full hybrid local and remote API support (OpenRouter, Nano-GPT and friends).

**v0.9.8.1 (2026-05-19)** — a focused point release: fixed an avatar-change crash on read-only filesystems, made the (since-removed) Cloud Sync page functional, hardened story generation against odd number formats from LLMs, stripped emoji from text-to-speech, and made Test Voice respect the "only narrate quotes" setting.

---

## v0.9.8-Beta Series

**Initial Beta Release:** 2026-04-25 (v0.9.8-Beta)  
**Latest Tagged Beta:** v0.9.8-Beta12 (2026-05-12)  
**Status:** Superseded by [v0.9.8 Stable](#v098-stable)

This series introduces the largest set of user-facing features since v0.9.0 and includes extensive under-the-hood refinements, especially to the Realism Engine and hardware compatibility.

### Major Features (from README "What's New")

- **🎭 Character Expressions** — Live emotion-driven avatar swapping.  
  Dual-path classification (fast local ONNX distilbert model or full Realism Engine LLM path). In-app one-click download of the ONNX classifier with progress overlay. Supports any SillyTavern-compatible expression pack (26 emotion categories). Sidebar or fullscreen cinematic modes with intelligent fallback.

- **⚡ KoboldCpp Performance & Control** — Flash Attention, Context Shift, mlock, explicit `--usecublas` GPU ID, and Prefill Batch Size now enabled by default where appropriate. New collapsible **Advanced Launch Options** panel in Settings. RTX 50-series (Blackwell) GPU detection fixed. ~20–40% faster generation on supported hardware.

- **🔒 True Beta/Stable Isolation** — Separate data directory, preference namespace, and update-check logic. Optional one-time copy of stable database on first beta launch.

- **.kcpps Preset Support & Context Management** — Load `.kcpps` launch presets from KoboldCpp. When a preset is active, context size and several other generation parameters are controlled by the preset (UI dims and shows explanatory tooltip). Centralized in `StorageService.contextSize`.

- **Other Notable Additions**
  - Custom chat background image uploader with per-chat persistence.
  - Google Fonts picker for chat text styling.
  - Per-character chat bubble color persistence (survives PNG export).
  - Expandable Scenario field and improved persona editor in Character Creator.
  - KoboldCpp log viewer and backend lifecycle improvements.

### Later Changes (post-v0.9.8-Beta12, on the 0.9.8-Beta branch)

These changes landed on the beta branch after the last tagged beta of the series.

**Fixes**
- Prevented runtime crash in `Tooltip` widgets ("Either `message` or `richMessage` must be specified") when no `.kcpps` preset was active (multiple files: settings_page.dart, character_creator_page.dart, chat_settings_dialog.dart, model_settings_dialog.dart).
- Realism Engine: increased eval token limits for thinking models (Qwen3 etc.), hardened JSON output params, fixed interruption handling during regeneration, proper cancellation/abort paths, and spatial awareness fixes when passage of time is disabled.
- Bond slider ranges and stale clamps updated to ±300 to match the character creator; short-term bond tier naming aligned. (Trust has always been on its own narrower ±100 scale, and still is.)
- Arousal delta cap and threshold scaling improved; arousal bar display fixes.
- Various UI: log text copyable, .kcpps preset validation before start, session picker and background edit widget tree fixes.
- RAG/lorebook: constant entries now persist correctly, improved deduplication and wildcard/word-boundary matching.
- macOS: bundle name fixes for Metal shader compilation; proper DMG packaging in CI. (The unsigned `.dmg` was retired in v1.1 — macOS now ships a signed, notarized `.pkg` only.)
- CI/build: multiple YAML indentation and packaging fixes (removed Windows zip from matrix, proper beta/stable release workflows).

**Improvements**
- Consolidated all context size logic and `.kcpps` preset parsing into `StorageService`.
- Realism Engine escape hatch and better one-shot eval handling for remote APIs (system prompt separation for impersonate).
- UI/UX: make Scenario field expandable, UI Settings dialog scrollable, improved hover tooltips on realism chips, numeric input boxes alongside sliders in chat settings.
- Persona/description fields consolidated; Author's Note moved for better visibility.

**Documentation & Maintenance**
- Extensive cleanup of accidental files, gitignore updates (`.opencode`, `.sisyphus`).
- Continued test coverage and analyzer warning reduction.

---

## v0.9.7 Series

**Date Range:** 2026-04-06 – 2026-04-21

A focused series of stability and polish releases, heavily centered on the Realism Engine, character editor, and web UI parity.

**v0.9.7.8 (2026-04-21)** — Release v0.9.7.8 — character description fix + web UI overhaul  
**v0.9.7.7 (2026-04-19)** — Release v0.9.7.7  
**v0.9.7.6 (2026-04-15)** — Global realism toggles, time anomaly reactions, and character description fixes  
**v0.9.7.5 (2026-04-13)** — Character editor redesign, editable Realism Engine, stability fixes  
**v0.9.7.4 (2026-04-13)** — Character generation pipeline stability & NSFW interview  
**v0.9.7.3 (2026-04-10)** — Learned Facts overhaul, Web UI creator parity, phased Realism Engine recovery  
**v0.9.7.2** — Inserted "What's New" notes and related fixes  
**v0.9.7.1 (2026-04-08)** — Realism Engine prompt overhaul, Chaos Mode timing rework, KoboldCpp stability  
**v0.9.7 (2026-04-06)** — Windows build fix (spell_check_plugin)

**Themes across the series**
- **Realism Engine** — Prompt engineering, recovery phases, global toggles, time anomaly handling, passage-of-time respect, baseline preservation on regeneration.
- **Character Tools** — Major editor redesign, description fixes, preservation of realism extensions on create/edit/duplicate.
- **UI & Creator** — Promote AI Character Creator to sidebar, web UI feature parity, numerous stability fixes in generation pipeline.
- **Build & CI** — Analyzer noise reduction (574 → 268 issues), Dependabot updates, test additions for ChatService, Realism state, and integration layers.
- **Story / Novel** — `StoryPipelineService` recreation on backend change.

---

## v0.9.6 Series

**Date Range:** 2026-03-27 – 2026-04-06

**v0.9.6 (2026-03-31)** — Release v0.9.6: Local Image Gen, Easy Mode Character Creator, and UI Updates  
**v0.9.6.6 (2026-04-06)** — Documentation and restructuring updates  
**v0.9.6.5 (2026-04-06)** — Dependabot + docs updates  
**v0.9.6.4 (2026-04-05)** — Windows spellcheck / ODR build bypass  
**v0.9.6.3 – v0.9.6.1** — Patch releases for character generator web server, file handling, and minor fixes.

**Key Additions**
- Local image generation backends (A1111, Forge, SDNext, Draw Things) with live model switching, LoRA support, and per-generation model selection.
- "Easy Mode" improvements and web UI parity for character creator and Porch Stories.
- Numerous fixes around image gen avatars, crop callbacks, and provider ordering.

---

## v0.9.0 – v0.9.5

**v0.9.5 (2026-03-27)** — Porch Stories: AI Novel Generator  
  Five-stage autonomous pipeline (concept → outline → draft → edit → publish) with skeuomorphic reader and audiobook TTS read-along. Distills character chats into coherent story timelines.

**v0.9.4.1 (2026-03-24)** — Crop library API compatibility update.

**v0.9.3.4 – v0.9.3.1 (March 2026)** — macOS file picker / updater / installer fixes; TTS auto-play and configurable endpoints.

**v0.9.3 (2026-03-15)** — Preserve four-part version display in UI.

**v0.9.2 (2026-03-14)** — Character evolution, user persona injection, a separate Rust embedding server for RAG memory, TTS fixes, RAG memory improvements. (That embedding server was retired in 1.0 — embeddings now run inside the app, and character evolution became Growth Rings.)

**v0.9.1 (2026-03-11)** — CI / Node.js 24 compatibility updates.

**v0.9.0 (2026-03-09)** — First stable release under AGPL-3.0 (earlier versions were GPLv3).  
  Merged alpha work including the full **AI Character Creator** (quick concept → complete V2 card, alternate greetings, lorebook auto-gen, editor passes: Anti-Puppet, Consistency, Quality Polish).

**v0.9.0-alpha3 (2026-03-05)** — CivitAI integration for image model search/download.  
**v0.9.0-alpha2 (2026-03-03)** — AI Character Creator, multi-tone greetings, editor passes, KoboldCpp model manager.  
**v0.9.0-alpha1** — CI version sync fixes for `app_version.dart`.

---

## v0.8 Series

**v0.8.3 / v0.8.2 (early March 2026)** — Backports of Linux segfault fixes, .desktop shortcuts, icon, and settings rename from the 0.9 alphas. Character data loss prevention on folder operations.

**v0.8.1 (2026-02-27)** — Fix for custom install directory breaking database.

**v0.8.0 (2026-02-27)** — Stable release: process cleanup, cloud sync reliability, orphan PNG cleanup.

**v0.8.0-beta series (Feb 2026)**  
- XTC sampler, persona cloud sync, Director Mode (multi-character group chat control).  
  (Cloud Sync was removed in 1.0 — automatic local backups replaced it.)  
- Backyard AI (.byaf) importer.  
- Model loading status, right-click context menus, smarter stop sequences, buffer duration settings.  
- ROCm GPU support, Linux process shutdown fixes, Ko-fi integration.

---

## Earlier Versions (v0.7 and below)

Rapid early development focused on core functionality.

- **v0.7.2 / v0.7.2.1 (2026-02-23)** — Custom models folder with safe recursive scanner, cross-platform "Open Folder", fixes for character folder display.
- **v0.7.1 (2026-02-22)** — CI path fixes for PyInstaller.
- **v0.7.0 (2026-02-19)** — Multi-engine TTS debut (Kokoro local 50+ voices, OpenAI, Piper lightweight fallback).
- **v0.6.1 (2026-02-19)** — Version display fixes, AppImage self-update, impersonate revamp, context size controls in chat settings.
- **v0.6.0 / v0.5.x (Feb 2026)** — Expandable fields, alternate greetings, example dialogues in edit dialog; installer and packaging refinements.
- **v0.0.4 series (2026-02-17)** — External API support, swipe navigation, thought chip, Continue button, chat import/export, persona titles.
- **v0.0.3 series (2026-02-16)** — Early sidebar UI fixes, Alt Greetings UI, smooth output buffer documentation.
- **v0.0.1 – v0.0.2 (2026-02-14/15)** — Initial public releases, macOS rework, CI/CD Windows build path fixes.

These early versions established the foundation: V2 character card support, local KoboldCpp integration, basic chat with rich text, persistent sessions, and the beginning of the Realism Engine and RAG memory features.

---

## How to View Full Changelog

```bash
# View commits between two tags (example)
git log v1.1.2..v1.2.0 --oneline

# List all tags (version-sorted)
git tag -l | sort -V

# Show the tag annotation/message for a specific release
git show v1.2.0

# Full diff between any two points
git log --oneline v1.0.0..HEAD
```

You can also browse the [commit history](https://github.com/linux4life1/front-porch-ai/commits/) or [Releases](https://github.com/linux4life1/front-porch-ai/releases) directly on GitHub.

---

*This page covers stable releases through v1.2.0 (August 2026). Nightly Rawhide builds and the full per-release detail are on [GitHub Releases](https://github.com/linux4life1/front-porch-ai/releases).*
