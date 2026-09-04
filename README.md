<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/porch-banner-dark.svg">
  <img src="docs/assets/porch-banner-light.svg" alt="Front Porch AI — a local-first AI companion for character chat &amp; roleplay" width="100%">
</picture>

<p align="center">
  <a href="https://github.com/linux4life1/front-porch-AI/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/linux4life1/front-porch-AI/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="License: AGPL v3" src="https://img.shields.io/badge/License-AGPLv3-B45309?labelColor=2B1B0C">
  <img alt="Made with Flutter" src="https://img.shields.io/badge/Made%20with-Flutter-E8833A?labelColor=2B1B0C&logo=flutter&logoColor=white">
  <img alt="Platform: Windows, Linux, macOS" src="https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-F4A259?labelColor=2B1B0C">
  <img alt="Branch: main (stable)" src="https://img.shields.io/badge/Branch-main-FFC44D?labelColor=2B1B0C">
</p>

**`main` is the stable release branch.** All new features land on `Rawhide` (the rolling development branch) and are promoted here when ready. Nightly cutting-edge builds are available from Rawhide for users who want the latest.

**A local-first AI companion for character chat & roleplay — Windows, macOS, and Linux.** Runs fully offline with local LLMs (KoboldCpp, oMLX, LM Studio, …), driven by a living **Realism Engine** (emotion, trust, needs, memory, pockets) with built-in **TTS and image generation** — and supports remote APIs like OpenRouter, Nano-GPT, and OpenAI with no lock-in when you want them. Open-source (**AGPL-3.0**). Built as a home for people who lost theirs when Backyard AI killed its desktop app.

> ### 🎂 New in 1.3.2 — Make a Wish
> - **Birthdays are real.** Characters and personas show their birthday on the card panel, on The Stoop, with gold/blue checks next to verified creators.
> - **Worlds can skip the weather.** A lorebook-only world opts out of climate entirely — quiet places stay quiet.
> - **Tool calls got faster.** Evals stop stalling on empty responses, and the judges share their prompt prefix.
> Plus the repairs: swapping a portrait no longer wipes Journal, Growth, quests, or RAG; AFK owns the clock; regen keeps its chips. Details in the in-app What's New.

## 🕯️ Why Does This Exist?

When Backyard's desktop app shut down, people lost the room they sat in at night — not just an installer. Front Porch is the local-first answer: your characters, on your machine, with a license that stays open even if someone hosts a fork.

From **v0.9.0** the license is **AGPL-3.0** — a modified hosted copy has to publish its changes. Your old Backyard library comes home too: the app imports `.byaf` archives directly.

That's the promise. **A home that stays.** Characters that feel like they're there.

> 🎩 Hat tip to the Backyard AI team for open-sourcing `.byaf` on their way out. (v0.8.x and earlier are GPLv3.)

---

<p align="center">
  <img src="docs/screenshots/home_new.png" width="800" alt="Front Porch AI — Character Library">
</p>

---

## 🆚 How Does Front Porch AI Compare?

If you're evaluating local AI tools, here's an honest breakdown. Every project on this list is doing something right — the goal isn't to trash competitors, it's to help you pick the right tool for *you*.

