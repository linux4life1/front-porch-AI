# User Guide

The complete reference for Front Porch AI — every feature, explained in plain English.

This guide assumes the app is installed and an AI model is set up. If you're not there yet, start with the [Getting Started guide](getting-started.md) and the [Installation guide](install.md).

> **Tip:** Many actions have hotkeys — see [Keyboard Shortcuts](keyboard-shortcuts.md).

---

## Table of Contents

**Everyday chatting**
- [The Chat Screen](#the-chat-screen)
- [Message Tools](#message-tools)
- [Director Mode](#director-mode)

**Your characters & their world**
- [Characters](#characters)
- [Lorebooks & Worlds](#lorebooks--worlds)
- [Group Chats](#group-chats)
- [The Realism Engine](#the-realism-engine)
- [Long-Term Memory](#long-term-memory)

**Voice, images & stories**
- [Voice: Talking and Listening](#voice-talking-and-listening)
- [Image Generation](#image-generation)
- [Porch Stories (Novel Generator)](#porch-stories-novel-generator)

**Beyond the desktop**
- [The Stoop (Community Hub)](#the-stoop-community-hub)
- [Web & Phone Access](#web--phone-access)

**Settings & upkeep**
- [Generation Settings](#generation-settings)
- [Appearance](#appearance)
- [The AI Backend](#the-ai-backend)
- [Backups & Data Safety](#backups--data-safety)
- [Updates](#updates)
- [Getting Help](#getting-help)

---

## The Chat Screen

Click any character on the home screen and you're in a chat.

![The chat screen](screenshots/chat.png)

**What you're looking at:**

- **Top bar** — the character's avatar, name, and a short description. The back arrow returns you to your library. The chevron button opens or closes the right-hand sidebar.
- **The conversation** — your messages and the character's replies, on top of a scene background you can change (see [Appearance](#appearance)). If Character Expressions are enabled, the character's portrait changes as their mood changes.
- **Right sidebar** — the character's current emotional state, relationship bars, memory, lorebook triggers, Author's Note, and more. Sections expand and collapse so you only see what you care about.
- **Input bar** — where you type. Drag the grip to make it taller. **Enter** sends; **Shift + Enter** makes a new line.

**Sending a message:** type and press Enter. The reply streams in live, word by word — no waiting for the whole thing. A red **Stop** button appears while the AI is writing; click it any time to cut the reply short.

**Thinking models:** some AI models (like Qwen or DeepSeek) "think out loud" before answering. Front Porch tucks that private reasoning into a collapsible "Thought" chip above the reply — tap it if you're curious, ignore it if you're not.

---

## Message Tools

Every reply comes with a toolkit. Hover over (or long-press) a message to see it.

### Regenerate & Swipes

Didn't like the reply? **Regenerate** asks for a completely new one — and the old version isn't thrown away. Each alternative is saved as a **swipe**. When a message has more than one version, ◀ ▶ arrows appear so you can flip between them instantly and keep whichever you like best.

### Continue

Tells the AI "keep going" from where the reply left off. Handy when a response got cut short or you want a longer scene.

### Impersonate

The magic-wand button asks the AI to write *your* next message for you. You can type a few words first to steer it. Great for when you're stuck.

### Edit

Click a message (yours or the character's) to rewrite it. The story continues from your edited version — a clean way to fix small details without restarting.

### Delete

Deleting a message removes that whole turn — and it also **rolls back any Realism Engine changes** that message caused. If a reply tanked your character's trust, deleting it undoes the damage too.

### Suggest Actions

The lightbulb button asks the AI for four short, clickable ideas for what you could do next ("Ask about her day", "Suggest moving somewhere private"…). Click one and it's sent as your message. Perfect for keeping momentum when you're not sure what to say.

### Branching

You can fork a chat from any point to explore a "what if" storyline, leaving the original untouched.

---

## Director Mode

Director Mode turns you from a participant into the director of the scene. Characters respond to each other on their own — you sit back and steer.

- Toggle it from the chat sidebar. The input bar changes to **"Direct the scene..."** — anything you type becomes a stage direction rather than dialogue ("Suddenly the power goes out", "Time skip to the next morning").
- A **delay slider** controls the pacing between turns, so a scene unfolds at reading speed instead of all at once.
- In group chats with auto-advance on, a play/pause button gives you hands-free ensemble scenes.

Pair Director Mode with auto-playing voice and Character Expressions and you get something close to ambient theater — characters talking, portraits shifting with their moods, while you drop in a note whenever you want the story to turn.

---

## Characters

Your library lives on the home screen. For everything about creating, importing, and editing characters — including the AI Quick Create wizard and card format details — see the dedicated [Characters guide](characters.md). Here's the short version.

![The character library](screenshots/home_new.png)

- **Create** — build a character by hand with the step-by-step creator, or type a one-line concept and let the AI write the whole card (personality, first message, example dialogue, even a matching avatar).
- **Import** — PNG character cards, JSON files, Backyard AI archives, and in-app browsing of community card sites all work. Multi-file and whole-folder import supported.
- **Edit** — open any card to change its personality, greetings, example dialogue, voice, lorebooks, and Realism Engine starting values.

![The character editor](screenshots/editor.png)

**Staying organized:**

- **Folders** — enter Organize mode from the toolbar, select characters, and move them into folders (folders can nest; breadcrumbs help you navigate).
- **Tags** — label characters freely and filter by tag in search.
- **Search** — the search bar matches names and descriptions, and you can scope it to the current folder, that folder plus subfolders, or your whole library.
- **Zoom** — a grid slider makes cards bigger or smaller to suit your collection.

---

## Lorebooks & Worlds

Lorebooks are how you give a character knowledge that never gets forgotten — backstory, places, factions, rules of magic, anything the AI should know but that would bloat every message if you pasted it in.

**How they work:** each lorebook entry has trigger keywords and a chunk of text. When a keyword shows up in recent conversation, that entry's text is quietly slipped into what the AI reads before replying. Mention "the war", and the AI suddenly knows your world's history of it.

**Making entries:** open a chat's sidebar and expand the lorebook section, or manage them from the character editor. Each entry gets:

- **Keywords** — the words that wake it up
- **Content** — what the AI learns when triggered
- **Always active** — some entries can be marked constant so they're *always* in play
- **Trigger depth** — how far back in the conversation the app looks for keywords

Entries that are currently active are highlighted, so you always know what the AI can "see."

**Worlds** are containers that bundle lorebooks together — a shared universe you can attach to many characters at once. Build a setting once, and every character who lives there knows its geography, politics, and history. World files from SillyTavern import cleanly.

**Rule of thumb:** character-specific facts go in the character's own lorebook; shared setting lore goes in a World.

---

## Group Chats

Put two or more characters in one room and they'll talk to you *and each other* — each with their own personality, voice, expressions, and Realism Engine state.

![A group chat](screenshots/group_chat_new.png)

**Creating a group:** on the home screen, use multi-select to pick your characters, then hit **Create Group**. Give it a name, an opening scenario, and choose how turns work.

![The group creator](screenshots/group_chat_creator.png)

**Turn order** comes in two flavors:

- **Round robin** — characters speak in a fixed rotation.
- **Random** — anyone might speak next.

Outside of full auto-play, a **next character** button in the toolbar shows who's up and lets you trigger their turn — or hand the reins over entirely with Director Mode and auto-advance.

Each member keeps their own lorebooks, relationship scores, needs, expression images, and voice. It's a real ensemble, not one AI wearing different name tags.

### A cast that changes mid-story *(currently in nightly builds)*

In nightly builds, a 1:1 chat and a group are the same chat with a different headcount — so you can change the cast **in place**, with your history and every character's memory and relationships intact:

- **`/join --full`** — turn the solo chat you're in into a group. The newcomer makes an entrance in their own voice and the story just continues.
- **`/join <name>`** — bring another character into an existing group. **`/promote`** upgrades a lightweight scene guest into a full member.
- **`/exit <name>`** — write someone out. They get a goodbye, and a one-tap **Undo** appears in case you regret it.
- **`/speak <name>`** — make a specific character take a turn right now.
- **`/turnorder`** — set exactly who speaks when, including your own slot (`/turnorder Mara, {{user}}, Kai`). On its own, it shows the current order.

When a group shrinks back to one character, it collapses into a clean 1:1 with the original character — no leftover copies — and they remember everything that happened in the group.

---

## The Realism Engine

The feature that makes characters feel alive instead of stateless. When it's on, the app quietly evaluates each exchange and updates what the character feels:

- **Bond & Trust** — closeness and reliability, each running from −300 to +300. Earn them slowly; lose them fast.
- **Emotion** — a current mood with momentum. Small moments cause small drift; it takes something real to swing a mood hard.
- **Arousal** — a −100 to +100 scale with its own pacing and recovery, for stories that go there.
- **Time** — scene time advances on its own (roughly every 6 replies), and you can nudge it with the ‹ › chevrons in the sidebar or skip ahead by writing something like *(OOC: we drive for several hours)*.
- **Needs** — a Sims-style layer: hunger, bladder, energy, social, fun, hygiene, comfort — each drifting realistically and coloring the character's behavior.
- **Fixations, objectives & evolution** — characters can develop obsessions, pursue their own goals, and organically grow new personality traits over long stories.
- **Chaos Mode** — optional random "Chance Time" events that shake up the scene when things get too comfortable.

Everything shows up in the chat sidebar — relationship bars, current mood, needs, the scene clock — and small chips under each reply show what changed and why.

You can switch the engine (or individual parts of it) on and off globally in Settings, per character in the editor, or per chat.

**The full deep-dive — every system, number, and tuning knob — lives in the [Realism Engine guide](realism-engine.md).**

---

## Long-Term Memory

Front Porch gives characters real long-term memory, entirely on your machine — no cloud.

**How it works:** as you chat, the app converts stretches of conversation into compact "memory fingerprints" using a small local AI model (you'll be offered a quick one-time download when you first enable it). When the character replies, the app finds the most relevant old memories and slips them into what the AI reads. The result: characters recall promises, inside jokes, and events from dozens of sessions ago.

**Where to see it:** expand the **Memory** section in the chat sidebar to browse what's stored, including a **Data Bank** for reference material and the sources behind each recall. The **Context Viewer** shows you the *entire* package the AI actually received — messages, memories, lorebook entries, and Realism state — which is the single best tool for understanding why a character said what it said.

The app also writes periodic **chat summaries** and can learn standing **facts** about you ("has a cat named Luna") that persist across conversations.

---

## Voice: Talking and Listening

### Text-to-Speech (the characters talk)

Four voice engines are supported — pick globally or per character:

| Engine | Runs | Cost | Notes |
|---|---|---|---|
| **Kokoro** | On your machine | Free | The default. 50+ natural voices across 9 languages. |
| **Piper** | On your machine | Free | Lightweight local fallback. |
| **ElevenLabs** | Cloud | Paid key | Outstanding emotional delivery. |
| **OpenAI** | Cloud | Paid key | Natural cloud voices. |

![Voice settings](screenshots/tts_settings.png)

**The settings that matter:**

- **Auto-Play** — new replies are spoken automatically. The heart of hands-free sessions.
- **Only narrate "quotes"** — reads just the spoken dialogue, skipping narration.
- **Ignore \*text inside asterisks\*** — skips action text entirely.
- **Kokoro workers** — for long narration, extra resident voices (2–4 is the sweet spot) keep audio flowing without stutters.

Every character can have their own voice, and in group chats each member speaks with theirs. A small speaker icon on any message replays it.

### Speech-to-Text (you talk)

Voice input runs on Whisper, locally — nothing you say leaves your computer.

- **Push-to-talk** — hold the microphone button, speak, release. Your words appear in the input box ready to edit or send.
- **Voice Call Mode** — the green call button starts a hands-free conversation: the app listens, sends when you pause, the character answers out loud, and the loop continues until you hang up.

Bigger Whisper models are more accurate (especially with names and accents) but slower; smaller ones are snappy. Choose in Settings — models download automatically the first time.

---

## Image Generation

Front Porch connects to image generators so your story can have faces and places:

- **Automatic1111** — the popular local Stable Diffusion server (Forge and other A1111-compatible servers work through this option too)
- **Draw Things** — a great local option on Macs
- **Remote API** — a cloud image service, if you'd rather not run one locally

![Image generation](screenshots/local_image_gen.png)

Set your backend in Settings, then generate from chat or the Image Studio: character portraits, scene illustrations, chat backgrounds, avatars. The app can build prompts from the current scene automatically, and you can choose between **natural-language prompts** or **Danbooru-style tags** depending on what your image model likes. Model switching and LoRA support (small style add-ons for image models) are built in.

![Image generation settings](screenshots/local_image_gen_settings.png)

---

## Porch Stories (Novel Generator)

Porch Stories turns ideas — or your existing chats — into full illustrated novels. Switch the home screen into **Porch Stories** mode to see your story projects.

![A finished Porch Story](screenshots/Porch_stories_book.png)

**How a story gets made:** you give it a concept, and a pipeline of specialized AI passes takes it from there — building a story bible (characters, world, themes), structuring acts and chapters, then writing scene by scene with continuity checks along the way. You can let it run or step through stages yourself.

**Project settings include:** point of view, genre and mood, prose length, pacing, dialogue density, maturity rating — plus which of your characters appear and whether to import chat history so the novel builds on what actually happened between you.

**Match it to your hardware:** a quality tier setting adjusts how ambitious the writing instructions are — one for frontier cloud models, one for large local models (70B+), one for small/mid local models — so the pipeline works whether you're on a laptop or an API.

Finished stories open in a page-flip book reader with optional read-along narration, and can be exported (including EPUB and audiobook generation via your TTS voices).

---

## The Stoop (Community Hub)

*(currently in nightly builds)*

The Stoop is a community character hub built into the app — browse, share, and download character and group cards without ever opening a browser.

- **Browse & discover** — featured and moderator-picked cards, search, tag filters.
- **One-tap download** — cards land in your library ready to chat.
- **Whole group casts travel** — sharing a group brings its members, avatars, lorebooks, *and* their pre-set Realism and Needs state. The scene arrives alive, not flattened.
- **Follow & vote** — follow creators you like, upvote what's good, report what breaks the rules.

The Stoop is **opt-in** and account-gated, strictly **18+** (adult content hidden by default), with optional two-factor authentication. It's the only part of the app that goes online — everything else stays local. If you never touch it, nothing about your setup changes.

---

## Web & Phone Access

Your desktop runs the AI — but you can chat from any browser, including your phone on the couch.

**Turning it on:** Settings → **Web Server** → **Enable Web Server**. A guided setup walks you through the rest and shows a **QR code** — scan it with your phone and you're in.

**On your own network (LAN):** works immediately — any device on the same Wi-Fi can connect.

**Away from home:** the guided setup recommends **Tailscale**, a free private network between your own devices. The app checks whether Tailscale is installed and signed in, walks you through fixing whatever's missing, and can set up HTTPS so you get a clean, secure address that works from anywhere — no router fiddling, nothing exposed to the public internet.

**Security:** web access is protected by a password (in the newest builds you set it right in the browser the first time you connect), with per-device sessions, optional two-factor authentication, and a desktop-side recovery option that can sign out all devices or reset the web login if you ever get locked out.

The web app covers the full chat experience — conversations, characters, generation — kept in sync with the desktop.

---

## Generation Settings

These control *how* the AI writes. Open them from the gear icon in a chat. Defaults are sensible — tweak one thing at a time.

- **Temperature** — creativity dial. Lower (0.6–0.8) is focused and consistent; higher (1.0+) is wilder. Around 0.8 suits most roleplay.
- **Min-P / Top-P** — filters that decide which words the AI is even allowed to consider. Min-P around 0.05–0.1 is a modern, reliable choice.
- **Repetition penalty** — discourages the AI from repeating itself. Small values (1.05–1.15) help; big ones make speech stilted.
- **Max response length** — a cap on reply length, in tokens (word-pieces — roughly ¾ of a word each).
- **Advanced samplers** — dynamic temperature, XTC, and friends, each with a tooltip explaining what it does. Safe to experiment; easy to reset.

**Two steering tools worth knowing:**

- **System Prompt** — permanent hidden instructions ("always write in third person"). Set per character or per chat.
- **Author's Note** — temporary scene direction the character experiences as part of *now* ("it's raining hard; she's exhausted"). Lives in the chat sidebar; edit it mid-scene any time.

> **Note:** if a KoboldCpp launch preset (`.kcpps` file) is active, it controls context size and related values — the app locks those fields and shows a tooltip explaining why.

---

## Appearance

Make it yours, in Settings and the UI options:

![Settings](screenshots/new_settings.png)

- **Theme** — dark or light.
- **Chat backgrounds** — a built-in set of scenes (cozy library, cyberpunk bedroom, cherry blossoms, beach, coffee shop, rooftop sunset, and more) plus your **own uploaded images**, nameable per chat.
- **Chat fonts** — pick from a set of quality fonts (Roboto, Open Sans, Lato, Nunito, Merriweather, and others), applied live.
- **Bubble colors** — per-character message colors that persist, even in PNG chat exports.
- **Expression display** — show the character's live portrait docked in the sidebar or as a fullscreen overlay.
- **Grid zoom** — resize library cards to taste.

The app remembers your window size and position between sessions.

---

## The AI Backend

The "backend" is whatever actually runs the AI model. Front Porch supports two kinds, switchable any time.

### Local (KoboldCpp) — private and free

The app downloads and fully manages KoboldCpp for you — no command line, ever. Your hardware is detected automatically (NVIDIA, Apple Silicon, AMD, Intel, or plain CPU) and the right acceleration is chosen.

![The Model Hub](screenshots/model_hub.png)

- **Model Hub** — search Hugging Face for GGUF models (the standard file format for local AI), see sizes and memory estimates, download in one click. Models you already have are picked up automatically.
- **Auto-configuration** — the app suggests how much of the model to put on your graphics card and how long its memory (context) should be, based on your hardware.
- **Advanced launch options** — a collapsible panel for the tinkerers: Flash Attention, Context Shift, memory locking, GPU selection, batch size — all with sane defaults if you never touch them.
- **Launch presets** — `.kcpps` preset files are supported; when one is active it takes charge of launch settings.
- A **log viewer** is there when you want to see what the engine is doing under the hood.

### Remote APIs — big models, no big GPU

Enter an API key and chat through **OpenRouter**, **Nano-GPT**, **OpenAI**, or any OpenAI-compatible service. Useful when you want frontier-class models, or on hardware that can't run local ones. Many people mix: local for daily chat, remote for character creation or story generation.

For hardware advice and model recommendations, see [Getting Started](getting-started.md#powering-the-ai-local-or-remote).

---

## Backups & Data Safety

Your characters and chats are irreplaceable, so the app protects them automatically — no setup, no account, no cloud.

**How it works:** every **30 minutes**, a snapshot of your entire database is saved locally. Retention is two-tier:

- the **10 newest snapshots** are always kept (fine-grained coverage of the last several hours), *plus*
- **one snapshot per day for the last 7 days** (so you can roll back to "yesterday" or "last Tuesday").

Old snapshots beyond those rules are pruned automatically, so backups never eat your disk.

**Managing them:** open **Backups & Restore** from the sidebar. You can **Create Backup Now** before anything risky, and **Restore** any snapshot with one click.

**Moving to a new computer:** export your characters as card files and import them on the other machine — or copy your whole data folder. Backup snapshots can also be restored on a fresh install.

> **What happened to Cloud Sync?** Older versions offered syncing through Google Drive or WebDAV. It could occasionally resurrect deleted data across devices, so I retired it: it's deprecated in the current stable release and removed entirely in nightly builds. Automatic local backups are the replacement — and for sharing characters between machines or with others, card export/import and The Stoop do the job better.

---

## Updates

The app checks GitHub for new releases and shows a friendly update dialog with what's new — download when you're ready, and the installer is staged to run for you. Update checks contact only GitHub.

Stable installs are only ever offered stable updates. Nightly builds are their own separate track (and keep separate data, so they can't touch your stable library). Full history lives in the [release notes](release-notes.md).

---

## Getting Help

- **[FAQ](faq.md)** — quick answers to the most common questions.
- **[Troubleshooting](troubleshooting.md)** — fixes for GPU, model, import, and audio issues.
- **[Discord](https://discord.gg/e4tET6rpdv)** — the friendliest place to ask anything, share characters, and talk to me (I'm the developer) directly.

---

*Everything above runs on your machine, on your terms. Enjoy the porch.* 🪑
