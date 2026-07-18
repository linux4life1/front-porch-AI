# Getting Started

Welcome to Front Porch AI — a private, offline-first app for chatting with AI characters, right on your own computer.

This guide walks you from a fresh install to your first conversation. No technical background needed.

---

## Table of Contents

1. [What Is Front Porch AI?](#what-is-front-porch-ai)
2. [What You Need to Run It](#what-you-need-to-run-it)
3. [Installing the App](#installing-the-app)
4. [Your First Launch](#your-first-launch)
5. [Powering the AI: Local or Remote](#powering-the-ai-local-or-remote)
6. [Your First Chat](#your-first-chat)
7. [Importing Characters](#importing-characters)
8. [Next Steps](#next-steps)

---

## What Is Front Porch AI?

Front Porch AI is a desktop app for Windows, macOS, and Linux that lets you chat, roleplay, and tell stories with AI characters — with everything running on *your* machine.

Out of the box, the app runs AI models locally, so your conversations never leave your computer. If you'd rather use a big cloud model instead, you can connect services like OpenRouter — but that's always your choice, never the default.

What makes it special:

- **The Realism Engine** — characters have moods, build trust with you, remember the passage of time, develop obsessions and goals, and grow new personality traits as your story unfolds.
- **Long-term memory** — characters recall details from conversations you had days ago.
- **Voice** — characters can speak (local text-to-speech with 50+ voices) and you can talk back (push-to-talk voice input). Cloud voices from ElevenLabs and OpenAI are optional extras.
- **Group chats** — put several characters in one scene and watch them interact.
- **Porch Stories** — turn your chats into full illustrated novels.
- **The Stoop** *(currently in nightly builds)* — a built-in community hub for sharing and downloading characters, without leaving the app.

It's free and open-source (AGPL-3.0). Your characters, chats, and memories stay on your machine.

> **Privacy promise:** By default, nothing leaves your PC. Remote AI services and The Stoop are strictly opt-in. If you do sign up for The Stoop, it stores your account info and the cards you choose to upload — the rest of the app stays fully local. Details in the [Privacy Policy](https://github.com/linux4life1/front-porch-AI/blob/main/PRIVACY.md).

---

## What You Need to Run It

Front Porch AI runs on a wide range of hardware. A gaming PC is great; a modest laptop works too.

| | Minimum | Recommended |
|---|---|---|
| **Operating system** | Windows 10, macOS 11+, or a recent Linux distro | The latest stable release of your OS |
| **Memory (RAM)** | 8 GB | 16 GB or more |
| **Graphics card** | Optional — the app can run on your CPU alone | A GPU with 8 GB+ of VRAM (its own memory), or an Apple Silicon Mac |
| **Disk space** | 10 GB free | 50 GB+ if you want room for several AI models and voices |

**About graphics cards:** a GPU makes the AI respond much faster, but it isn't required. The app detects your hardware automatically and picks the best setup for you:

- **NVIDIA cards** — fastest option, fully supported.
- **Apple Silicon Macs** (M1 and newer) — excellent performance, fully supported. *Intel Macs can't run local models — the app switches to remote mode for you (see below).*
- **AMD and Intel cards** — supported.
- **No GPU at all** — still works. Smaller models run fine on a CPU.

**No capable hardware?** No problem — skip local models entirely and connect a remote service like OpenRouter. You get access to the biggest models available, and the rest of the app works exactly the same.

---

## Installing the App

The short version:

1. Go to the [Releases page](https://github.com/linux4life1/front-porch-AI/releases).
2. Download the latest **stable** build — `.exe` installer for Windows, `.pkg` installer for macOS (signed & Apple-notarized, so Gatekeeper opens it without a fuss), `.AppImage` / `.deb` / `.rpm` for Linux.
3. Install and launch it.

On Linux you can also install through your package manager (recommended — updates arrive automatically). Full instructions for every platform, including package-manager setup, are in the **[Installation Guide](install.md)**.

> **Curious about new features early?** Nightly builds come out most days with the newest work — including The Stoop community hub. They use a completely separate data folder, so they never touch your stable characters and chats. Rough edges possible.

---

## Your First Launch

The first time you open Front Porch AI, a dark overlay titled **"Starting Front Porch AI"** appears. That's the automatic setup — there's no wizard to click through.

Here's what it does on its own:

1. **Checks for the AI engine.** The app uses KoboldCpp (the program that actually runs AI models on your computer). If it's not there yet, the app downloads the right version for your hardware — you'll see a progress bar. The download is typically a few hundred MB.
2. **Detects your hardware.** Your graphics card, its memory, and your system RAM are checked so the app can pick smart defaults.
3. **Opens your library.** The overlay fades and you land on the home screen — your character library.

If anything goes wrong, you'll get a friendly error with **Retry Setup** and **Continue to App anyway** buttons. You can always finish setup later from Settings.

*On an Intel Mac:* local models aren't supported, so the app skips the download and takes you straight to remote-API mode.

*On a beta or nightly build:* you may be offered the option to import a copy of your stable library so your characters are available for testing.

![Front Porch AI home screen — your character library](screenshots/home_new.png)

*The home screen after setup. Your characters, folders, and group chats live here. The toolbar at the top handles creating, importing, and searching.*

---

## Powering the AI: Local or Remote

You have complete freedom in how the AI itself runs — fully local, fully remote, or a mix.

### Option A: Local models (recommended)

The app manages everything for you. You never touch a command line.

To get your first model:

1. Open **Manage Models** from the left sidebar.
2. Search for a model by name — the search runs against HuggingFace, the main library of free AI models.
3. Pick one and click download. Each result shows the file size and an estimate of whether it fits your graphics card.

![Manage Models — search and download AI models with one click](screenshots/model_hub.png)

A few terms you'll see while browsing:

- **GGUF** — the file format local AI models come in. It's the only format you need.
- **Quantization** (names like `Q4_K_M`) — a compressed version of a model. Smaller numbers = smaller file and lower quality. **Q4** is the sweet spot for most people.
- **7B, 12B, 70B…** — the model's size in billions of "parameters." Bigger is smarter but needs more powerful hardware.

**What should you download first?**

| Your hardware | Start with |
|---|---|
| 6–8 GB graphics card, or Apple M1/M2 | A **7–9B** model at Q4 |
| 12–16 GB graphics card, or M-series Mac with 16 GB+ | A **12–14B** model at Q4 |
| 24 GB+ graphics card | A **20–70B** model (quantized) |
| CPU only / older laptop | A **3–7B** model at Q4 — smaller, but still fun |

Modern small models are genuinely good at roleplay. Most people are surprised. If you already have `.gguf` files from elsewhere, just drop them into the app's models folder and they'll show up automatically (you can change where that folder lives in Manage Models).

### Option B: Remote services

Prefer the biggest frontier models, or don't have the hardware? Connect a remote service in **Settings → Backend**:

- **OpenRouter** — popular, with a huge catalog of models.
- **Nano-GPT** and any other OpenAI-compatible service.
- **OpenAI** itself.

Enter your API key once and you're done. Remember: remote means your chat text is sent to that provider — that's the trade-off for the extra horsepower.

### Option C: Mix and match

Plenty of people run a local model for everyday chatting (free, private, unlimited) and switch to a remote model for heavy lifting — like generating a detailed new character or writing a Porch Stories novel. Switching backends takes a few seconds in Settings, and the app remembers your last setup.

---

## Your First Chat

### 1. Get a character

From the home screen you can:

- **Create one with AI** — click **AI Create**, type a short concept (*"a sarcastic Victorian inventor who loves tea"*), and the app generates a complete character: description, personality, greeting, sample dialogue, even a matching avatar and lore.

![The AI character creator](screenshots/ez_char_creator.png)

- **Build one by hand** — click **Create New** for the manual editor.
- **Import one** — see [Importing Characters](#importing-characters) below.

Once you have a character, click its card to start chatting.

### 2. The chat screen

![The chat view — conversation, input bar, and sidebar](screenshots/chat.png)

- The **middle** is your conversation. Dialogue and actions are styled differently so scenes are easy to read.
- The **right sidebar** shows the character's current emotion, your bond and trust levels, the story clock, and memory — all driven by the Realism Engine.
- The **bottom input bar** is where you type. **Enter** sends; **Shift + Enter** makes a new line. Drag its top edge to make it taller.

### 3. Send something

Type a greeting and press **Enter**. The reply streams in live, word by word. While it's generating, a red **Stop** button lets you cut it short at any time.

Two nice touches you might notice:

- If your model is a "thinking" model (one that reasons before answering), its private reasoning is tucked into a **Thought** chip above the reply — tap it if you're curious.
- After each reply, the sidebar quietly updates — mood shifts, bond changes, time passing. That's the Realism Engine at work.

### 4. Message controls

Every AI reply has controls:

- **Regenerate** — roll a fresh version. Old versions aren't lost: use the left/right arrows to flip between takes.
- **Continue** — "keep going" from where the reply stopped.
- **Impersonate** — the AI drafts *your* next message for you.
- **Edit** — click any message to change its text directly.
- **Fork** — branch the whole conversation from any point to explore a "what if."

### 5. Tweak as you go

**Settings → Generation** holds the dials: response length, creativity (temperature), repetition control, and more. The defaults are sensible — you don't need to touch anything to have a great time.

Everything auto-saves. Close the app mid-scene and pick it up tomorrow exactly where you left off.

---

## Importing Characters

Front Porch AI speaks the same character-card language as the rest of the community, so thousands of ready-made characters just work.

**Supported formats**

- **PNG character cards** — the standard format used by SillyTavern, Chub.ai, and friends. The character data is embedded inside the image itself.
- **JSON files** — the same data without the picture.
- **Backyard AI archives (`.byaf`)** — if you're coming from Backyard AI, your characters can escape here intact.

**How to import**

- Click **Import Card** on the home screen and pick one or more files.
- Use **Bulk Import** to point at a whole folder — it scans everything inside, subfolders included.
- Use **Import BYAF** for Backyard archives.
- Or browse **Chub.ai and aicharactercards.com in the built-in browser** — click download on any card there and it lands straight in your library, tags and all.

After importing you can tag, edit, duplicate, and organize characters into folders. Everything on the card comes across: personality, greetings, sample dialogue, alternate openings, and attached lorebooks.

For the full story on cards, the AI editor, and lorebooks, see the **[Characters Guide](characters.md)**.

---

## Next Steps

**Make it feel alive** → the [Realism Engine guide](realism-engine.md). Bond and trust, moods with momentum, story time, character goals, obsessions, chaos events, and Sims-style needs.

**Build your cast** → the [Characters Guide](characters.md). The card format, AI-assisted creation and editing, lorebooks, expression images, and organizing a big library.

**Explore everything else** → the [User Guide](user-guide.md). Group chats and Director Mode, voice setup, image generation, Porch Stories, backups, and using the app from your phone.

**Stuck or curious?**

- [FAQ](faq.md) — quick answers to common questions.
- [Troubleshooting](troubleshooting.md) — when something's not working.
- [Discord](https://discord.gg/e4tET6rpdv) — the friendliest place to ask. I read everything.

---

**Welcome to the front porch.** Your characters are waiting, and your stories are yours alone. 🪑✨
