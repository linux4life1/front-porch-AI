# Release Notes

Front Porch AI uses a rapid release cycle with frequent patch and beta releases. The authoritative version string is defined in [`lib/app_version.dart`](../lib/app_version.dart), which also controls the `isPreRelease` flag used to isolate beta data directories and preferences.

**Beta releases** (0.9.8-Beta series) live on the `0.9.8-Beta` branch. They install to a completely separate directory (`~/Documents/FrontPorchAI-Beta/`) and use `beta_` namespaced preferences so they never touch your stable installation. Stable releases target the `main` branch.

For the most up-to-date per-commit details, see the [GitHub Releases page](https://github.com/linux4life1/front-porch-ai/releases).

---

## Table of Contents

- [v0.9.8-Beta Series (Current)](#v098-beta-series-current)
- [v0.9.7 Series](#v097-series)
- [v0.9.6 Series](#v096-series)
- [v0.9.0 – v0.9.5](#v090--v095)
- [v0.8 Series](#v08-series)
- [Earlier Versions (v0.7 and below)](#earlier-versions-v07-and-below)
- [How to View Full Changelog](#how-to-view-full-changelog)

---

## v0.9.8-Beta Series (Current)

**Initial Beta Release:** 2026-04-25 (v0.9.8-Beta)  
**Latest Tagged Beta:** v0.9.8-Beta12 (2026-05-12)  
**Status:** Public beta — ongoing development on `0.9.8-Beta` branch

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

### Recent Changes (post-v0.9.8-Beta12, on 0.9.8-Beta branch)

These changes are present in the current development head but not yet in a tagged beta release.

**Fixes**
- Prevented runtime crash in `Tooltip` widgets ("Either `message` or `richMessage` must be specified") when no `.kcpps` preset was active (multiple files: settings_page.dart, character_creator_page.dart, chat_settings_dialog.dart, model_settings_dialog.dart).
- Realism Engine: increased eval token limits for thinking models (Qwen3 etc.), hardened JSON output params, fixed interruption handling during regeneration, proper cancellation/abort paths, and spatial awareness fixes when passage of time is disabled.
- Bond/Trust slider ranges and stale clamps updated to ±300 to match character creator; short-term bond tier naming aligned.
- Arousal delta cap and threshold scaling improved; arousal bar display fixes.
- Various UI: log text copyable, .kcpps preset validation before start, session picker and background edit widget tree fixes.
- RAG/lorebook: constant entries now persist correctly, improved deduplication and wildcard/word-boundary matching.
- macOS: bundle name fixes for Metal shader compilation; proper DMG packaging in CI.
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

**v0.9.2 (2026-03-14)** — Character evolution, user persona injection, Rust embed server (ONNX RAG), TTS fixes, RAG memory improvements.

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
git log v0.9.7.8..v0.9.8-Beta12 --oneline

# List all tags (version-sorted)
git tag -l | sort -V

# Show the tag annotation/message for a specific release
git show v0.9.8-Beta12

# Full diff between any two points
git log --oneline v0.9.5..HEAD
```

You can also browse the [commit history](https://github.com/linux4life1/front-porch-ai/commits/0.9.8-Beta) or [Releases](https://github.com/linux4life1/front-porch-ai/releases) directly on GitHub.

**Tip for contributors:** When preparing a new release, update `lib/app_version.dart`, create an annotated tag, and ensure the README "What's New" section and this file are both updated with categorized highlights.

---

*Last updated: 2026-05-15 (incorporating git tag data through v0.9.8-Beta12 and post-tag development on the 0.9.8-Beta branch).*
