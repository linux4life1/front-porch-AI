# Characters

Characters are the heart of Front Porch AI. This guide covers everything about them — where to find ready-made ones, how to make your own, what's actually inside a character card, and how to keep a growing library organized.

---

## Table of Contents

1. [What Is a Character Card?](#what-is-a-character-card)
2. [Getting Characters Into the App](#getting-characters-into-the-app)
3. [Creating Your Own Character](#creating-your-own-character)
4. [What's Inside a Card](#whats-inside-a-card)
5. [Editing & Managing Your Library](#editing--managing-your-library)
6. [Expression Images](#expression-images)
7. [Group Cards — Sharing a Whole Cast](#group-cards--sharing-a-whole-cast)
8. [Compatibility With Other Apps](#compatibility-with-other-apps)
9. [When an Import Goes Wrong](#when-an-import-goes-wrong)

---

## What Is a Character Card?

A **character card** is a single file that holds everything about an AI character: their name, appearance, personality, the situation you meet them in, their opening message, and samples of how they talk. Share the file, and anyone can chat with the exact same character.

Cards come in two common shapes:

- **PNG image** — the most common. The picture *is* the character's avatar, and all the personality data is hidden inside the image file itself. This is the format most character-sharing sites use.
- **JSON file** — the same data as plain text, without an image.

Front Porch AI uses the **V2 card format** (and its newer V2.5 revision) — the same standard used by SillyTavern, Chub.ai, RisuAI, and most of the character-chat world. Cards travel freely between these apps: anything you make here works there, and vice versa.

> **Rescuing Backyard AI characters:** Front Porch AI also imports Backyard AI's `.byaf` archive format, so characters stranded there can move in. They're converted to standard V2 cards on the way.

---

## Getting Characters Into the App

Everything starts from the home screen — your character library.

![The character library — your home screen](screenshots/home_new.png)

### Import files you already have

1. Click **Import** in the top toolbar.
2. Pick one or more `.png` or `.json` card files (you can select several at once).
3. After each import, a tag dialog pops up so you can label the character before it lands in your library.

Have a whole folder of cards? Use the **folder import** option instead — point it at a directory and the app scans it top to bottom, including subfolders, finding every PNG card and `.byaf` archive inside. It shows you a breakdown of what it found and lets you confirm before anything is imported.

### Browse character sites without leaving the app

The toolbar has built-in browsers for two popular character sites:

- **Chub.ai** — browse and search their huge catalog; when you hit a card's download button, it drops straight into your library. (A heads-up dialog appears first, since Chub hosts unfiltered community content.)
- **aicharactercards.com** — same idea, different catalog.

On Linux, the built-in browser needs a system component called WebKit — the official AppImage bundles it. If it's missing, the app offers to open the site in your normal browser instead, and you can import the downloaded file manually. See [Troubleshooting](troubleshooting.md) if the browser won't open.

### The Stoop *(currently in nightly builds)*

The Stoop is the community hub built right into Front Porch AI — browse featured cards, follow creators you like, and download characters (including entire group casts) with one tap. It's opt-in, needs a free account, and is strictly 18+ with adult content hidden by default. The rest of the app stays fully offline whether or not you use it.

---

## Creating Your Own Character

There are two paths: let the AI build the character from your idea, or write every field yourself.

### The AI Character Creator

![The AI character creator](screenshots/ez_char_creator.png)

Open the Character Creator and pick how much control you want:

- **Quick Create** — the fastest path. Give it a name and a short description ("a sarcastic Victorian inventor who loves tea"), and the AI writes the whole card: description, personality, scenario, first message, and example dialogue.
- **Automated Creator** — pick personality traits, genres, and tones from tappable bubbles, and the AI fills in the gaps around your choices.
- **Guided Creator** — write out your vision in your own words, with guided prompts helping you cover appearance, personality, and backstory. Best when you already know exactly who this character is.

A few things worth knowing, whichever mode you pick:

- **Alternate greetings** — the creator can write up to 5 extra opening messages alongside the first one, each with its own tone (playful, dramatic, and so on). When you start a chat, you can flip between them and begin the story from whichever opening you like.
- **World lore** — paste one or more wiki or lore page URLs (a Fandom wiki, for example), or attach local files (`.txt`, `.md`, `.pdf`, `.json`, `.csv`), and the creator weaves that knowledge into the character and their lorebook.
- **Lorebook generation** — the creator can write world-knowledge entries to go with the character (more on lorebooks below).
- **Avatar generation** — if you've connected an image generator (see the [User Guide](user-guide.md)), the review step can generate a matching portrait.
- If the AI's response gets cut off mid-generation, the creator notices and automatically fills in whatever's missing.

When generation finishes you review every field, edit anything you like, and save. The result is a normal, fully editable card — nothing about it is locked to the AI that wrote it.

> **Tip:** The creator leans on your currently active AI model. A smarter model writes noticeably better cards, so some people temporarily switch to a remote API just for character creation, then switch back to their local model to chat.

### The Manual Creator

Prefer to write it all yourself? **Create Character** walks you through seven steps, in order: **Identity** (name, avatar, tags), **Personality** (description, traits, scenario), **Dialogue** (first message, alternate greetings, example conversations), **Lorebook**, **Realism** (the character's starting emotional state — see below), **Expressions** (optional emotion portraits), and **Review**.

The Realism step sets where the character *starts*: their initial bond and trust toward you, their mood, the time of day, and which Realism Engine features are on. These become the character's defaults — every new chat begins from them. (Full details in the [Realism Engine guide](realism-engine.md).)

---

## What's Inside a Card

A quick tour of the fields, whether you're writing your own or editing an import:

| Field | What it does | Tips |
|---|---|---|
| **Name** | The character's display name | |
| **Description** | Appearance, clothing, mannerisms, voice | Be vivid and specific — this is the model's mental picture |
| **Personality** | Core traits, speech style, likes and dislikes | Works together with Description |
| **Scenario** | The situation your story starts in | Where are you two, and why? |
| **First Message** | The character's opening line | Long and atmospheric is fine |
| **Example Dialogue** | Sample exchanges showing how they talk | **The single biggest lever** for a consistent voice — a handful of good exchanges works wonders |
| **Alternate Greetings** | Extra possible openings | Flip between them when starting a chat |
| **System Prompt** | Hidden instructions for the AI, specific to this character | Optional; overrides the global one |
| **Post-History Instructions** | A reminder slipped in after the recent chat history | Good for "always stay in character" style nudges |
| **Tags** | Labels for search and filtering | |
| **Lorebook** | World-knowledge notes that activate when their keywords come up in chat | Great for places, factions, and backstory the character should "know" |
| **TTS Voice** | A voice just for this character | Overrides your default voice; shines in group chats |

Two placeholders appear throughout cards: **`{{char}}`** stands for the character's name and **`{{user}}`** for yours. Write "{{char}} smiles at {{user}}" and every player who imports the card sees their own name in the story.

---

## Editing & Managing Your Library

- **Edit** — open any character and change every field: personality, dialogue, lorebook, colors, avatar, Realism defaults. Edits to Realism defaults apply to *new* chats; conversations already in progress keep their living state.
- **Duplicate** — one click makes a full copy (named "(duplicate)") including the lorebook and Realism settings. Perfect for experiments: tweak the copy, keep the original safe.
- **Export** — saves the character back out as a standard V2 PNG card you can share anywhere.
- **Delete** — removes the character from your library.
- **Folders** — group characters however you like; create and rename folders right from the home screen.
- **Tags & search** — filter the grid by tag or search by name instantly.
- **Per-character looks** — each character can have their own chat bubble colors and font, and they survive export/import.

---

## Expression Images

Give a character a set of portraits — one per emotion — and their avatar changes live as their mood shifts during the conversation: smiling when they're happy, glowering when they're angry.

- Add expressions in the creator's **Expressions** step or from the character editor.
- **SillyTavern expression packs work as-is**, so packs you find in the community drop right in.
- The app figures out the current emotion using either a small local classifier (fast, fully offline, downloads with one click in Settings) or the Realism Engine's deeper read of the scene.
- If an emotion has no image, the app quietly falls back to neutral.

The [User Guide](user-guide.md) covers display modes (sidebar vs. fullscreen) and setup in more detail.

---

## Group Cards — Sharing a Whole Cast

A Front Porch original: export an entire **group chat as one PNG file** — every member with their avatars and lorebooks, the group's scenario and opening message, the speaking order, *and* the cast's current Realism state (who trusts whom, everyone's mood and needs). Import it on another machine and the whole living scene rebuilds itself, ready to play.

![Building a group](screenshots/group_chat_creator.png)

A few notes:

- To other apps, a group card looks like an ordinary image — the group data is a Front Porch format, so only Front Porch AI can open it. Single-character cards remain universal.
- On nightly builds, group cards can be shared and downloaded on **The Stoop**, casts and all.
- Developers building tools that work with group cards can find the full format specification in the [integration guide on GitHub](https://github.com/linux4life1/front-porch-AI/blob/main/docs/CharacterCardForge_GroupChat_Integration_Guide.md).

---

## Compatibility With Other Apps

Cards are meant to travel, and Front Porch AI takes round-tripping seriously:

- **Reading**: V2 and V2.5 cards from SillyTavern, Chub.ai, RisuAI, Agnai, and other standard exporters open correctly, whether PNG or JSON.
- **Writing**: exported cards are standard V2.5 PNGs that open anywhere the standard is supported.
- **Nothing gets lost**: Front Porch's own additions (Realism defaults, bubble colors, voice assignment) live in the card's standard *extensions* area — the part of the format explicitly set aside for app-specific data. Other apps simply ignore it. And when a card arrives carrying another app's extension data, it's preserved untouched and written back on export.

In short: import, edit, export, share — the card keeps working everywhere, and nobody's data gets stomped on.

---

## When an Import Goes Wrong

- **"Import failed" or the character comes in blank** — the PNG probably doesn't contain card data (it may be a plain image, or the data was stripped by an image editor or a site that re-compressed it). Re-download the original card file.
- **Avatar shows as a gray square** — re-open the character and re-assign the image, or re-import the card.
- **The Chub browser won't open on Linux** — install WebKit or use the AppImage build; the app will offer your regular browser as a fallback either way.
- **A `.byaf` import fails** — make sure the file is a genuine Backyard AI export and not renamed or partially downloaded.
- **A JSON card imports as gibberish** — the file needs to be saved with UTF-8 text encoding; re-save it from a text editor.

More fixes live in the [Troubleshooting guide](troubleshooting.md). If a card stumps you, bring it to the [Discord](https://discord.gg/e4tET6rpdv) — someone's usually seen it before.

---

*Next up: bring your characters to life with the [Realism Engine](realism-engine.md), or explore chats, voice, and more in the [User Guide](user-guide.md).*
