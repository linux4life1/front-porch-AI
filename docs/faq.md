# Frequently Asked Questions

Straight answers to the questions I get most often. If yours isn't here, the [Discord community](https://discord.gg/e4tET6rpdv) is friendly and fast.

---

## Table of Contents

### General
- [Is Front Porch AI free?](#is-front-porch-ai-free)
- [Is my data private?](#is-my-data-private)
- [What platforms are supported?](#what-platforms-are-supported)
- [Do I need an internet connection?](#do-i-need-an-internet-connection)
- [What's the difference between Stable and Nightly builds?](#whats-the-difference-between-stable-and-nightly-builds)

### AI & Models
- [What AI models can I use?](#what-ai-models-can-i-use)
- [How do I choose a model?](#how-do-i-choose-a-model)
- [Can I use OpenAI / Claude / Google models?](#can-i-use-openai--claude--google-models)
- [Why is the AI slow?](#why-is-the-ai-slow)
- [Why does the AI repeat itself?](#why-does-the-ai-repeat-itself)

### Characters
- [Where can I find characters?](#where-can-i-find-characters)
- [Can I use my SillyTavern or Backyard AI characters?](#can-i-use-my-sillytavern-or-backyard-ai-characters)
- [Why isn't my character acting right?](#why-isnt-my-character-acting-right)

### The Stoop
- [What is The Stoop?](#what-is-the-stoop)
- [What data does The Stoop collect?](#what-data-does-the-stoop-collect)

### Voice
- [Why isn't the voice (TTS) working?](#why-isnt-the-voice-tts-working)
- [How do I get better-sounding voices?](#how-do-i-get-better-sounding-voices)
- [Why does voice call mode send my message too early?](#why-does-voice-call-mode-send-my-message-too-early)

### Realism Engine
- [What is the Realism Engine?](#what-is-the-realism-engine)
- [Does the Realism Engine slow down my chats?](#does-the-realism-engine-slow-down-my-chats)
- [How do I reset a character's bond and trust?](#how-do-i-reset-a-characters-bond-and-trust)

### Your Data & Devices
- [How do backups work?](#how-do-backups-work)
- [Where is my data stored?](#where-is-my-data-stored)
- [Can I chat from my phone or another computer?](#can-i-chat-from-my-phone-or-another-computer)
- [Can I sync between two computers?](#can-i-sync-between-two-computers)
- [How do updates work?](#how-do-updates-work)
- [How do I report a bug?](#how-do-i-report-a-bug)

---

## General

### Is Front Porch AI free?

Yes — completely free and open-source (AGPL-3.0 license). Download it, use it, modify it, share it. There's no paid tier, no subscription, and no account required for the app itself.

A few *optional* third-party services have their own costs if you choose to use them — for example OpenRouter (remote AI models, pay per use) or ElevenLabs (premium cloud voices). Everything built into the app is free.

### Is my data private?

**Yes.** Front Porch AI is local-first: your characters, chats, memories, and settings live in a folder on your computer, and using the app offline sends nothing anywhere. There are no ads, no trackers, and no crash reporting.

Three optional features involve the internet, and only if you turn them on:

- **Remote AI APIs** (OpenRouter and similar) — your prompts go to that provider. Check their privacy policy.
- **Cloud voices** (ElevenLabs, OpenAI) — the text being spoken goes to that provider.
- **The Stoop** — the community character hub. It's the only part of the app with an account or any data collection at all — see [What data does The Stoop collect?](#what-data-does-the-stoop-collect)

The full details are in the [Privacy Policy](https://github.com/linux4life1/front-porch-AI/blob/main/PRIVACY.md).

### What platforms are supported?

- **Windows** 10 and 11
- **macOS** — Apple Silicon (M-series) natively; Intel Macs can run the app but only with remote AI APIs (local models need Apple Silicon)
- **Linux** — install from the APT/RPM repos, the AUR, or grab an AppImage

See the [Installation Guide](install.md) for step-by-step instructions.

### Do I need an internet connection?

Only for the initial setup: downloading the app, the AI engine, and a model. After that, everything core works fully offline — chatting, memory, local voices, image generation with a local backend, all of it.

You need to be online for: remote AI APIs, cloud voices, The Stoop, and downloading new models.

### What's the difference between Stable and Nightly builds?

- **Stable** is the recommended download — tested, polished releases (currently v0.9.9.1.3).
- **Nightly** builds come fresh from active development every night. You get new features first — right now that includes **The Stoop** community hub and the ability to change a chat's cast on the fly — but you may also hit rough edges.

Beta and nightly builds keep their data in a completely separate folder (`FrontPorchAI-Beta`), so trying one never touches your stable characters and chats.

---

## AI & Models

### What AI models can I use?

**Local models (recommended for privacy):** any model in **GGUF format** — the standard file format for AI models that run on your own computer. That covers essentially every popular open model family: Llama, Mistral, Qwen, Gemma, Phi, DeepSeek, and many more. The built-in **Model Hub** lets you search and download them without leaving the app.

**Remote models:** with an API key you can use OpenRouter (which offers hundreds of models including the biggest frontier ones), or any other OpenAI-compatible service.

### How do I choose a model?

The app detects your hardware automatically and suggests sensible settings, but here's the plain-English version:

| Your computer | Good starting point |
|---|---|
| 6–8 GB of GPU memory | A 7–9B model at Q4 quality — great balance of speed and personality |
| 12–16 GB of GPU memory | A 12–24B model — noticeably better writing and consistency |
| 24 GB or more | 32B and up — excellent reasoning and character depth |
| Apple Silicon Mac (16 GB+) | Most 7–13B models run beautifully |
| No dedicated GPU | A small 3–7B model, or use a remote API |

Two terms you'll see everywhere:

- **"7B", "13B" etc.** — the model's size in billions of parameters. Bigger is smarter but needs more memory and runs slower.
- **"Q4", "Q5" etc.** — quantization, i.e. how compressed the model file is. Q4 or Q5 is the sweet spot; quality loss is tiny and the memory savings are huge.

The Model Hub shows an estimate of whether a model fits your GPU before you download it. When in doubt, start small — modern 8B models are shockingly good at roleplay.

### Can I use OpenAI / Claude / Google models?

Yes. Add an **OpenRouter** key in Settings → AI Settings and you get access to virtually every major model through one account. You can also point the app at any OpenAI-compatible service. Remote models work with everything — the Realism Engine, memory, voices, all of it.

### Why is the AI slow?

Almost always one of these:

- **The model is too big for your GPU**, so part of it spills over to regular RAM, which is much slower. Fix: use a smaller model or a more compressed version (Q4 instead of Q6/Q8), or lower the context size.
- **Too many GPU layers** — lower the GPU Layers setting so the model actually fits.
- **The app is running on CPU** without you realizing. Re-run hardware detection in Settings → AI Settings.
- **Very large context sizes** (16k+) cost speed and memory even before the model starts writing.

See [Troubleshooting → Generation is slow](troubleshooting.md#generation-is-extremely-slow) for the full checklist.

### Why does the AI repeat itself?

Usually fixable with settings:

- Raise **Temperature** a little (0.8–1.1 works well for roleplay).
- Raise **Repetition Penalty** slightly (1.05–1.15).
- Check the character card — missing or weak **example dialogue** is the number-one cause of repetitive characters. A few good example exchanges work wonders.
- Some models are simply repetitive, especially at heavy compression. Try a different one — personality varies a lot between model families.

---

## Characters

### Where can I find characters?

- **The Stoop** — the community hub built right into the app (currently in nightly builds): browse, follow creators, and download with one tap.
- **Import a card file** — download a card (PNG or JSON) from any character site in your normal browser, then use the **Import** button and it lands straight in your library.
- **Anywhere character cards are shared** — Front Porch AI reads standard V2/V2.5 character card files (PNG or JSON), the same format the whole community uses.
- **Make your own** — the AI Character Creator builds a complete character from a one-line concept, or use the step-by-step manual creator.
- **The Discord** — people share cards and ideas in the [community Discord](https://discord.gg/e4tET6rpdv).

### Can I use my SillyTavern or Backyard AI characters?

Yes, directly:

- **SillyTavern cards** (PNG or JSON) import perfectly — drag them onto the app or use the Import button. Multi-select and whole-folder import are supported.
- **Backyard AI archives** (`.byaf` files) have a dedicated importer, so your characters aren't stranded in that format.

Everything you create or edit is saved as standard, portable character cards too — no lock-in in either direction.

### Why isn't my character acting right?

In rough order of likelihood:

1. **The card is thin.** A character with no example dialogue and a two-line description gives the AI almost nothing to work with. Add example exchanges and specifics.
2. **The model is too small** for a subtle personality. Try a larger or newer model.
3. **Sampler settings are off.** Extremely low temperature makes characters robotic; extremely high makes them incoherent. Start at 0.85–1.0.
4. **A global system prompt is fighting the card.** If you've customized the system prompt in Settings, it can override character instructions.
5. **The Realism Engine is off.** Without it, characters have no persistent emotional state between turns. Turning it on adds bond, trust, mood, and memory of how your story has been going — see the [Realism Engine guide](realism-engine.md).

---

## The Stoop

### What is The Stoop?

The Stoop is a community character hub built into the app (currently in nightly builds, coming to stable): browse featured and moderator-picked cards, follow creators you like, vote, and download characters — including entire group casts with their Realism state intact — straight into your library.

It's opt-in, needs a free account, and is strictly 18+. Adult content is hidden unless you explicitly turn it on. The rest of the app stays 100% local whether or not you ever open The Stoop.

### What data does The Stoop collect?

Only if you sign in and use it:

- **Your account info** — email, display name, your 18+ confirmation, and a securely hashed password.
- **What you upload** — the cards you choose to share, obviously.
- **An anti-abuse signal** — a salted, one-way *hash* of your IP address (never the raw IP), used only to enforce bans and stop ban-evasion, deleted after 90 days.
- **An anonymous stats ping** — coarse facts like OS, app version, and GPU tier (e.g. "NVIDIA · 8–12 GB") so I know what hardware to prioritize. It's on by default but there's an off switch right on the sign-up screen and in Account settings. It never includes chats, characters, or your IP.

Never collected: your conversations, your characters (unless you upload them), or anything from offline use. Full details: [Privacy Policy](https://github.com/linux4life1/front-porch-AI/blob/main/PRIVACY.md).

---

## Voice

### Why isn't the voice (TTS) working?

- **First use downloads voice files.** The default local engine (Kokoro) fetches its voice models (~300 MB) the first time you use it. Give it a minute and watch for the progress indicator.
- **Wrong engine selected** — check Settings → Voice. Kokoro is the local default; ElevenLabs and OpenAI need an API key and internet.
- **A character has a voice from a different engine.** If you switched engines, a character's assigned voice may no longer match — the voice picker warns you about incompatible ones. Re-assign or choose the default.

More fixes in [Troubleshooting → Voice](troubleshooting.md#tts-not-producing-sound).

### How do I get better-sounding voices?

- **Best free local:** Kokoro (the default) — over 50 voices, surprisingly natural, fully offline.
- **Best overall (paid):** ElevenLabs — extremely natural and expressive, needs an API key.
- **Lots of distinct voices:** Piper — lightweight and fast, handy for giving every group member their own voice.
- **Per-character voices:** assign a specific voice on each character's card; it overrides the global default, including in group chats.

### Why does voice call mode send my message too early?

Voice call mode listens for a pause: once you've spoken, about two seconds of silence tells it you're done, and it sends the transcription. It also samples the room's background noise for a moment when the call starts, to learn what "quiet" sounds like on your setup.

If it keeps cutting you off or triggering on background noise:

- Use a headset — laptop microphones pick up fans and keyboards easily.
- Lower your microphone gain in your OS settings.
- End and restart the call — it re-measures the background noise fresh each time.
- You can always press the **Send** button in the call screen to send manually instead of waiting for the pause detection.

---

## Realism Engine

### What is the Realism Engine?

The optional system that makes characters feel *alive* over time instead of resetting every message. With it on, a character:

- carries a **mood** that shifts naturally and lingers between turns
- builds (or loses) **bond** (−300 to +300) and **trust** (−100 to +100) with you, which changes how open they are
- experiences the **passage of time** — the story clock moves forward as you chat
- can develop **fixations**, pursue their own **objectives**, and **evolve new personality traits** over long stories
- can live with Sims-style **needs** — hunger, energy, social, fun, hygiene, comfort, and more

It's off by default and configurable per character. The [Realism Engine guide](realism-engine.md) covers all of it.

### Does the Realism Engine slow down my chats?

Honestly: yes, somewhat — it's not free. After each turn, the engine asks the AI a few short background questions ("how did that land emotionally?", "did time pass?"). On a local model those run one after another and typically add a few seconds per turn; on remote APIs they run in parallel and the cost is smaller.

Ways to reduce it:

- Turn on **One-Shot Eval** mode, which combines the background questions into a single call.
- Use a fast model — the evaluations are short, so speed matters more than size.
- Turn the Realism Engine off for characters or scenes where you don't need it.

### How do I reset a character's bond and trust?

Start a **new chat** — Realism state (bond, trust, mood, time, needs) belongs to the conversation, and a fresh chat starts from the character's saved starting values. There's currently no reset button inside an ongoing chat.

You can also edit a character's *starting* Realism values in the character editor — but those only apply to chats started after the change; existing conversations keep their history.

---

## Your Data & Devices

### How do backups work?

Automatically, and always on. The app snapshots your database every **30 minutes** and keeps two tiers:

- the **10 most recent** snapshots (fine-grained undo for the last few hours), plus
- **one snapshot per day for the last 7 days** (a rolling week of restore points)

Old ones are pruned automatically so it never grows unbounded. If the database is ever damaged, a restore screen appears on launch and recovery is one click. You can also make a manual backup any time from Settings.

For an extra off-machine copy, just copy your whole `FrontPorchAI` folder somewhere safe — that's everything.

### Where is my data stored?

Everything lives in one folder you control:

- **Windows:** `Documents\FrontPorchAI\`
- **macOS / Linux:** `~/Documents/FrontPorchAI/`

(Beta and nightly builds use `FrontPorchAI-Beta` instead, so they never touch stable data.)

Inside you'll find your database, character cards, and backups (in `KoboldManager/`), your downloaded AI models (`models/`), plus folders for chats, worlds, and the AI engine itself. Copy the whole folder and you've backed up everything.

### Can I chat from my phone or another computer?

Yes. The app has a built-in **web server**: turn it on in Settings, then open `http://<your-computer's-address>:8085` in any browser on the same network — phone, tablet, laptop. You get a full web interface for chatting.

Two things to know:

- Your desktop computer does all the actual work (it's running the AI), so it needs to stay on.
- It's designed for your home network. For access away from home, a personal VPN like Tailscale is the safe way to reach it.

### Can I sync between two computers?

Not really, and I'd steer you away from trying. The old Cloud Sync feature (Google Drive / WebDAV) is **deprecated** — it could occasionally resurrect deleted data across devices, which is why newer builds show a retirement notice. Automatic local backups replaced it as the safety net.

To move to another machine: copy your `FrontPorchAI` folder over, or export/import individual character cards. Both are reliable.

### How do updates work?

- **Windows / macOS:** the app checks for updates and shows a "What's New" dialog when one is available; download and install from there (or grab it from [GitHub Releases](https://github.com/linux4life1/front-porch-AI/releases)).
- **Linux (APT/RPM/AUR):** updates arrive through your normal system updates — `apt upgrade`, `dnf upgrade`, or `yay -Syu`.

### How do I report a bug?

- [GitHub Issues](https://github.com/linux4life1/front-porch-AI/issues) — best for anything reproducible.
- [Discord](https://discord.gg/e4tET6rpdv) — best for "is it just me?" questions and quick help.

If the app misbehaves, launching it from a terminal shows error messages that make bug reports ten times more useful. See [Troubleshooting](troubleshooting.md) first — your issue may already have a fix.
