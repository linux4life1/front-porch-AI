# Getting Started

Welcome to Front Porch AI — a private, offline-first AI chat application for desktop.

---

## Table of Contents

1. [What Is Front Porch AI?](#what-is-front-porch-ai)
2. [System Requirements](#system-requirements)
3. [Installation](#installation)
4. [First Launch](#first-launch)
5. [Setting Up Your AI Backend](#setting-up-your-ai-backend)
6. [Your First Chat](#your-first-chat)
7. [Importing Characters](#importing-characters)
8. [Next Steps](#next-steps)

---

## What Is Front Porch AI?

Front Porch AI is a warm, privacy-first desktop companion that lets you chat, roleplay, and tell stories with AI characters — all running completely on *your* computer.

Built with Flutter for smooth native performance, it works beautifully on Windows, macOS (Apple Silicon recommended), and Linux. The app uses powerful local language models through KoboldCpp (automatically managed for you) or optional remote APIs like OpenRouter when you want access to the biggest frontier models. No subscriptions. No data sent to the cloud unless you explicitly choose to.

At its heart is immersive character chat with **persistent memory** and the groundbreaking **Realism Engine** — a system that tracks how characters feel, how much they trust you, their evolving relationships, the passage of time in the story, and even lets them develop new traits organically as your conversations unfold. Add voice (local Kokoro TTS + Whisper STT or premium cloud voices), group chats, local image generation, and **Porch Stories** (a full novel generator that turns your chats into beautiful illustrated books), and you have a complete private storytelling studio.

Everything is free and open-source under the AGPL-3.0 license. Your characters, chats, and memories stay on your machine. Join the friendly community on Discord for help, sharing cards, and feedback.

> **Privacy promise:** By default, nothing leaves your PC. Cloud sync (Google Drive / WebDAV) and remote APIs are strictly opt-in.

---

## System Requirements

Front Porch AI runs well on a wide range of hardware thanks to excellent support for GPU acceleration backends.

### Quick Reference

| Component       | Minimum                          | Recommended                                      |
|-----------------|----------------------------------|--------------------------------------------------|
| **Operating System** | Windows 10, macOS 11+, Ubuntu 20.04+ / Fedora / Arch | Latest stable releases                          |
| **RAM**         | 8 GB                             | 16 GB+ (32 GB ideal for 13B+ models)             |
| **GPU / Acceleration** | Any Vulkan or Metal capable GPU, or CPU fallback | NVIDIA RTX 3060 / 4060 (8 GB+ VRAM), Apple M1/M2/M3/M4, AMD RX 6000+ with ROCm or Vulkan |
| **Storage**     | 10 GB free                       | 50 GB+ (room for several GGUF models + voices)   |

### GPU Acceleration Notes
- **NVIDIA**: CUDA (CuBLAS) + Flash Attention — best performance on 20-series and newer.
- **Apple Silicon**: Native Metal backend — excellent efficiency and full layer offloading on M-series chips.
- **AMD**: ROCm (Linux, best) or Vulkan (widest compatibility).
- **Intel / Others**: Vulkan or CPU mode with AVX2/AVX-512 optimizations.
- **CPU-only**: Fully supported and usable for smaller or heavily quantized models.

The app runs hardware detection automatically on first launch and in Settings, suggesting optimal GPU layers and context sizes based on your VRAM.

For full details, driver setup tips (e.g., ROCm groups on Linux), and developer build instructions, see the complete [Installation Guide](install.md).

---

## Installation

Front Porch AI is available for Windows, macOS, and Linux.

### Fastest Way to Install
1. Head to the [GitHub Releases page](https://github.com/linux4life1/front-porch-AI/releases).
2. Download the latest **stable** build (`.exe` installer for Windows, `.dmg` for macOS, `.AppImage`/`.deb`/`.rpm` for Linux) or the **beta** standalone archives for early features.

### Linux Users — Package Managers (Recommended)
- **Debian / Ubuntu / Mint / Pop!_OS**: One-line install script or APT repo (see install.md).
- **Fedora / RHEL / openSUSE**: Official RPM repo via DNF.
- **Arch Linux**: `front-porch-ai-bin` (stable) or `front-porch-ai-beta-bin` on the AUR.

Full instructions, including developer setup (Flutter + Rust + Python sidecars), driver troubleshooting, and post-install steps for the embedding server, are in the **[Installation Guide](install.md)**.

> **Beta note**: Beta builds use a completely separate data folder (`FrontPorchAI-Beta`) so they never touch your stable characters or chats. Perfect for testing new features safely.

---

## First Launch

When you launch Front Porch AI for the very first time, a sleek dark overlay appears over the main window titled **"Starting Front Porch AI"** with a sparkling icon. This is the automatic setup process — no manual wizard to click through.

### What Happens Automatically

1. **Backend Check** — The app looks for the KoboldCpp inference engine (the program that actually runs your local AI models). If it's not present in the app's private `bin` folder, it begins downloading the correct build for your operating system and GPU.

2. **Hardware Detection** — In the background, `HardwareService` probes your GPU vendor, VRAM amount, system RAM, and available acceleration APIs (CUDA, Metal, ROCm, Vulkan). This information is used later to pick smart defaults for GPU offloading and context size.

3. **Backend Download** (if needed) — You'll see a progress bar and status messages ("Downloading Backend...", "Connecting to GitHub...", percentage). The download is typically 80–250 MB depending on the optimized binary (CUDA, ROCm, or generic Vulkan). Intel Macs are automatically skipped — local inference is not supported on them, so the app heads straight to remote API mode.

4. **Autostart** — If you previously used local mode and have a model selected, the backend may start automatically so you're ready to chat immediately.

5. **Main Interface Appears** — The overlay fades away and you're greeted by the beautiful character library (the "home" screen).

If anything fails, the overlay shows a friendly error and offers **Retry Setup** or **Continue to App anyway** (you can configure everything manually in Settings later).

On the first launch of a **beta** build, you may also see an option to import a copy of your stable database so you have your existing characters available for testing.

### Your First View: The Character Library

![Front Porch AI home screen — character grid with search, folders, and import tools](../screenshots/home_new.png)

*This is what the main window looks like after setup completes. The grid shows all your characters, folders, and group chats. Use the top toolbar to create, import, search, or open the Model Hub and Settings.*

Hardware detection results and recommended settings are also visible (and re-detectable) in **Settings → AI Settings**.

You're now ready to set up your first AI model or jump straight into chatting if a model was already configured.

---

## Setting Up Your AI Backend

Front Porch AI gives you complete freedom in how you power the AI — fully local, fully remote, or a mix of both.

### Option A: Local Inference (KoboldCpp) — Recommended

KoboldCpp is a popular, highly optimized inference server for GGUF-format models (the standard for local LLMs). Front Porch AI **completely manages KoboldCpp for you**:

- On first launch (or when missing), the correct executable is auto-downloaded to a private `bin/` folder inside your app data.
- You never have to run command-line tools or edit launch scripts.
- The app can start and stop the backend on demand from within the UI (including from the Character Creator).

**The Model Hub (in-app Hugging Face browser)**

Open **Settings → AI Settings → Model Manager** (or the Model Hub button) to search and download models directly:

![Model Hub — search Hugging Face for GGUF models and download with one click](../screenshots/model_hub.png)

- Search by name, architecture, or tags (e.g., "llama-3.1", "qwen3", "mistral").
- See file sizes, quantizations (Q4_K_M, Q5_K_S, IQ4_XS, etc.), and VRAM estimates.
- One-click download with a beautiful progress overlay. Files land in your `models/` folder.
- Local models you already have (just drop `.gguf` files into the models folder) are automatically discovered.

**Hardware Acceleration — Smart Defaults**

The app detects your GPU on launch and in Settings and applies the best backend automatically:

- NVIDIA → CuBLAS (with Flash Attention)
- Apple Silicon (M1–M4) → Metal (often allows full offload of 7B–13B models)
- AMD on Linux → ROCm when available, otherwise Vulkan
- Everything else → Vulkan or pure CPU

You can fine-tune GPU layers, context size, Flash Attention, mlock, and more in the Advanced panel.

**Recommended Starting Models by Hardware**

| Your Hardware          | Suggested Models (GGUF)                  | Typical Quant | Context | Notes |
|------------------------|------------------------------------------|---------------|---------|-------|
| 6–8 GB VRAM (or Intel iGPU) | Llama-3.1-8B, Mistral-7B, Phi-3-mini, Gemma-2-9B | Q4_K_M or Q5_K_S | 4k–8k | Excellent quality/speed balance |
| 12 GB VRAM             | Llama-3.1-8B/70B Q3, Qwen2.5-14B, Command-R | Q4_K_M       | 8k–16k | Great for longer stories |
| 16–24 GB VRAM          | 70B Q3/Q4, 34B models, DeepSeek-R1 32B | Q3_K_M or Q4 | 8k–16k+ | Reasoning models shine here |
| Apple M1/M2/M3 (16 GB+) | Most 7B–13B full offload possible       | Q4–Q6        | 8k+     | Very efficient |
| CPU only / low VRAM    | 3B–7B heavily quantized (Q3/Q2)         | Q4_K_S       | 2k–4k   | Still very usable for roleplay |

The app's Optimization Service will suggest good GPU layer counts and context sizes automatically based on detected VRAM.

### Option B: External / Remote API

Prefer the biggest models (70B–405B) or don't have a dedicated GPU? Switch to **remote mode** in Settings → AI Settings.

Supported providers:
- **OpenRouter** (recommended — huge catalog, cheap, fast)
- Any OpenAI-compatible endpoint (Nano-GPT, Together, Fireworks, Groq, etc.)
- Official OpenAI (for GPT-4o, o1, etc.)

Just enter your API key once. The app handles the rest. Generation is usually faster than local on modest hardware, and you get access to the absolute latest models.

**When to use remote:**
- You want maximum intelligence for character creation or complex plots
- Traveling / on a laptop without strong GPU
- You only chat occasionally and don't mind per-token costs

### Option C: Hybrid Workflow (Best of Both Worlds)

Many users run **local** for day-to-day roleplay (unlimited, private, no cost) and switch to **remote** only when:
- Using the AI Character Creator (the "Quick Create" button that writes full V2 cards from a short concept)
- Generating stories with Porch Stories
- Chatting with a character that benefits from a much smarter model

You can change the active backend at any time in Settings or even per-character in some flows. The last-used model and backend are remembered.

**Pro tip**: Start with the Model Hub + a good 7B or 8B Q4 model. Most people are amazed at how good modern small models are for immersive roleplay — and everything stays on your machine.

Full advanced configuration (including .kcpps presets, prefill batch size, and more) lives in the Settings page.

---

## Your First Chat

Ready to talk to your first character? It's delightfully simple.

### 1. Create or Choose a Character

From the home grid:

- Click the big **+ Create** button in the toolbar. The AI Character Creator opens — type a short concept ("a sarcastic Victorian inventor who loves tea and steam-powered gadgets") and let the app generate a complete, high-quality V2 card including description, personality, first message, example dialogue, and even a matching avatar and lorebook entries.

![AI-assisted character creation wizard](../screenshots/ez_char_creator.png)

- Or import a ready-made character (see the Importing section below).

- Once you have at least one character, simply **click its card** in the grid.

The app will open a chat session (creating a new one if none exists) and take you straight to the chat screen.

### 2. The Chat Screen

![Typical chat view with message history, input bar, and sidebar](../screenshots/chat.png)

- The **main area** shows the conversation. Your messages appear in one style, the character's replies in another (with rich formatting — dialogue in warm tones, actions in subtler text).
- The **right sidebar** shows the active character, Realism Engine stats (current emotion, bond level, trust, time of day), memory snippets, and quick generation settings.
- The **bottom input bar** is where the magic happens. It resizes as you type (drag the grip) and supports **Shift + Enter** for new lines.

### 3. Send Your First Message

1. Type something in the input box (e.g., *"Hello! It's a beautiful morning on the porch, isn't it?"*).
2. Press **Enter** (or click the paper-plane Send button).
3. Watch the response **stream in live** — tokens appear character-by-character as the model generates. No waiting for the whole reply.

**Special features you'll notice immediately:**

- **Reasoning / Thinking models** (Qwen3, DeepSeek-R1, etc.): Any `<think>...</think>` blocks the model produces are captured into a clean, tappable "Thought" chip above the visible reply. Tap it to read the model's private chain-of-thought.
- A **red Stop button** appears while generating — click it anytime to cut the response short.
- The Realism Engine (if enabled) quietly evaluates the character's emotional state, bond, and trust after each turn and updates the sidebar.

### 4. Message Controls (After the Reply Arrives)

Every AI message has handy controls:

- **Regenerate** (circular arrows): Generates a completely new version of that reply. All previous versions are saved as **swipes** — use the left/right arrows to swipe between them instantly without re-rolling the whole conversation.
- **Continue**: Tells the model "keep going" from where it left off (great for long scenes).
- **Impersonate** (magic wand): The AI writes what *you* might say next (optionally seeded with a few words you type first).
- Click any message to **edit** it directly. Changes are saved and the conversation continues from the edited point.
- **Fork** the chat from any point to explore "what if" branches (chat branching).

### 5. Fine-Tuning on the Fly

Click the gear icon in the chat or open **Settings → Generation** to adjust:

- Temperature, Top-P, Min-P, repetition penalty
- Max response length
- System prompt / Author's Note (per-character or global)
- Memory / RAG settings
- And many advanced samplers (XTC, dynamic temperature, etc.)

All settings are per-chat or can be saved as presets.

Your chats are **automatically saved** the moment anything changes. Close the app and come back later — everything is right where you left it.

That's it! You've just had your first private, local AI conversation. From here the experience only gets deeper with the Realism Engine, voice, expressions, and group chats.

See the [User Guide](user-guide.md) for Director Mode, advanced editing, lorebooks, and more.

---

## Importing Characters

One of Front Porch AI's greatest strengths is seamless compatibility with the massive ecosystem of existing characters.

### Supported Formats
- **PNG character cards** (the most common) — the image file itself contains the full V2 or V2.5 JSON data in a special chunk (Tavern / SillyTavern format).
- **Standalone JSON** files.
- Full **SillyTavern / Backyard AI** compatibility.

### How to Import Characters

1. On the home screen, click the **Import** button (folder-with-arrow icon) in the top toolbar.
2. In the file picker, select one or more `.png` or `.json` files (multi-select is supported).
3. For bulk imports, use the **folder import** option — point it at a whole directory of cards and the app will scan recursively for PNGs.

After import you can assign tags via a convenient dialog. The characters instantly appear in your library grid, ready to chat.

**Chub.ai In-App Browser**

Click the cloud-shaped **Chub** button in the toolbar to open an embedded browser directly to chub.ai. Browse, search, and click the download button on any card — it streams straight into your library with tags and metadata intact. No leaving the app, no manual saves.

**Drag & Drop**

On desktop platforms, you can drag PNG/JSON files from your file manager into the import dialog or use the system's native drag-to-select behavior in the picker.

### What Gets Imported?

Everything in the standard V2/V2.5 spec:
- Name, Description, Personality, Scenario, First Message
- Example Dialogue (few-shot)
- System Prompt & Post-History Instructions
- Alternate Greetings (multiple opening lines)
- Tags, Lorebooks, World info
- And Front Porch AI extensions (TTS voice assignments, expression image packs, Realism Engine notes, etc.)

Once imported, you can edit any field, regenerate parts with the AI editor, attach more lore, duplicate the card for experiments, or organize it into folders.

For the complete character card specification, advanced editing, lorebook creation, and the powerful AI Quick-Create workflow, read the dedicated **[Characters & Import Guide](characters.md)**.

---

## Next Steps

You've got the basics — now the real fun begins. Here's your personalized roadmap:

### For Immersive, Living Roleplay
Head straight to the **[Realism Engine guide](realism-engine.md)**. Learn how bond & trust, emotion states, autonomous time progression, character objectives, the Fixation Engine, and organic character evolution turn ordinary chats into deeply believable stories that remember and grow.

### For Building & Managing Your Roster
The **[Characters & Import](characters.md)** guide covers everything: the full V2/V2.5 spec, the AI-powered Quick Create & editor passes, lorebook generation, folder organization, tags, bulk operations, and expression image packs.

### Explore the Rest of the App
- **[User Guide](user-guide.md)** — the complete reference for group chats & Director Mode, TTS/STT voice setup, local image generation (A1111/Forge), Porch Stories novel generator, cloud sync (Google Drive & WebDAV), the web server, and every setting.
- **[Keyboard Shortcuts](keyboard-shortcuts.md)** — speed up your workflow with handy hotkeys.

### Need Help?
- **[FAQ](faq.md)** — answers to the most common questions ("Is it really private?", "Which model should I pick?", "Why is my character acting weird?").
- **[Troubleshooting](troubleshooting.md)** — GPU/driver issues, slow generation, import problems, database recovery, and more.
- **[Discord Community](https://discord.gg/e4tET6rpdv)** — the friendliest place to ask questions, share character cards, request features, and talk directly with the developer. Also on Matrix.

---

**Welcome to the front porch.**

Your characters are waiting. Your stories are yours alone. Everything runs locally, on your terms, with love for the craft of interactive fiction.

If you create something wonderful, the community would love to see it on Discord. Enjoy every moment. 🪑✨

