# Privacy Policy

**Last updated:** June 30, 2026

## The short version

Front Porch AI is a free, open-source desktop app (AGPL-3.0). **The app itself is local-first: your characters, chats, lorebooks, settings, and models live on your device. Using the app offline collects nothing and sends us nothing.**

There is **one optional online feature — "The Stoop"** (a community hub for sharing AI character cards). The Stoop is the *only* part of Front Porch AI that uses an account or involves any data collection, and **only if you choose to sign in and use it.** Everything below about data collection applies to **The Stoop only**. If you never open The Stoop, none of it happens.

## What stays entirely on your device (always)

Stored locally, in a folder you choose, and never collected or transmitted to us:

- Character cards, chat logs, lorebooks, worlds, story projects
- App settings, RAG memory / embeddings, and model (GGUF) files

**Local AI models** (KoboldCpp) run entirely on your hardware — no chat data leaves your machine.

**Text-to-speech / speech-to-text** runs locally (Kokoro, Piper, Whisper). No audio is collected by us.

**Remote AI / TTS APIs** (OpenRouter, Nano-GPT, OpenAI, etc.) are opt-in: if you configure one, your prompts/audio go to *that provider* — not to us. Review the chosen provider's own privacy policy.

## The Stoop (optional community hub) — what we collect, and why

The Stoop is a strictly-18+ community where people share AI character cards. Using it requires an account. When — and only when — you use The Stoop, we collect:

**Account information**
- Your email, a display name, your confirmation that you are 18 or older, and a securely **hashed** password (your password is never stored in readable form).
- Your acceptance of the Acceptable Use Policy.

**Content you choose to share**
- Character / group cards and avatar images you upload — stored on our servers and S3-compatible object storage so others can browse and download them.
- Your votes, your download history, reports you file, and messages between you and moderators.

**An anti-abuse signal (a hashed IP — never the raw IP)**
- On sign-up and sign-in we record a **salted, one-way hash of your IP address** (we do **not** store the raw IP) alongside a random per-install identifier. This is used **only** to enforce bans and to detect ban-evasion and coordinated vote-brigading. These signals are automatically deleted after a limited retention window (currently 90 days).

**Anonymous app analytics — opt-out, on by default**
- So we can see what platforms, app versions, and hardware the community runs (and prioritize development accordingly), the app sends a once-per-launch, **anonymous** ping containing only coarse device facts: operating system + version, app version, language/locale, and a coarse GPU tier (e.g. "NVIDIA · 8–12 GB").
- It contains **no chats, no characters, and no IP address.**
- It is **opt-out**: on by default, but you can turn it off right on the sign-up screen, or any time later in **Account → "Share anonymous analytics."** When it's off, no ping is ever sent.

## NSFW content

Adult content is **hidden by default.** You only see it if you explicitly opt in via **Account → "Show NSFW content."**

## Your controls

- **Delete your account** at any time (**Account → "Delete my account"**). This permanently erases your account, your uploaded characters, your votes, and your messages.
- Toggle analytics off, toggle NSFW off, enable optional two-factor authentication, or change your display name — all from the account menu.
- Simply not using The Stoop keeps the entire app local and silent.

## What we do **not** do

- We do not sell your data.
- We do not use third-party advertising/tracking SDKs, behavioral profiling, or crash-reporting services.
- We do not store raw IP addresses, and the analytics ping never includes your IP, your chats, or your characters.

## Changes to this policy

The "Last updated" date reflects the current version. Material changes to how The Stoop handles data are also surfaced in-app through the Acceptable Use Policy, which you re-accept whenever it changes.

## Contact

Questions about this policy? Open an issue on our [GitHub repository](https://github.com/linux4life1/front-porch-AI).