| Feature | **Front Porch AI** | SillyTavern | Jan.ai | Backyard AI |
|---|---|---|---|---|
| **Native desktop app** | ✅ Flutter (Win/Mac/Linux) | ❌ Web-based (local server) | ✅ Electron | ✅ (abandoned) |
| **Built-in community character hub** | ✅ **The Stoop** — **open-source (AGPL-3.0)**, local-first; browse / share / download in-app, incl. full **group casts** (members + lorebooks + realism/needs/pockets) | ❌ (external sites only) | ❌ | ⚠️ Character Hub — **closed, paid-SaaS**; desktop app killed (2025), web/mobile only; single cards |
| **Fully offline — no cloud required** | ✅ | ✅ | ✅ | ✅ |
| **Remote LLM Endpoints** | ✅ Native multi-provider support (OpenRouter, Nano-GPT, custom, etc.) with deep integration | ✅ Strong native support for custom OpenAI-compatible endpoints | ⚠️ Limited | ❌ (service discontinued) |
| **Built-in TTS (50+ voices)** | ✅ Kokoro + Piper + ElevenLabs + OpenAI | ⚙️ Extension required | ❌ | ❌ |
| **Speech-to-text (push-to-talk)** | ✅ Whisper, built-in | ⚙️ Extension required | ❌ | ❌ |
| **Local image generation** | ✅ A1111, Forge, ComfyUI, Draw Things (macOS) | ⚙️ Extension required | ❌ | ❌ |
| **Realism Engine** | ✅ Time, trust, emotion, needs, chaos, quests, pockets, tastes — each switchable | ❌ | ❌ | ❌ |
| **Character Expressions** | ✅ ONNX + LLM, live avatar swap | ⚙️ Extension required | ❌ | ❌ |
| **RAG memory (local)** | ✅ ONNX embeddings, no cloud | ⚙️ Extension required | ❌ | ❌ |
| **Novel / story generator** | ✅ Porch Stories pipeline | ❌ | ❌ | ❌ |
| **Character card compatibility** | ✅ V2 spec + Backyard .byaf import | ✅ V2 spec | ❌ | .byaf only |
| **Group chat** | ✅ | ✅ | ❌ | ❌ |
| **Web / phone app** | ✅ Installable PWA from the desktop app | ⚙️ Separate | ❌ | ⚠️ Web/mobile only now |
| **Extension / plugin ecosystem** | ❌ | ⭐ Very large | Moderate | ❌ |
| **Open source license** | ✅ AGPL-3.0 | ✅ AGPL-3.0 | ✅ MIT | ❌ |
| **Best for** | Polished AI companion + storytelling | Power users / heavy customization | Simple local chat | — |

> SillyTavern's extension ecosystem is genuinely impressive and unmatched for customization depth. If you want maximum flexibility and don't mind configuration work, it's excellent. Front Porch AI prioritises **everything working out of the box** for users who want to chat, not configure.

---

## ✨ Features

### 🏡 The Stoop — Built-In Community Character Hub

A stoop is where the neighbourhood meets — the front step where people swap stories and pass things back and forth. **The Stoop** brings that to Front Porch: a community character hub built right into the app, so you can discover and share characters without ever leaving home, while everything else stays offline. What sets it apart from other in-app hubs (Backyard AI's Character Hub, RisuAI's RisuRealm) is that The Stoop hands over **entire group casts** — not just single character cards — carrying members, lorebooks, **and** the pre-seeded Realism/Needs/Pockets state intact, so a whole living scene arrives ready to play.

