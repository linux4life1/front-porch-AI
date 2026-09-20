<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/porch-banner-dark.svg">
  <img src="docs/assets/porch-banner-light.svg" alt="Front Porch AI — a local-first AI companion for character chat and roleplay" width="100%">
</picture>

<p align="center">
  <a href="https://github.com/linux4life1/front-porch-AI/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/linux4life1/front-porch-AI/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="License: AGPL-3.0-or-later" src="https://img.shields.io/badge/License-AGPL--3.0--or--later-B45309?labelColor=2B1B0C">
  <img alt="Made with Flutter" src="https://img.shields.io/badge/Made%20with-Flutter-E8833A?labelColor=2B1B0C&logo=flutter&logoColor=white">
  <img alt="Platform: Windows, Linux, macOS" src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-F4A259?labelColor=2B1B0C">
  <img alt="Branch: Rawhide (development)" src="https://img.shields.io/badge/Branch-Rawhide-FFC44D?labelColor=2B1B0C">
</p>

**A local-first desktop app for character chat and roleplay — Windows, macOS, and Linux.** Models run on your machine (KoboldCpp, oMLX, LM Studio) or, if you choose, on a remote API. Characters have moods, needs, a story clock, pockets, a journal, and memory that never leaves the box. Optional **TTS / STT**, local image backends, a companion **web/phone UI**, and **The Stoop** (opt-in, 18+ character hub). Open source: **AGPL-3.0-or-later**.