- **Browse & discover** — featured and moderator-picked cards, search, tag filters, and a live feed of what the neighbours are sharing. A card page shows the whole character: ambitions, likes, starting wardrobe — not just the greeting.
- **One-tap download** — pull any card straight into your library; it lands ready to chat, exactly as the creator tuned it.
- **Whole casts come over, not just cards** — share a full group and the recipient gets everything: members, avatars, lorebooks, **and** the pre-seeded Realism state, Needs baselines, pockets, and intra-group dynamics. Nothing is flattened on the round-trip.
- **Share what you made** — a guided upload wizard with member-avatar montages for groups, comma-formed tag pills, and a clean review flow before anything goes live. Shared a card already? **Update it in place**. Sharing someone else's work? The **Original creator** field gives them visible credit. **18+ is not a checkbox the uploader ticks** — the hub derives it from what's actually on the card.
- **Creator profiles** — a real profile (picture, bio, links, art grid) behind a confirmed email, so drive-by accounts can't post avatars.
- **Follow creators & vote** — follow the people whose characters you love, upvote/downvote (counts update live), and report anything that breaks the house rules.
- **On the web too** — [hub.frontporchai.app](https://hub.frontporchai.app) works from any browser, including guest browsing with no account at all.
- **Open porch, not a walled garden** — The Stoop is **open-source (AGPL-3.0)** and local-first. The for-profit hubs tend to drift closed and paywalled; AGPL exists so The Stoop can't be fenced off the same way.
- **Safe by design** — **opt-in** and **account-gated**; the rest of the app stays 100% local and offline. Strictly **18+**, with adult content **hidden by default**, optional **two-factor authentication**, and an **opt-out** anonymous device-stats ping (platform / app version / GPU tier — never your chats, characters, or raw IP). See the [Privacy Policy](PRIVACY.md).

### 🕘 Work & Time

New in 1.3.1 — Clock In.

- **They have a job** — occupation, which days, clock-accurate hours. Skip a turn and the banner says they're at work.
- **Night skip lets them rest.** A day off is a day off.
- **Time is announced, then they write.** After the reply the clock decides how much passed. Continue does not tick.
- **With you is a yes or a no**, after they speak — not a default.

### 🎁 Pockets & Wardrobe

New in 1.3. She has pockets, clothes, and a set-aside pile — and the app keeps the record, not just the prose.

- **Hand her something and she has it** — accept a gift, pick it up, put it down, pass it to someone else in a group. An offer she ignores or turns down stays out of her pockets.
- **Clothes come off into the pile**, not into nowhere. What she set aside lasts the night and is gone at the story's next morning.
- **Authors can dress her on the card** — starting clothes and carried items seed the first chat. The Stoop card page shows that wardrobe.
- **The Journal keeps a Belongings tab** of where things went.
- **Own switch.** Does not need the Realism Engine. If Needs is on too, a hungry character reaches for the food already in her pocket before looking elsewhere.

### 💬 Chat
- **Immersive roleplay** with V2-spec character cards — full SillyTavern / Backyard AI compatibility
- **Smooth output buffer** — text drips at your reading pace, not your GPU's pace
- **Rich text styling** — dialogue highlighted in amber (straight, curly, and international quotes alike), actions in grey
- **Regenerate, Continue, Impersonate, Edit** — full message control. **Impersonate is on the phone too**; a start you already typed is continued as you, not answered as the character
- **Take a chat with you** — export a conversation as a Front Porch `.fpchat` (history, diary, growth, the lot) or SillyTavern JSONL, and bring it back on desktop or the phone
- **Photo attachments** — send your character a picture and vision-capable models genuinely see and react to it (with a fully local description fallback for text-only models)
- **Per-chat visual themes** — ten presets plus full color customization, desktop and web
- **Output Sanitizer** — automatic find-and-replace on model output (goodbye em-dash tics), with per-chat overrides
- **Slash commands** — `/image`, `/join`, `/exit`, `/speak`, `/turnorder`, `/afk`, and more, with a `/` helper panel
- **Persistent sessions** — chat history auto-saved and restored per character
- **Chat branching** — fork from any message to explore alternate storylines

### 🏡 Porch Life & the Realism Engine
- **Porch Life** — one Settings home for every living-character switch, instead of hunting them across the app
- **À la carte** — Journal, Chaos / Chance Time, the story clock, Pockets, and Objectives each have their own switch. Turn on what you want. The Realism Engine is no longer the master key
- **Emotion tracking** — character mood evolves naturally across the conversation, carrying inertia between turns
- **Likes & Dislikes** — give her tastes (thunderstorms, being interrupted) and she acts on them. Moments that hit what she actually cares about move bond and trust harder
- **Intimate preferences get said** — not just scored in the background. She can ask for what she wants, and she can turn something down
- **A bad day that isn't about you** — optional, off by default. She can arrive tired, hungry, or weather-beaten from her own life, and the sidebar says why. Nothing is invented
- **Relationship & Trust system** — earn a character's trust over time; it shifts how open and vulnerable they allow themselves to be
- **Sims-style Needs** — hunger, energy, social, fun, hygiene, comfort: they decay on their own, respond to what actually happens in the scene, and bottoming one out has real consequences
- **Story clock** — time advances every turn from what just happened (not a six-turn gate). It can run with the engine off. If she names 6am, the clock becomes 6am
- **Weather & dreams** — hour-by-hour story weather, and a short dream when a story night passes
- **Character quests** — self-chosen goals become real main quests with concrete steps. **Ambitions on the card steer those quests**, and you can set them when you create her
- **Promises** — commitments land in a Journal tab you can mark kept or broken yourself
- **Fixation Engine** — active emotional obsessions that subtly color every response
- **Growth Rings** — visible, receipt-backed character growth: real changes become rings that strengthen into permanence or fade into a viewable past
- **The Journal** — a living, per-chat diary (each entry stamped with its emotion). Strong memories linger; faint ones resurface when relevant. Nothing ever leaks between chats
- **AFK / Dynamic Responses** — characters keep living while you're away, with time and Needs following along
- **RAG Memory** — local semantic memory powered by a lightweight ONNX embedding engine; the AI recalls past conversations without any cloud

### 🎭 Character Management
- **V2 spec support** — fully compatible with the V2 character card specification (PNG & JSON)
- **One-click import** — any V2 character card PNG/JSON, or grab community cards straight from **The Stoop** — no browser needed
- **Backyard AI (.byaf) importer** — rescue your characters from the archive format Backyard AI left behind
- **AI Enhance** — grow a character from a real chat. Walks you through it, review old-vs-new, and bring those chats along onto the enhanced copy. The original card is never overwritten
- **Folder organization**, including group casts, global search, tag editor, bulk PNG import, mass delete with confirmation
- **One-click duplication** — clone any character card for risk-free experiments

### 🧙 AI Character Creator
- **Quick Create** — type a name and concept, the AI builds a complete V2 card from scratch
- **Voice-first interview** — better questions, three-stage lorebook generation, a veto gate on the portrait before an expression pack spends your time
- **World Lore (RAG-Lite)** — paste a Fandom wiki URL or attach a local `.txt`/`.pdf` and the generator embeds that lore into the character
- **Editor passes** — Anti-Puppet, Consistency Check, Quality Polish, Truncation Completion
- **Alternate greetings** — generate up to 5 unique first messages with configurable tone
- **Lorebook auto-generation** — world-building entries generated alongside the character
- **Ambitions, likes, and starting wardrobe** are first-class on the card — not buried prose

### 👥 Group Chat & Director Mode
- **Multi-character conversations** — 2+ characters interacting with each other and with you
- **One chat, a changing cast** — turn a solo chat into a group **in place** with `/join --full`, add/remove characters live with `/join` and `/exit` (goodbye + undo), and collapse back to a clean 1:1 with the **original** character — no forking or orphan copies
- **Macros** — `/turnorder` (set who speaks when, including your own slot), `/speak` (force a character to take a turn now), `/promote` (promote a scene guest to a full member)
- **Director Mode** — let characters chat autonomously, or manually choose who speaks next
- **Per-character everything** — realism, needs, pockets, expression images, author notes, and growth are tracked per member and carried losslessly when converting between 1:1 and group

### 🌍 Worlds
- **Author a place** — climates, temperature bands, atmosphere and gravity. Mars does not come with breathable air; characters feel the weather and dress for it
- **Share a world on The Stoop** like a character. A new chat can inherit its character's world automatically
- **`.fpworld` packages** — take a place between installs (Front Porch 1.2 or newer)

### 🧭 Lorebooks & Macros
- **Full-fidelity imports** — SillyTavern, Chub, NovelAI, AgnAI, and RisuAI books arrive through a preview wizard with every setting honored
- **A real activation engine** — conditional & regex triggers, scan depth, exact placement, sticky/cooldown timers, chaining, variety groups, and a token budget
- **Per-chat books** — try a lorebook in one conversation without touching your library
- **Stateful macros** — `{{setvar}}`/`{{getvar}}`, `{{random}}`, `{{roll}}`, time/date, and conversation macros, everywhere macros run
- **Perfect round-trips** — exports write genuine SillyTavern-format files; nothing is lost in either direction

### 🗣️ Text-to-Speech
- **Four engines**: Kokoro (local, 50+ voices, 9 languages), ElevenLabs (cloud, expressive), OpenAI (cloud, premium), Piper (lightweight fallback, including **bring-your-own** `.onnx` voices)
- **Parallel generation** — sentences generated concurrently for fast audio output
- **Narration filters** — dialogue-only or skip action blocks (SillyTavern-style)
- **Per-character voices** — visible and clearable on the card, so a voice that arrived on an import isn't an invisible override

### 🖼️ Image Studio & Local Image Generation
- Natively connects to **A1111, Forge, SDNext, ComfyUI, and Draw Things** — auto-discovery, friendly status cards, no node graphs required. **Draw Things is macOS-only** (it is macOS-only software) and the chip hides on Windows and Linux
- **Subject-first Studio** — pick freeform, your character, or your persona and the prompt auto-fills; technical settings tuck away until you want them
- **Expression packs** — a full matching emotion set from one portrait, with an optional AI vision quality check
- **`/image` in chat** — paint the current scene (or anything else) as a picture bubble, with live in-progress preview
- **Reference images & editing** — img2img with a denoise slider on all local backends, plus a dedicated Edit mode with its own settings
- Live model switching, LoRA injection with **family-compatibility guard**, **Natural Language or Danbooru Tags** prompt modes

### 📖 Porch Stories — Novel Generator
- Distill character chats into a coherent storyline timeline
- 5-stage autonomous pipeline: concept → outline → draft → edit → publish, with per-step tuned generation (disciplined planning, creative prose)
- Step-by-step creation wizard and a skeuomorphic page-flip reader with audiobook TTS read-along

### 📱 Web & Phone App
- The whole porch in your browser: an installable web app (PWA) served straight from the desktop app to your home network
- Chat, characters, stories, images, Impersonate, chat import/export, and the full **Stoop** hub — in the same warm-porch look, laid out properly for both desktop browsers and phones
- Fast over slow connections (right-sized thumbnails, smart caching) and self-healing after your phone sleeps
- Built-in web login management — change or recover it, or sign out all devices, from desktop Settings

### 💾 Local Backups *(replaced Cloud Sync)*
- Two-tier rolling local backups (30-minute snapshots + one per day for 7 days), written by the database engine itself, with one-click restore. **Cloud Sync was removed** in favor of these.

### 🎭 Character Expressions
- **Emotion-driven avatar swapping** — the character's portrait changes in real time as their mood shifts during the conversation
- **Two classification paths**: a lightweight **ONNX model** (distilbert, fully offline, ~300 ms) or the **LLM path** via the Realism Engine for deeper contextual accuracy
- **Generate a pack in-app** — the Image Studio can paint a full expression set from one portrait, so any character can have live expressions
- **26 emotion categories** mapped to your character's expression image set (compatible with SillyTavern expression packs)
- **Sidebar and fullscreen display modes** — float the expression portrait or dock it beside the chat, with an optional emoji burst on mood changes

### ⚙️ KoboldCpp Integration
- Automated download and update of the KoboldCpp backend — including an automatic compatible build for older CPUs without AVX2
- Hardware detection — Vulkan on PC, Metal on Apple Silicon, Intel ARC support, **Nvidia Blackwell (RTX 50-series) support**
- Model Hub: search and download GGUF models directly from HuggingFace
- **Thinking models think** — Request Reasoning works on local models, with the reasoning shown in a collapsible block. Models that have no thinking mode say so instead of showing three chips that do nothing
- **Honest live status** — real prompt-reading progress and "waiting" reasons on KoboldCpp, oMLX, and LM Studio
- **Advanced Launch Options** — Flash Attention, Context Shift, mlock, GPU ID selector, prefill batch size, `.kcpps` preset support, and per-model vision (mmproj) attachment

---

## 📥 Install

### Linux — Package Manager

**Debian / Ubuntu / Mint / Pop!_OS**
```bash
curl -fsSL https://apt.frontporchai.app/install.sh | bash
sudo apt install front-porch-ai
```
Or manually:
```bash
curl -fsSL https://apt.frontporchai.app/front-porch-ai.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/front-porch-ai.gpg
echo "deb [signed-by=/etc/apt/keyrings/front-porch-ai.gpg] https://apt.frontporchai.app stable main" | sudo tee /etc/apt/sources.list.d/front-porch-ai.list
sudo apt update && sudo apt install front-porch-ai
```

**Fedora / RHEL / openSUSE**
```bash
sudo dnf config-manager --add-repo https://rpm.frontporchai.app/front-porch-ai.repo
sudo dnf install front-porch-ai
```

**Arch Linux (AUR)**
```bash
yay -S front-porch-ai-bin        # Stable
```

Future updates arrive through your normal system updates (`apt upgrade`, `dnf upgrade`, `yay -Syu`).

### All Platforms — Manual Download

Head to the **[Releases](https://github.com/linux4life1/front-porch-ai/releases)** page for the stable installers: `.exe` (Windows), `.pkg` (macOS), `.AppImage` / `.deb` / `.rpm` (Linux).

---

## ⚙️ Configuration

1. **Backend** — go to **Settings → Download Backend** to fetch KoboldCpp, or point it at an existing binary. First launch also asks: built-in engine, or do you already have OpenRouter / oMLX / LM Studio / another API?
2. **Model** — go to **Manage Models → HuggingFace Search**, find a GGUF model (recommended: `Q4_K_M` or `Q5_K_M`), download.
3. **Optimize** — hit **Auto-Configure** to let the app pick the best GPU layer split and thread count for your hardware.

---

## 🤝 Contributing

Pull requests are welcome! If you're a dev reading this far down, here's what you need to know:

- **Branch workflow:** Two branches. All work (features, fixes, experiments) targets **`Rawhide`**. `main` is tagged stable releases only. There is no `dev` line and no beta series. See [CONTRIBUTING.md](CONTRIBUTING.md).
- **Nightly / scheduled builds & schedule triggers:** Automatic builds are powered by `.github/workflows/nightly.yml`. GitHub **only** reads `on: schedule:` from the default branch (`main`). A current copy of the workflow (especially the version-patching step) must live on `main`, otherwise nightly compiles will fail. The job typically checks out the active development branch for source, but the workflow definition itself always comes from `main`.
- **Commit conventions:** Follow the guidelines in [CLAUDE.md](CLAUDE.md) for commit message format, code style, and naming conventions.
- **Full guide:** See [CONTRIBUTING.md](CONTRIBUTING.md) for build instructions, testing requirements, and the PR template.
- **Before you PR:** Run `flutter analyze` and `flutter test` locally. The project is now at 0 warnings on the active rules. CI analyzes only changed `.dart` files on PRs (plus a full scheduled lint job). Introducing new warnings will fail CI.

---

## 📝 Note from the Dev

If you've shown up with bug reports, cards, kind words, or just a night on the porch — thank you. The **[DreamersAI Discord](https://discord.gg/e4tET6rpdv)** carried this from the first push. Particular thanks to **PapaOak**, **Pacmanincarnate**, and **Vanta**.

— **SosukeAizen** on Discord

---

## 🙏 Credits

Front Porch AI stands on the shoulders of these incredible open-source projects:

| Project | What It Does | Link |
|---|---|---|
| **KoboldCpp** | The local LLM backend. Single-file, GGUF-native, GPU-accelerated. | [GitHub](https://github.com/LostRuins/koboldcpp) |
| **sherpa-onnx** | Runs Whisper speech-to-text and the local TTS voices in-process. | [GitHub](https://github.com/k2-fsa/sherpa-onnx) |
| **Kokoro** | Default TTS engine. Beautiful offline voices via ONNX. | [GitHub](https://github.com/hexgrad/kokoro) |
| **Piper** | Fallback TTS engine. Fast, lightweight, privacy-respecting. | [GitHub](https://github.com/rhasspy/piper) |

If Front Porch AI is useful to you, please consider starring these projects too — they're the foundation everything is built on.

---

## 🔒 Privacy

The app is **local-first**: using it offline collects nothing and sends us nothing. The **only** part that involves an account or data collection is **The Stoop** — the optional online community hub — and only if you sign in and use it. The Stoop then handles your account info, the cards you choose to upload, a salted **hash** of your IP for anti-abuse (never the raw IP), and an **opt-out** anonymous device-stats ping (no chats, characters, or IP). Full details: [Privacy Policy](PRIVACY.md).

## 🤝 Contributors

Front Porch AI is built by [@linux4life1](https://github.com/linux4life1), with help from the community — thank you:

**Code — pull requests & fixes**

- [@S-A-M-F](https://github.com/S-A-M-F)
- [@willie](https://github.com/willie)
- [@MisterLotto](https://github.com/MisterLotto)
- [@dazpants1](https://github.com/dazpants1)
- [@bigsombar](https://github.com/bigsombar)

**Testing & feedback**

| Contributor | Role |
|---|---|
| **Hakko504** | Bug Testing, UI/Feature Suggestions |
| **PacmanIncarnate** | Bug Testing, UI/Feature Suggestions |
| **SunTzucious** | Beta Testing |

Want to pitch in? Start with [CONTRIBUTING.md](CONTRIBUTING.md).

## 📄 License

**v0.9.0+** — [AGPL-3.0](LICENSE)  
**v0.8.x and earlier** — GPL-3.0

---

## 🛠️ Build from Source

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Git
- Windows, Linux, or macOS

That's the whole list — every AI engine (TTS, STT, character expressions, RAG memory embeddings, the Draw Things client) runs **in-process** via ONNX/native libraries that ship with the app's packages. There are no sidecar binaries to build, no Rust, no Python.

### Linux Extra Dependencies

**Ubuntu/Debian**
```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev libunwind-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

**Arch Linux**
```bash
sudo pacman -S clang cmake ninja pkgconf gtk3 xz libsecret gstreamer gst-plugins-base
```

**Fedora**
```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libsecret-devel gstreamer1-devel gstreamer1-plugins-base-devel libstdc++-devel
```

### Build & Run

```bash
git clone https://github.com/linux4life1/front-porch-ai.git
cd front-porch-ai
flutter pub get
flutter run
```

**Release build:**
```bash
flutter build linux    # or windows, or macos
```
That's it — the built bundle is self-contained.

---

<details>
<summary><strong>📦 Old Release Notes</strong></summary>

### v0.9.9.1

Powerful new tools plus a far more reliable Realism Engine and group experience.

**🎨 Image Studio – First-Class Experience**
- Full integrated studio (no more popups or separate dialogs). Buttons for Visualize Scene, Character Portrait, Chat Background, Custom, etc.
- Configure everything inside: models/LoRAs, style, negative, steps, CFG, advanced DT settings.
- Visualize Scene pulls the most recent chat messages so images match what's happening right now.

**🧠 Realism Engine & Needs – Dramatically More Reliable**
- Bond, Trust, and Lust deltas consistently appear in chips and reflect actual changes.
- Group chats correctly track per-speaker needs, decay, scene rewards, and sidebar/cards.
- Dedicated Needs tab in group settings + editable per-character realism baselines.
- Fixed missing needs reactions, double-firing post-gen checks, state bleed on new chats/forks/imports.

**✨ Editor & Prompting**
- Live syntax highlighting + spellcheck in all editors with no typing lag.
- SillyTavern-style macros work inside cards, scenarios, and lorebooks.
- Unified lorebook editor across the whole app with quick enable/disable toggles.

**📤 Other**
- Export User Personas as SillyTavern-compatible JSON. Fixed Windows maximized window ghosting. Database Cleanup Tool for orphaned records.

### v0.9.8.1

- 🖼️ Fixed a crash when replacing a character's avatar in the full editor (especially on macOS — "Read-only file system" error).
- ☁️ Cloud Sync settings page now loads the real interface instead of a placeholder.
- 📖 Story engine handles floating-point numbers from AI models (e.g. `1.0` instead of `1`) — generation is much more stable across different models.
- 🔊 Emojis stripped before sending to TTS. "Test Voice" now respects the "Only narrate quotes" setting.
- 🖼️ Increased local image generation timeout for slower models.

### v0.9.8

The headline feature is **Character Expressions** (live emotion portraits that swap as the conversation evolves), plus major Realism Engine maturation, a much more robust Kokoro TTS experience, `.kcpps` preset support, custom chat backgrounds, Google Fonts picker, expanded bond/trust/arousal ranges, and dozens of stability fixes.

### V0.9.7.5

Complete character editor redesign with a 4-tab layout (Details, Dialogue, Lorebook, Worlds), glassmorphic section cards, Realism Engine settings editable directly in the character editor, and several crash/data-integrity fixes.

### V0.9.7.3

Learned Facts quality overhaul, full Web UI parity for the character creator, and phased Realism Engine improvements for more natural character behavior.

### V0.9.7.2

Community-contributed fixes and features — thanks to [@willie](https://github.com/willie): proper `"system"` role on chat-completion APIs, LM Studio streaming fix with `reasoning_content` support, macOS RAG embedding server bundling, settings tab bar styling, BYAF importer cache fix, pubspec version format fix.

### V0.9.7.1

Realism Engine prompt overhaul (personality-aware evaluations, emotion vocabulary guidance, spatial continuity, dramatic event inertia, trust rebalance), Chaos Mode timing rework, KoboldCpp stability for thinking models.

### V0.9.7

**Chance Time — Chaos Mode**: spinning wheel overlay, 175+ era-agnostic events across four categories, escalating pressure, category-specific reveal animations, manual spin.

### V0.9.6.6

Deterministic time progression (every 6 AI turns), OOC time-skip detection, manual time nudge chevrons.

### V0.9.6.5

Realism Engine 2.1: emotion inertia, trust-based behavioral calibration, narrative day-of-week tracking, post-greeting baseline eval. Redesigned processing overlay.

### V0.9.6.3 / V0.9.6.4

Realism Engine 2.0 (long-term relationship scaling, dynamic trust), streaming eval UI, native desktop spell checking (macOS `NSSpellChecker`, Windows `ISpellChecker`).

### V0.9.6 – V0.9.6.2

Realism Engine 1.0 (relationship & tension, emotion wheel, autonomous time). Local image generation (A1111, Forge, SDNext, Draw Things). Easy Mode Quick Create. World Lore RAG. Settings UI overhaul.

### V0.9.5

Group chat fork from 1:1 conversations. Database power-failure protection (SQLite FULL sync + integrity check). Automatic rolling backups every 10 minutes.

### V0.9.0 – V0.9.3

Database hard-delete optimization (334MB → 2MB). Full-featured Web UI. Voice Call Mode. Chat Summary. AI Character Creator. Push-to-Talk (Whisper STT). AGPL-3.0 license. RAG Memory. Character Evolution. Objectives/Goals. ElevenLabs TTS. Platform fixes.

### V0.8.x and earlier

SQLite database backend (migrated from JSON). Backup management. Backyard AI (.byaf) importer. Director Mode. Group chat. TTS multi-engine support. Chat branching. External API support (OpenRouter, Nano-GPT).

</details>

---

*Built with 🧡 using [Flutter](https://flutter.dev)*