This file is the **Rawhide** README — the rolling development branch. Tagged stable releases live on [`main`](https://github.com/linux4life1/front-porch-AI/tree/main). Nightlies are built from Rawhide and keep a **separate** library so they never touch a stable install.

**Docs:** [User guide](https://frontporchai.app) · [Getting started](docs/getting-started.md) · [Install](docs/install.md) · [FAQ](docs/faq.md) · [Discord](https://discord.gg/e4tET6rpdv)

---

<p align="center">
  <img src="docs/screenshots/home_new.png" width="800" alt="Front Porch AI — character library">
</p>

---

## Why this exists

When a popular desktop character-chat app went SaaS-only, a lot of people lost the room they actually sat in at night. Front Porch AI is a warm place to sit with your characters **on your own machine**. The license is part of that promise: from **v0.9.0** on, the app is **AGPL-3.0-or-later**, so a hosted fork has to stay open. Cards import from the usual V2 PNG/JSON world and from Backyard `.byaf` archives.

It is not a SillyTavern clone with a different coat of paint. The bet is **everything working out of the box** — Porch Life, groups, phone, voices — instead of a plugin bazaar.

---

## How it compares

Every project below is doing something right. This is so you can pick the right tool, not so anyone gets dunked on.

| | **Front Porch AI** | SillyTavern | Jan.ai | Backyard AI |
|---|---|---|---|---|
| Native desktop | Flutter (Win / macOS / Linux) | Local web UI | Electron | Abandoned desktop |
| Community hub | **The Stoop** — in-app + [web](https://hub.frontporchai.app), AGPL, group casts | External sites | — | Closed hub, web/mobile |
| Offline chat | Yes | Yes | Yes | — |
| Remote / OpenAI-compatible APIs | OpenRouter, Nano-GPT, LM Studio, oMLX, custom | Strong | Limited | — |
| Built-in TTS + push-to-talk STT | Kokoro / Piper / ElevenLabs / OpenAI + Whisper, in-process | Extension | — | — |
| Local pictures | A1111, Forge, SDNext, ComfyUI, Draw Things | Extension | — | — |
| Living characters | Porch Life: realism, needs, clock, journal, pockets, chaos, quests, growth | — | — | — |
| Phone / browser | PWA served by the desktop app | The ST UI itself | — | — |
| Card format | V2 PNG/JSON + `.byaf` | V2 | — | `.byaf` |
| License | AGPL-3.0-or-later | AGPL-3.0 | MIT | Closed |

SillyTavern still wins on raw extension depth. Front Porch is for people who want to chat, not configure a second career.

---

## What you actually get

### Chat

- V2 character cards (SillyTavern / Chub / Risu compatible) and **`.byaf`** import — drop a PNG or archive on the home porch
- Streamed replies, a smooth output buffer, regenerate / swipe / continue / impersonate / edit / fork
- **Continue does not move the story clock.** Delete / regen rewind Realism state, not just the text
- Attach a photo (desktop and phone). Vision models see it; text-only models can use a local Photo Understanding helper
- Slash commands (`/join`, `/exit`, `/speak`, `/turnorder`, `/afk`, `/image`, `/scan`, …) and `@` mentions
- Thinking models put private reasoning in a collapsible **Thought** chip that follows new tokens
- Persistent sessions, chat history, `.fpchat` / SillyTavern export

<p align="center">
  <img src="docs/screenshots/chat.png" width="800" alt="Front Porch AI — chat">
</p>

### Living characters

**Settings → Porch Life** is the defaults board for Realism, Needs, the story clock, Journal, Pockets, Objectives, Chaos, Growth, Afterglow, and the rest of that family. Realism is **not** a master key — Journal, the clock, Chaos, Pockets, and Objectives each have their own switch. New chats pick up those defaults. An **open** chat is tuned from the sidebar, not by flipping Settings.

That tab does **not** host Clock In, AFK, or RAG.

- **Realism** — mood, bond, trust, lingering feeling
- **Needs** — hunger, bladder, energy, social, fun, hygiene, comfort; a quiet beat can leave them still
- **Passage of Time** — a **story** clock, not your wall clock. Continue does not tick it
- **Journal** — per-chat diary cards; they never leak into another conversation
- **Growth Rings** — long-story character change, with receipts so regen/delete can rewind
- **Pockets & Wardrobe** — what they wear and carry; per-character switch on the Wearing / Carrying panel
- **Objectives** — goals and steps; leftover quests can go stale instead of pretending you won
- **Chaos** — Chance Time events (own switch, not a Realism dependency)
- **Afterglow** — 18+ cooldown after a scene

These three live somewhere else:

- **Clock In** — occupation, hours, and weekdays on the character **Details** tab (Work). Not a Settings switch. People at work stay on the clock
- **AFK / Dynamic Responses** — sidebar **Story Tools** (the 1:1 panel) or `/afk`. The scene keeps living while you step away; in a group, the cue is about **who actually speaks**
- **RAG memory** — sidebar **Memory (RAG)** in 1:1, or **Group Settings → Memory & RAG**. Local ONNX embeddings; remembered lines keep a speaker nametag

Deep dive: [Porch Life](docs/porch-life.md) · [Realism Engine](docs/realism-engine.md)

### Groups

- Several characters in one scene, or `/join --full` to turn a 1:1 into a group in place
- Guests vs full members; `/promote`, `/speak`, `/turnorder`, `/exit`
- Director mode for autonomous back-and-forth
- Per-speaker realism, needs, lore, expressions, and pockets — same observable result as 1:1 for that character

### Cards, worlds, lore

- Quick Create and a guided creator; wiki / file lore can be woven into a new card
- Avatar Gallery (multiple looks per character); expression packs that swap with mood
- Lorebooks with a real activation engine (triggers, depth, sticky/cooldown, token budget)
- **Places / Worlds** — setting, seasons, weather, climate; a lore-only place stays lore
- SillyTavern-format lorebook import/export

### Voice, pictures, stories

- **TTS:** Kokoro (local, 50+ voices), Piper, ElevenLabs, OpenAI — in-process, no Python
- **STT:** Whisper push-to-talk, same story
- **Image Studio** — A1111 / Forge / SDNext / ComfyUI / Draw Things. You run the picture program; Front Porch talks to it. `/image` paints the scene into chat
- **Porch Stories** — distill a chat into a novel (concept → outline → draft → edit → publish) with a page-flip reader

### The Stoop

Opt-in, account-gated, **18+**. Browse and download without leaving the app — including **whole group casts** (members, avatars, lorebooks, seeded realism/needs). Share, follow, vote, comments. Adult cards hidden until you turn them on.

Also on the web: **[hub.frontporchai.app](https://hub.frontporchai.app)** (guest browse, no install).

The rest of the app stays local. Details: [Privacy Policy](PRIVACY.md).

### Phone and browser

The desktop app can serve an installable PWA on your LAN (or Tailscale). Chat, library, settings, Stoop browse, Porch Stories, attach a photo. The desktop machine has to stay on — it is the brain.

Not on the phone: full Image Studio, Voice Call, Stoop upload, backups UI, and a handful of power-user backend knobs. Guide: [Web & Phone](docs/web-phone.md).

### Waifu Coder

A managed [OpenCode](https://github.com/sst/opencode) coding session inside the app. Front Porch downloads a pinned build into its own closet and runs it on localhost — not your Homebrew copy, not a chat sidecar.

### Backends

- **KoboldCpp** — downloaded and started for you. Vulkan / Metal / Intel ARC / NVIDIA (including RTX 50). Older CPUs get a non-AVX2 build. Model Hub talks to HuggingFace. Flash Attention, Context Shift, `.kcpps` presets, mmproj for vision
- **oMLX** — local Apple Silicon
- **LM Studio**, **OpenRouter**, **Nano-GPT**, or any OpenAI-compatible URL
- **Intel Macs** cannot run local GGUFs. Pick a remote / OpenAI-compatible backend yourself; the app will not silently switch you

Thinking / reasoning works on local models. Prompt-read progress is honest on Kobold, oMLX, and LM Studio.

### Backups

Two-tier **local** snapshots (about every 30 minutes, plus daily copies). One-click restore on stable. Nightlies still write snapshots into their own folder; the Backups page there is a notice, not a restore UI. There is no cloud sync.

---

## Install

**Stable** (from [`main`](https://github.com/linux4life1/front-porch-AI/tree/main)): [Releases](https://github.com/linux4life1/front-porch-AI/releases) — Windows `.exe`, notarized macOS `.pkg`, Linux AppImage / `.deb` / `.rpm` / `.tar.gz`.

**Nightly** (this branch): tagged `nightly-…`, flagged pre-release. Separate `FrontPorchAI-Beta/` data folder. Windows / macOS / AppImage / `.tar.gz` — not apt/dnf.

Full platform notes, FUSE, AUR caveats: **[Installation guide](docs/install.md)**.

### Linux packages (stable)

**Debian / Ubuntu / Mint / Pop!_OS**
```bash
curl -fsSL https://apt.frontporchai.app/install.sh | bash
sudo apt install front-porch-ai
```

**Fedora / RHEL**
```bash
sudo dnf config-manager --add-repo https://rpm.frontporchai.app/front-porch-ai.repo
sudo dnf install front-porch-ai
```

**Arch (AUR)** — `yay -S front-porch-ai-bin` (stable) or `front-porch-ai-beta-bin` (nightly; the name is leftover). The two conflict. The AUR can lag the GitHub release; the AppImage on [Releases](https://github.com/linux4life1/front-porch-AI/releases) is always current.

### First launch

1. **Backend** — let the app fetch KoboldCpp, or point it at oMLX / LM Studio / OpenRouter / a custom URL.
2. **Model** — Manage Models → HuggingFace Search. `Q4_K_M` / `Q5_K_M` is a sensible start.
3. Hardware defaults are chosen for you. Tweak GPU layers in Settings → Backend if you want.

Voice and embeddings download the first time you turn those features on. Nothing else phones home.

---

## Docs

| | |
|---|---|
| [Getting started](docs/getting-started.md) | First launch to first chat |
| [User guide](docs/user-guide.md) | The reference |
| [Chatting](docs/chatting.md) · [Porch Life](docs/porch-life.md) · [Characters](docs/characters.md) | How a conversation, a life, and a card actually work |
| [Image Studio](docs/image-studio.md) · [Web & phone](docs/web-phone.md) | Pictures, and the PWA |
| [FAQ](docs/faq.md) · [Troubleshooting](docs/troubleshooting.md) | When it will not talk |
| [What's New (stable)](docs/main.md) · [Rawhide nightlies](docs/Rawhide.md) · [Release notes](docs/release-notes.md) | What changed |
| [CONTRIBUTING.md](CONTRIBUTING.md) · [CLAUDE.md](CLAUDE.md) | How to send a patch |

---

## Contributing

Work lands on **`Rawhide`**. `main` is tagged stable only. PRs against `main` are almost never accepted.

```bash
git clone https://github.com/linux4life1/front-porch-AI.git
cd front-porch-AI
git checkout Rawhide
flutter pub get
flutter run
```

CI Flutter is **3.47.0** (Dart `^3.10.8`). macOS **12 Monterey** is the floor.

There is **no Rust, no Python, no sidecar** to build. TTS, STT, embeddings, and expressions run in-process. KoboldCpp and Waifu Coder's OpenCode are process-managed the way a browser manages a helper — the app downloads a pinned build and starts it on localhost.

Before a PR: `flutter analyze` on what you touched, `flutter test --concurrency=4 --exclude-tags golden`, and if you edited `web_ui/`, `npm run lint && npm test` there. Format **only** the Dart files you already edited — never `dart format .`. Full law: [CONTRIBUTING.md](CONTRIBUTING.md) and [CLAUDE.md](CLAUDE.md).

Linux extra packages for a source build are in the [install guide](docs/install.md#for-developers-building-from-source).

---

## Privacy

Offline use collects nothing. The **only** account is **The Stoop**, and only if you sign in. Chats, cards, and models stay in a folder you control (`FrontPorchAI` in Documents; `FrontPorchAI-Beta` for nightlies). Remote APIs you configure receive *your* prompts — not a Front Porch server.

[Privacy Policy](PRIVACY.md)

---

## Credits

| Project | Role |
|---|---|
| [KoboldCpp](https://github.com/LostRuins/koboldcpp) | Local GGUF backend |
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | In-process Whisper + local voices |
| [Kokoro](https://github.com/hexgrad/kokoro) | Default local TTS |
| [Piper](https://github.com/rhasspy/piper) | Lightweight local TTS |
| [OpenCode](https://github.com/sst/opencode) | Waifu Coder's managed coding loop |
| [Flutter](https://flutter.dev) | The desktop (and the PWA's host) |

If Front Porch is useful, a star on those projects helps the people who actually made the engines.

**Character Card Forge** ([@FrozenKangaroo](https://github.com/FrozenKangaroo/Character-Card-Forge)) is a community editor that can seed Realism state. It talks to the database directly, so a schema bump can break it.

Code PRs have also come from [@S-A-M-F](https://github.com/S-A-M-F), [@willie](https://github.com/willie), [@MisterLotto](https://github.com/MisterLotto), [@dazpants1](https://github.com/dazpants1), and [@bigsombar](https://github.com/bigsombar).

---

## License

**v0.9.0 and later** — [AGPL-3.0-or-later](LICENSE)
**v0.8.x and earlier** — GPL-3.0

---

*Built with 🧡 using [Flutter](https://flutter.dev)*
