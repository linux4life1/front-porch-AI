# User Guide

The complete reference for everything that is not a dedicated page.

**Read these first, they are the real manuals:**

- [Chatting](chatting.md) — screen, tools, slash, groups, Director
- [Porch Life](porch-life.md) — every living-character switch, the story clock, skip time, Clock In, Pockets
- [Image Studio](image-studio.md) — what program to run, ports, Create vs Edit
- [Web & Phone](web-phone.md) — how to open it, what the phone **cannot** do
- [Characters](characters.md) · [Realism Engine](realism-engine.md) · [Getting Started](getting-started.md)

This page is Settings, voice, Stoop, Porch Stories, generation, backend, backups.

It describes **Front Porch AI 1.3.1 ("Clock In")**.

> **Tip:** Many actions have hotkeys — see [Keyboard Shortcuts](keyboard-shortcuts.md).

---

## Table of Contents

**Everyday chatting**
- [The Chat Screen](#the-chat-screen)
- [Message Tools](#message-tools)
- [Director Mode](#director-mode)

**Your characters & their world**
- [Characters](#characters)
- [User Personas](#user-personas)
- [Lorebooks & Worlds](#lorebooks--worlds)
- [Group Chats](#group-chats)
- [The Realism Engine](#the-realism-engine)
- [Porch Life](#porch-life)
- [Passage of Time](#passage-of-time)
- [Pockets & Wardrobe](#pockets--wardrobe)
- [Clock In](#clock-in)
- [Long-Term Memory](#long-term-memory)

**Voice, images & stories**
- [Voice: Talking and Listening](#voice-talking-and-listening)
- [Image Generation](#image-generation)
  - [Turn it on](#turn-it-on)
  - [Backends](#backends)
  - [Image Studio](#image-studio)
  - [Create vs Edit](#create-vs-edit)
  - [`/image` in chat](#image-in-chat)
  - [Expression packs](#expression-packs)
  - [When Edit or QC won't run](#when-edit-or-qc-wont-run)
- [Porch Stories (Novel Generator)](#porch-stories-novel-generator)

**Beyond the desktop**
- [The Stoop (Community Hub)](#the-stoop-community-hub)
- [Web & Phone Access](#web--phone-access)

**Settings & upkeep**
- [Settings (all six tabs)](#settings-all-six-tabs)
- [Generation Settings](#generation-settings)
- [Slash commands](#slash-commands)
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

- **Top bar** — the character's avatar, name, and a short description. The back arrow returns you to your library, and the **Toggle Sidebar** button on the right opens or closes the right-hand sidebar. That's all the top bar holds.
- **The conversation** — your messages and the character's replies, on top of a scene background you can change (see [Appearance](#appearance)). If Character Expressions are enabled, the character's portrait changes as their mood changes. **◀ ▶ on that portrait** flips **looks** from the Avatar Gallery for this chat (a different face, not a different emotion).
- **Right sidebar** — **Main Settings** sits at the top of the sidebar (not the top bar), opening a menu with Edit Character, Avatar Gallery, UI Settings, Chat Settings, Model Settings and TTS Settings. Because it lives in the sidebar, you need the sidebar open to reach it. Below it are collapsible cards you can open and close independently: **📝 Author's Note**, **🎭 Character State** (mood, bond/trust bars, needs, scene clock, weather, ambitions), **📖 Journal & Memory**, **🎯 Objectives**, and **🎲 Story Tools** (Chaos Mode, Dynamic Responses, Places, lorebooks). A one-on-one chat shows all five; a group chat shows four, because group objectives open from the focused cast member's card instead of getting a card of their own. If the participant you have focused is a lightweight **scene guest** (see [Group Chats](#group-chats)), Character State and Objectives drop away as well — a guest carries no relationship or needs tracking, and a small "Lite NPC" note in the sidebar says so.
- **Input bar** — the strip along the bottom: your persona avatar and a row of buttons, the box you type in, and more buttons after it. Drag the grip to make the box taller. **Enter** sends; **Shift + Enter** makes a new line.

**Sending a message:** type and press Enter. The reply streams in live, word by word — no waiting for the whole thing. A red **Stop** button appears while the AI is writing; click it any time to cut the reply short.

**Attaching a photo:** the **Attach a photo** button next to the message box adds an image to your message. If your model can see images, it looks at the photo directly. If it can't, the app offers a small offline **Photo Understanding** helper that describes the picture for it, so the character can still react. (Once installed, you can remove it again from Settings → Voice & Media.)

**Slash commands:** type `/` in the message box — a list appears. Full table: [Slash commands](#slash-commands). Type `@` to mention someone present (host, guest, or group member). `Esc` dismisses either list.

**Chat Management** (the folder icon in the input bar at the bottom of the chat — not in the top bar) holds **New Chat**, **Chat History** (every past conversation with this character), **Import Chat** / **Export Chat** (a native **`.fpchat`** package *or* SillyTavern JSON/JSONL), **Context Budget** (see [Long-Term Memory](#long-term-memory)), and **Turn Into a Story…**, which hands the conversation to [Porch Stories](#porch-stories-novel-generator). Right-click a character or group on Home → **Chat History** opens the same list (edit name, delete a chat); it does not delete the character.

**Thinking models:** some AI models (like Qwen or DeepSeek) "think out loud" before answering. Front Porch tucks that private reasoning into a collapsible "Thought" chip above the reply — tap it if you're curious, ignore it if you're not.

---

## Message Tools

Messages come with their own controls, and they're always on screen — there's nothing to hover over to reveal them. **Edit**, **Fork from here** and delete sit on every message. **Regenerate**, **Continue** and the ◀ ▶ swipe arrows appear on the last reply. (The one exception below is Impersonate, which is the magic-wand button in the input bar rather than anything on a message — it's grouped here because it belongs with the rest.)

### Regenerate & Swipes

Didn't like the reply? **Regenerate** asks for a completely new one — and the old version isn't thrown away. Each alternative is saved as a **swipe**. When a message has more than one version, ◀ ▶ arrows appear so you can flip between them instantly and keep whichever you like best.

### Continue

Tells the AI "keep going" from where the reply left off. Handy when a response got cut short or you want a longer scene.

### Impersonate

The magic-wand button in the input bar at the bottom — not on a message bubble — asks the AI to write *your* next message for you. You can type a few words in the box first to steer it. Great for when you're stuck.

### Edit

The pencil (**Edit message**) on any bubble — yours or the character's — lets you rewrite it. The story continues from your edited version, a clean way to fix small details without restarting. **Esc** cancels (asking first if you changed anything), **Ctrl/⌘ + Enter** saves.

### Delete

Deleting a message removes that whole turn — and it also **rolls back any Realism Engine changes** that message caused. If a reply tanked your character's trust, deleting it undoes the damage too.

### Suggest Actions

The lightbulb button asks the AI for four short, clickable ideas for what you could do next ("Ask about their day", "Suggest moving somewhere private"…). Click one and it's sent as your message. Perfect for keeping momentum when you're not sure what to say.

### Branching

**Fork from here** on any bubble splits the chat at that point so you can explore a "what if" storyline, leaving the original untouched.

---

## Director Mode

Director Mode turns you from a participant into the director of the scene. Characters respond to each other on their own — you sit back and steer. It's a **group chat** feature.

- Toggle it at the top of a group chat's sidebar (you can also have a group start in Director Mode by default). The input bar changes to **"Direct the scene..."** — anything you type becomes a stage direction rather than dialogue ("Suddenly the power goes out", "Time skip to the next morning").
- A **Response Delay** slider controls the pacing between turns, so a scene unfolds at reading speed instead of all at once.
- A play/pause button in the chat toolbar starts and stops hands-free auto-chat; outside of that, the **next character** button triggers one turn at a time.

Pair Director Mode with auto-playing voice and Character Expressions and you get something close to ambient theater — characters talking, portraits shifting with their moods, while you drop in a note whenever you want the story to turn.

---

## Characters

Your library lives on the home screen. For everything about creating, importing, and editing characters — including the AI Quick Create wizard and card format details — see the dedicated [Characters guide](characters.md). Here's the short version.

![The character library](screenshots/home_new.png)

- **Create** — build a character by hand with the step-by-step creator, or type a one-line concept and let the AI write the whole card (personality, first message, example dialogue, even a matching avatar).
- **Import** — the download button in the toolbar takes **Import Cards** (character card PNGs and JSON), **Import Folder** (a whole directory at once), and **Import Backyard AI (.byaf)** archives. For browsing and downloading new characters without leaving the app, use [The Stoop](#the-stoop-community-hub).
- **Edit** — open any card to change its personality, greetings, example dialogue, voice, lorebooks, and Realism Engine starting values.
- **Avatar Gallery** — from a chat's **Main Settings → Avatar Gallery**, give a character several looks plus their expression images, star a canonical avatar, and pick which look this particular chat uses.

![The character editor](screenshots/editor.png)

**Staying organized:**

- **Folders** — enter Organize mode from the toolbar ("Organize into folders"), select characters, and move them into folders; you can also drag a card straight onto a folder. Folders nest, and breadcrumbs help you navigate. **Since 1.2, group chats can live in folders too**. Delete folder: **contents bubble up** vs **folder + characters** (type DELETE). Group right-click **Extract Characters** copies each member out as standalone cards. Search: this folder / +subs / all. Sort Name/Recent/Import/Messages. Grid zoom is on the toolbar.
- **Tags** — label characters freely and filter by tag in search.
- **Search** — the search bar matches names and descriptions, and you can scope it to the current folder, that folder plus subfolders, or your whole library.
- **Sort** — Name (A→Z), Recent Activity, Import Date, or Messages Sent.
- **Zoom** — a grid slider makes cards bigger or smaller to suit your collection.

---

## User Personas

A persona is *you* — who the character thinks they're talking to. Open **User Persona** in the left sidebar.

Each persona has:

- **Avatar** — the picture used for your messages.
- **Title** — an optional label just so you can tell personas apart in the list.
- **Name** — what gets sent to the AI as your name.
- **Persona text** — the details the character knows about you. This is included in every conversation, so keep it tight.

You can keep as many personas as you like and switch which one is **active**; the active persona is the one used in chats. Personas import and export as JSON, and personas brought over from SillyTavern or Backyard AI fill themselves in automatically.

---

## Lorebooks & Worlds

Lorebooks are how you give a character knowledge that never gets forgotten — backstory, places, factions, rules of magic, anything the AI should know but that would bloat every message if you pasted it in.

**How they work:** each lorebook entry has trigger keywords and a chunk of text. When a keyword shows up in recent conversation, that entry's text is quietly slipped into what the AI reads before replying. Mention "the war", and the AI suddenly knows your world's history of it.

**Making entries:** open a chat's sidebar → **Story Tools** and expand the lorebook section, or manage them from the character editor. Each entry gets:

- **Keywords** — the words that wake it up (optionally regex, optionally case-sensitive)
- **Content** — what the AI learns when triggered
- **Always Active** — some entries can be marked constant so they're *always* in play

And, if you want them, the finer controls SillyTavern users will recognize:

- **Secondary keywords** with AND/NOT logic, so an entry only fires in the right combination
- **Position and Order** — where the text lands in the prompt and which entries win when space is tight, plus an "ignore token budget" escape hatch for entries that must always make it
- **Scan depth** — how far back in the conversation the app looks for keywords
- **Sticky, Cooldown and Delay** — stay active for N messages, refuse to re-fire for N messages, or stay silent until the chat is long enough
- **Probability and groups** — random firing, and groups where only one entry of the set is picked
- **Chain reactions** — let one entry's text trigger another

Entries that are currently active are highlighted, and the sidebar shows what *would* trigger next, so you always know what the AI can "see."

**Worlds** are the **Places** your stories happen in — open **Worlds** in the left sidebar. A place bundles lore (so every character who lives there knows its geography, politics and history), optional cover art, and a **climate**. Attach a place to a chat from the sidebar's **Story Tools → Places** panel, or attach it on the character **Worlds** tab so new chats inherit it.

**Import Lorebook** is its own page (not Import Cards): pick a file → send it to a **new Place**, to **characters**, to a **group**, or to the **current chat**. Pulling one card's lore into another is **Import Character Lore** on the editor.

Lorebook and world files from SillyTavern import cleanly.

**Rule of thumb:** character-specific facts go in the character's own lorebook; shared setting lore goes in a Place.

### Weather and climate

A place gives its chats real, consistent weather. There are built-in climates (temperate, rainforest, desert, continental, tropical, mediterranean, highland), each with its own seasons, conditions and temperatures. The current condition and temperature show as a chip in the chat sidebar, and the character actually notices them — nobody sunbathes in a blizzard. Temperatures follow the °C/°F switch on **Porch Life** (**Temperatures in °F**).

**Authoring your own climate (1.2):** the climate editor lets you build a world that isn't Earth. **2 to 8 seasons** (not stuck at four) — each has a month/day start; overlap blocks save. You can start from a built-in biome. Day–night swing = how hard temperature drops after sundown.

- **Seasons and temperatures** — set the temperature band and swing for each season, from cryogenic all the way up to inferno.
- **Renamed conditions** — call "rain" a *Dust Squall* and give it your own emoji. Each rename carries a **stance** (pleasant, ordinary, harsh, dangerous, deadly) so the app knows how characters should treat it — nobody goes dancing in acid rain. Flavour text + a Preview / sample week show how a character will feel it.
- **How often each condition happens** — weight the mix per season.

**Atmosphere and gravity (1.2):** a place can also declare that its air is thin, unbreathable or outright hostile, and that gravity is low, high or micro. Characters behave accordingly — they struggle for breath, move differently, and treat going outside as the serious thing it is. Leave both at the Earth-normal default and nothing is added to the story at all.

### Sharing places

Places export to a portable **`.fpworld`** file (lore, climate, traits and cover art in one package) and import the same way from the Worlds page. You can also **share a place on [The Stoop](#the-stoop-community-hub)**, and downloading one drops it straight into your Places — no file handling at all.

> Places themselves aren't new — they've been in the app since 1.0, and so have the built-in climates. What arrived in 1.2 is the authored-climate editor above (including atmosphere and gravity) and the portable `.fpworld` package here. A `.fpworld` file needs **Front Porch AI 1.2 or newer**; an older version can't open one.

---

## Group Chats

Put two or more characters in one room and they'll talk to you *and each other* — each with their own personality, voice, expressions, and Realism Engine state.

![A group chat](screenshots/group_chat_new.png)

**Creating a group:** click **Create Group Chat** in the left sidebar. It's a step-by-step wizard: build a roster of at least two characters, give the group a name, an opening scenario and first message (the AI can draft both for you), and choose how turns work.

![The group creator](screenshots/group_chat_creator.png)

**Turn order** comes in two flavors:

- **Round robin** — characters speak in a fixed rotation.
- **Random** — anyone might speak next.

Outside of full auto-play, a **next character** button in the toolbar shows who's up and lets you trigger their turn — or hand the reins over entirely with Director Mode and auto-advance.

Each member keeps their own lorebooks, relationship scores, needs, expression images, and voice. It's a real ensemble, not one AI wearing different name tags.

**Group Settings** (from the group, not global Settings) has tabs: General, Realism, Needs, Memory & RAG, Lore/Worlds, and **Prompt Engineering** (per-group system / post-history text). Per-member Realism and Needs live on the member cards.

Groups sit on the home screen next to your characters, and (since 1.2) can be filed into folders the same way.

### A cast that changes mid-story

A 1:1 chat and a group are the same chat with a different headcount — so you can change the cast **in place**, with your history and every character's memory and relationships intact. Type `/` in the message box to see the list; the ones that move people around are:

- **`/join <name>`** — bring someone into the scene. In a 1:1 they arrive as a lightweight **scene guest** (they're in the story, but they don't carry their own relationship and needs tracking). In a group, everyone is always a full member.
- **`/join --full <name>`** — bring someone in as a *full* member. In a solo chat that converts it into a group on the spot, no wizard and no screen change. The newcomer makes an entrance in their own voice and the story just continues.
- **`/promote`** — turn the scene you're already in into a real group, upgrading every guest present to a full member.
- **`/exit <name>`** — write someone out. They get a goodbye, and a one-tap **Undo** appears in case you regret it.
- **`/speak <name>`** — make a specific character take a turn right now.
- **`/turnorder`** — set exactly who speaks when, including your own slot (`/turnorder Mara, {{user}}, Kai`). On its own, it shows the current order.
- **`/create <name>: <concept>`** — invent a brand-new guest on the spot and walk them into the scene.
- **`/scan`** — look over the scene for someone the story keeps mentioning and offer to add them.

When a group shrinks back to one character, it collapses into a clean 1:1 with the original character — no leftover copies — and they remember everything that happened in the group.

**Other commands worth knowing:** `/image` pictures the current scene (or whatever you describe), `/expression` sets a character's portrait by hand, and `/afk` keeps the scene ticking over while you step away.

---

## The Realism Engine

The feature that makes characters feel alive instead of stateless. When it's on, the app quietly evaluates each exchange and updates what the character feels:

- **Bond** — closeness, running from −300 to +300. Earned slowly; lost fast.
- **Trust** — how safe you seem, on a smaller −100 to +100 scale.
- **Emotion** — a current mood with momentum. Small moments cause small drift; it takes something real to swing a mood hard.
- **Arousal** — a −100 to +100 scale with its own pacing and recovery, for stories with 18+ themes.
- **Time** — the story clock moves **every single turn**, by however long the exchange actually took, and rolls over into days, weekdays and seasons. You can nudge it with the ‹ › chevrons in the sidebar or skip ahead by writing something like *(OOC: we drive for several hours)*.
- **Weather** — each chat gets consistent, believable weather (with real temperatures) from the Place it's set in, and the character reacts to it. See [Lorebooks & Worlds](#lorebooks--worlds).
- **Needs** — a Sims-style layer: hunger, bladder, energy, social, fun, hygiene, comfort — each drifting realistically and coloring the character's behavior.
- **Fixations, objectives & ambitions** — characters can develop obsessions, pursue goals of their own, and carry longer-term ambitions that inch forward over many sessions.
- **Growth Rings** — instead of rewriting a personality, long stories add *rings*: new stances, habits, skills and scars that layer on top of who the character already was. You can review them in the sidebar.
- **Promises** — commitments either of you make are tracked. Kept ones warm trust; broken ones hurt; open ones hang over the next reply.
- **Dreams** — when a story night passes, the character dreams: a short, hazy scene made from what they remember, how they feel, and the weather outside.
- **Chaos Mode** — optional random "Chance Time" events that shake up the scene when things get too comfortable.

Everything shows up in the chat sidebar under **Character State** — relationship bars, current mood, needs, the scene clock, the weather chip, ambitions — and small chips under each reply show what changed and why.

You can switch the engine (or individual parts of it) on and off globally in **Settings → Porch Life** and per character in the editor. For a single conversation: in a one-on-one chat the switch sits on the **Character State** card in the sidebar; in a group chat that card has no such switch — use **Group Settings → Realism**, which has a "Realism Engine for this group" toggle. (The tune icon on the Character State card opens the finer simulation settings in both.)

**The full deep-dive — every system, number, and tuning knob — lives in the [Realism Engine guide](realism-engine.md).**

---

## Porch Life

**Settings → Porch Life** is the home for every living-character switch. It is not Settings → General (that's still theme, system prompt, 18+ themes).

The important bit since 1.3: **Realism Engine is no longer the master key.** Journal, the story clock, Chaos / Chance Time, Pockets, and Objectives each have their own switch. Turn on what you want. New chats pick up those defaults; an open chat can still overrule them in the sidebar.

Other rows on that tab, in plain English:

- **Needs** — Sims-style hunger/energy/etc. Needs the engine to turn a need into a mood.
- **Story Weather** — rides on the clock.
- **Dreams / Promises / Growth Rings / Ambitions / Standing Mood** — each says what it needs on the row itself.
- **Notice new characters** — every few messages, offer to bring in someone the story named. `/scan` still works if you turn this off.
- **Planner** — they keep a short plan (needs Time + Objectives + Journal). You can add or delete lines.
- **Welcome-back recap** / **Character notices your absence** — after a long gap, a banner and (optional) one in-character mention. Coarse (“a few days”), never guesses what you were doing.
- **Afterglow** (18+ themes on) — desire settles after a scene instead of snapping to zero. Older docs called this NSFW Cooldown; same thing, new name.
- **Acts on desires** — card intimate preferences are *said and acted on*, not only scored.

**18+ themes** itself is Settings → **General**, not Porch Life. Off hides After Dark and intimate card fields; it does not erase what you already set.

**AI Enhance** is not on this tab. Right-click a character on Home → grow the card from real chats (can pull those chats along).

---

## Passage of Time

Dummy version is on the [FAQ](faq.md#how-does-time-work). This is the same facts, for the User Guide.

The story clock is **chat-scoped** (one clock for a group). It is **not** allowed to follow the real calendar — Monday in the story stays Monday if you reopen the chat on Saturday.

**On:** Settings → Porch Life → Passage of Time. Per chat: Character State → **tune** → Automatic Passage of Time.

**With Realism off:** the nested switch **Keep the clock running without the engine** (default **off**). Without it the clock holds still on purpose — that call used to be free while the engine was on, and treating the old default as consent would bill everyone an extra eval. Cost: one short model call after each reply.

**After each reply** (not Continue): scene-time eval → `minutes_elapsed` → clamp **180**. Eval fail → **+5 minutes**. **12** stalled turns → snap to next period (dawn 6:00, morning 9:00, late morning 11:30, afternoon 2:30, evening 6:30, night 10:30). Regen/swipe restore `story_clock_before` then eval again.

**Skip:** OOC / skip phrases in [FAQ → skip](faq.md#how-do-i-skip-time); ‹ › period nudge; tap date → Story Calendar. Night-skip language lands morning.

Weather, dreams, Clock In, and Planner all read this clock.

---

## Pockets & Wardrobe

They can wear things, carry things, and set things aside. Hand them an item, take it back, or (in a group, if you turned **Hand things between characters** on) they pass it to someone else.

- Own switch on **Porch Life**. Does **not** need the Realism Engine.
- Authors can send them into a chat already dressed and carrying things (the card / greeting seed).
- The Journal grows a **Belongings** tab of where things went.
- Extra model call when inventory changes — that's the cost.

If they "forget" an object you handed them, check the switch is on for that chat and look at Belongings before assuming the model is broken.

---

## Clock In

A character can have a job: occupation, which weekdays, hours on the clock.

- Set it on the character (the work / occupation row).
- Skip a turn while they're scheduled to be working and a banner says they're at work. A night skip lets them rest.
- The story clock is told the time **before** they write; after the reply the clock decides how much passed. **Continue does not tick the clock.**
- **With you** is scored after they speak — not assumed. They can be at work and still talking to you, or not.

If Discord is asking "why won't they leave work?" — that's this feature, not a bug. Change their hours, skip to after shift, or turn the occupation off.

---

## Long-Term Memory

Front Porch gives characters real long-term memory, entirely on your machine — no cloud. It comes in two layers, both under **📖 Journal & Memory** in the chat sidebar.

### The Journal

Every so often the character writes in a diary. Not a bland summary — **memory cards**, each one a thing that happened *and how it felt*, stamped with the emotion and how strongly they felt it.

- **Warm memories stay close.** Cards carry heat that cools a little each time the diary is updated. Recent, intense ones are always in mind; quiet ones fade into the back of the drawer. Something big — a promise broken, trust repaired, a goal finally reached — makes them stop and write immediately.
- **Bringing a cold memory back** needs the Memory (RAG) layer below: matching a faded card to what you just said is done with the same small embedding model, so it only happens once RAG is switched on *and* that model has been downloaded. On a fresh install neither is true yet, so faded cards simply stay faded — everything else about the diary works regardless, warm and pinned cards included.
- **"Where we are"** — a short running recap of the situation, at the top of the section.
- **Our Story** — open the full diary and switch to the **Our Story** tab for the relationship's real beats: first bond tier reached, trust repaired, promises kept and broken, objectives completed. Every entry quotes the line it came from, and tapping it jumps you back to that exact message.
- **You can write in it too.** **Plant a memory** adds a card in your own words; you can edit, pin (pinned cards never fade) or delete anything the character wrote.
- **Review updates first** — an optional switch behind the sliders icon on the "Where we are" card. Proposed diary changes wait for your approval instead of saving themselves. (There's also a control for how often the diary updates, and a pause button.)

**Memories never leak between chats.** A character's diary belongs to the conversation it was written in, and it's deleted with that chat. Two separate chats with the same character know nothing about each other — deliberately.

The Journal has its own on/off switch, next to the "Where we are" heading in the sidebar. Turn it off and both the diary and the recap stop — the character then only remembers what still fits in the context window, plus whatever the Memory layer below finds.

### Memory (RAG)

The second layer is a searchable index of the conversation itself. As you chat, the app converts stretches of conversation into compact "memory fingerprints" using a small local AI model (you'll be offered a quick one-time download when you first enable it). When the character replies, the app finds the most relevant old passages from earlier in *this* conversation — the parts that have already scrolled out of the AI's working memory — and slips them back into what the AI reads.

**This layer respects the same wall the diary does.** A character's own memories are searched only within the chat they were made in; anything belonging to a different conversation with them is deliberately skipped, so an old storyline can't bleed into a new one. The only two things that reach across conversations are ones you set up yourself: the opt-in **Sources** list and the **Data Bank**, both described just below.

The **Memory (RAG)** panel lets you set how many memories to pull per turn, open the **Data Bank** (**Add Entry** or **Import File** — txt/PDF, chunked ~500 words), and pick **Sources** — an opt-in list if you *want* a character to also draw on memories belonging to *other* characters. Nothing crosses over unless you tick it.

Memory (RAG) has a master switch that is off until you turn it on and download the embedding model. Once it is on, group chats use it too and are enabled by default; the sidebar Memory (RAG) panel itself only appears in one-on-one chats, and groups are configured under **Group Settings → Memory & RAG**: turn it on or off for the group, set how many memories to pull, set how much of the context budget they may take, and boost or suppress each individual member with **Per-Character Memory Importance**.

### Seeing what the AI was actually told

**Chat Management → Context Budget** breaks down the *entire* package sent with the last message — system prompt, lorebook entries, persona, scenario, examples, chat history and post-history instructions — with a token count for each part and how close you are to your context limit. It's the single best tool for understanding why a character said what it said, and for spotting what's eating your context.

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

Both local voice engines run *inside* the app itself — no helper program to install, no Python, nothing to start or keep running for voice. (Your AI model is a different matter: the default local setup runs KoboldCpp as its own program alongside the app — see [The AI Backend](#the-ai-backend).)

![Voice settings](screenshots/tts_settings.png)

**The settings that matter:**

- **Auto-Play** — new replies are spoken automatically. The heart of hands-free sessions.
- **Only narrate "quotes"** — reads just the spoken dialogue, skipping narration.
- **Ignore \*text inside asterisks\*** — skips action text entirely.
- **Kokoro workers** — for long narration, extra resident voices (2–4 is the sweet spot) keep audio flowing without stutters.

Every character can have their own voice, and in group chats each member speaks with theirs. A small speaker icon on any message replays it.

**Bringing your own Piper voice:** in the Piper voice browser, **Add custom voice** takes a raw Piper `.onnx` model (with its matching `.onnx.json` sitting next to it — the standard pair every Piper voice ships as) and installs it for use like any built-in voice. That means the whole Piper voice ecosystem, including voices you trained yourself, works here. This is a desktop-only feature by design; there's no importer in the browser/phone UI.

### Speech-to-Text (you talk)

Voice input runs on Whisper, inside the app — nothing you say leaves your computer, and again, there's nothing extra to install.

- **Push-to-talk** — hold the microphone button, speak, release. Your words appear in the input box ready to edit or send.
- **Voice Call Mode** — the green call button starts a hands-free conversation: the app listens, sends when you pause, the character answers out loud, and the loop continues until you hang up. Optional **Voice Call Model** (a different, usually faster model than chat), **buffer** (pre-generate N sentences), and a **call-only system prompt**. Auto-send transcription is a switch — FAQ covers it cutting you off early.

Bigger Whisper models are more accurate (especially with names and accents) but slower; smaller ones are snappy. Choose in Settings — models download automatically the first time.

---

## Image Generation

Front Porch does **not** run Stable Diffusion inside the chat app. You run an image server (or a cloud API); Front Porch talks to it. The pictures are made in the **Image Studio** (desktop) or with `/image` in chat.

The phone / web UI does **not** have the full Image Studio. It **can** generate from **Models** and from `/image` in chat.

### Turn it on

1. Settings → **Voice & Media** → **Image Generation** — flip it on. Until that switch is on, the ✨ **Image Studio** button in the chat toolbar is hidden.
2. Point it at a backend (below). URL and model pickers live *inside* the Studio, not on that Settings row.

### Backends

You pick a chip **inside Image Studio**. Front Porch never starts these programs.

| Chip | Start this yourself | Default address | Gotcha |
|---|---|---|---|
| **Draw Things** | Draw Things app (Mac). Enable **gRPC**. | `127.0.0.1` port **7859** | Not shown on Windows/Linux unless you already saved it. |
| **ComfyUI** | ComfyUI | `http://127.0.0.1:8188` | Edit = recipe or upload a workflow. |
| **AUTOMATIC1111** | A1111 or **Forge** | `http://127.0.0.1:7860` | Must launch with **`--api`**. |
| **Remote** | Nothing extra locally | Same URL/key as Settings → **Backend** | Not a second key. Empty key = Generate does nothing useful. Cloud bill. |

Wait for the green **connected** card (model count). Dummy-proof steps: [FAQ → Pictures](faq.md#how-do-pictures-actually-work).

### Image Studio

Open a chat → ✨ in the input bar.

**Subject** (what the picture is *of*):

- **Freeform** — you write the prompt. Leave it blank and tap **Write it for me** / Craft to picture the current scene.
- **Character** — close-up from the card's appearance + current expression. Personality text is *not* stuffed into the prompt. In a group, pick one member (or attempt a group shot — diffusion is bad at several specific faces at once, and the UI says so).
- **Your persona** — portrait from your persona appearance.

**Prompt style:** Natural language (FLUX / SD3) or Danbooru tags (SD 1.5 / anime). Match what your checkpoint was trained on.

**Write it for me** asks your *text* LLM to draft the prompt; you can edit it before Generate.

**LoRAs** — style add-ons from the image server. Compatible ones show in the picker; confirmed mismatches hide behind **Show N incompatible** and warn if you force one anyway. Weight slider is right there.

**Reference image (img2img)** — local backends only (hidden on Remote): attach a picture + denoise strength. Not the same as Edit.

**History** of generations sits in the Studio. From a result you can **Variations**, **Edit prompt & regenerate**, **Send to chat**, **Save to gallery**, or save to disk.

### Create vs Edit

Two tabs at the top of the Studio:

- **Create** — new picture from a prompt. Model slot, LoRA, size, style, negative prompt, Advanced samplers.
- **Edit** — change an existing picture. Needs an **edit-capable** model (Qwen-Image-Edit, Flux Kontext, and friends) on a backend that supports edits. If your current combo can't, the app tells you why — it does not silently txt2img.

Edit on Draw Things: use **Use recommended** on the recipe strip before you invent CFG. Comfy: pick a built-in recipe or **Upload your own** workflow.

### /image in chat

Type `/image` for the current scene, or `/image me | char | raw <prompt> | <description>`.

If **Review AI prompts before generating** is on (Studio generation settings), `/image` **pauses** so you can edit the crafted prompt first.

### Expression packs

Studio (and the character editor's portrait panel) can build a set of mood faces from **one base portrait**, so the pack stays the same person.

- **Starter** — 8 emotions (neutral, joy, sadness, anger, fear, surprise, love, embarrassment). Fast.
- **Full** — 28 emotions, everything chat expressions can show.
- You can keep faces you already like and only generate the missing ones.
- **QC** — the app looks at each face (needs a **vision-capable** text model: local GGUF + mmproj in Model Settings → Vision, or a vision remote). Re-roll one that failed. Import the keepers into the Avatar Gallery.

No base portrait → it stops and says so. No edit model → expression pack from a portrait can't run.

### When Edit or QC won't run

- **No vision model** — local: load a vision GGUF and its mmproj (Model Settings → Vision). Remote: pick a model that can see images.
- **Couldn't check vision** — the model server didn't answer (often still loading). Wait, retry.
- **Edit disabled** — wrong family for inpainting/edit. Switch the image model, not the chat model.

![Image generation](screenshots/local_image_gen.png)

![Image generation settings](screenshots/local_image_gen_settings.png)

---

## Porch Stories (Novel Generator)

Porch Stories turns ideas — or your existing chats — into full illustrated novels. Switch the home screen into **Porch Stories** mode to see your story projects.

![A finished Porch Story](screenshots/Porch_stories_book.png)

**How a story gets made:** backend must be loaded. Setup wizard: **Engine → Concept → Style → Format → Cast → Review**. If you import chat history, a **Distiller** runs first so the novel tracks what actually happened. Then **Architect** (bible) → **Act Structurer** (acts/scenes) → per-scene beats then prose. You can rewrite one scene from the structure tree. Chat → **Turn Into a Story…** names the project (desktop).

**Project settings include:** point of view, genre and mood, prose length, pacing, dialogue density, maturity rating — plus which of your characters appear and whether to import chat history so the novel builds on what actually happened between you.

**Match it to your hardware:** a quality tier setting adjusts how ambitious the writing instructions are — one for frontier cloud models, one for large local models (70B+), one for small/mid local models — so the pipeline works whether you're on a laptop or an API.

Finished stories open in a page-flip book reader with optional read-along narration, and can be exported (including EPUB and audiobook generation via your TTS voices).

---

## The Stoop (Community Hub)

The Stoop is a community hub built into the app — browse, share, and download characters, whole group casts and places. Open it from **The Stoop** in the left sidebar, or in a browser at [hub.frontporchai.app](https://hub.frontporchai.app) (guests can browse and download there).

- **Browse & discover** — **Mod's Picks** on the front page, new cards from creators you follow, and browse-all with sorting by **Newest**, **Top** or **Downloads**. Filter by **Singles**, **Groups** or **Worlds**.
- **Search** — one box that understands a name, an `@creator` or a `#tag`.
- **One-tap download** — cards land in your library ready to chat.
- **Whole group casts travel** — sharing a group brings its members, avatars, lorebooks, *and* their pre-set Realism and Needs state. The scene arrives alive, not flattened.
- **Places travel too (1.2)** — share a place and its lore, climate, traits and cover art ride along; downloading one drops it straight into your Places.
- **Follow & vote** — follow creators you like, upvote what's good, report what breaks the rules.
- **Uploads are reviewed** — sharing submits the card for moderation rather than publishing it instantly.

### Your profile

Every account gets a public porch page: profile picture, when you joined, follower count, lifetime stats, a short bio, up to four links, and your published cards laid out as an art grid. Edit it from **Edit profile** on your Stoop home.

**Confirming your email** unlocks sharing, a profile picture, comments, and reports. Browsing and downloading work without it. If you haven't confirmed yet, a banner on The Stoop offers to send the link again.

### Messages and notifications

The bell opens your inbox. **Notifications** collects approvals and review notes for cards you've shared; **Moderator chat** is a direct line to the moderation team if you have a question about a review or the rules.

### Privacy

The Stoop is **opt-in**, strictly **18+**, with adult content hidden until you turn it on, and optional two-factor authentication. On the **web hub** you can browse and download as a guest. Sharing, votes, comments, and reports need an account. It's the only part of the app that involves an account or any data collection at all — everything else stays on your machine. If you never touch it, nothing about your setup changes.

---

## Web & Phone Access

Your desktop runs the AI — but you can chat from any browser, including your phone on the couch.

**Turning it on:** Settings → **Advanced** → **Web Server** → **Enable Web Server**. A guided setup walks you through the rest and shows a **QR code** — scan it with your phone and you're in.

**On your own network (LAN):** works immediately — any device on the same Wi-Fi can connect.

**Away from home:** the guided setup recommends **Tailscale**, a free private network between your own devices. The app checks whether Tailscale is installed and signed in, walks you through fixing whatever's missing, and can set up HTTPS so you get a clean, secure address that works from anywhere — no router fiddling, nothing exposed to the public internet.

**Security:** web access has its own login, which you create in the browser the first time you connect. On **this computer** (localhost) that first-run page is enough; from a phone, another machine, or a tunnel you also enter the **one-time setup code** shown under Settings → Web Server on the desktop. Sessions are per-device, two-factor authentication is optional (turning 2FA **on or off** asks for your password so a stolen browser session alone can't lock you out), and the desktop side is your recovery key: Settings → Advanced → Web Server can **sign out all devices** or **reset the web login** entirely if you ever get locked out. (Resetting only clears the web username, password and 2FA — your characters, chats and settings aren't touched — and shows a new setup code.)

The web app is **not** a clone of every desktop button. It covers chats (including group), library and editors, AI create, models, settings (including Porch Life), Worlds, Porch Stories, and browsing The Stoop.

**Not on phone / web (do these on the desktop app):**

- Image Studio (full Create/Edit/LoRA/expression-pack QC). Phone **Models** can still generate a picture and insert it into chat; `/image` works in web chat too
- Voice Call Mode (push-to-talk mic still works over HTTPS)
- Suggest Actions
- Attach a photo to a message / Photo Understanding
- Sharing / uploading on The Stoop (browse, download, follow, vote, comments work)
- Backups & Restore
- Database Scan & Clean / changing the data folder
- Turn Into a Story from chat
- Director auto-play + response delay (the Director toggle exists; pacing is desktop)
- Six-tab Settings layout, Voice Call model, GPU launch, custom Piper importer

**Remote** is its own page on the phone (Tailscale login, HTTPS, optional **ngrok**, QR) — not only the desktop Advanced wizard.

Mic / push-to-talk on a phone needs **HTTPS** (Tailscale HTTPS or similar). Plain `http://192.168…` will not get microphone permission.

Account on the web: change password, enroll 2FA (QR + recovery codes), signed-in devices, sign out. Dangerous actions re-ask the web password.

---

## Settings (all six tabs)

Open **Settings** from the left sidebar. Tabs, left to right:

| Tab | What lives here |
|---|---|
| **General** | Dark/light, chat fonts, bubble colors, **Font Size Scale** (whole app, separate from chat text size), **18+ themes**, system prompt + presets, About & License. Pointer to Porch Life. |
| **Porch Life** | Every living-character switch. See [Porch Life](porch-life.md). |
| **Generation** | Samplers, token limits, smooth output buffer, stop sequences, banned phrases (Kobold only), Output Sanitizer, thinking/reasoning effort. |
| **Voice & Media** | TTS engines (Kokoro / Piper / ElevenLabs / OpenAI). Piper **Add custom voice** = raw `.onnx` + `.onnx.json` next to it (**desktop**). Voice catalog + preview is here, not on the character Voice row. STT/Whisper, Voice Call (separate call model, buffer, call prompt, auto-send), expression display (**sidebar / background / both**), **Image Generation** on/off, **Photo Understanding** uninstall (separate from Image Generation). |
| **Backend** | Local KoboldCpp / oMLX / OpenAI-compatible (OpenRouter, Nano-GPT, LM Studio, custom). Model picker, presets, process logs. |
| **Advanced** | **Data directory** (change where everything lives), **Web Server** (QR, Tailscale, setup code, 2FA reset), GPU/launch extras, **Database Maintenance → Scan & Clean** (orphan avatars, leftover embeddings, dead sessions — **not** the same as Reclaim Disk Space), **Reclaim Disk Space** (old sidecar leftovers). |

Spell-check language for red underlines is under Generation / Chat Settings on desktop (and Generation on web).

---

## Generation Settings

These control *how* the AI writes. Set them globally in **Settings → Generation**, or just for the conversation you're in via **Main Settings → Chat Settings** (which has a **Reset to global defaults** button whenever you want out). Defaults are sensible — tweak one thing at a time.

- **Temperature** — creativity dial. Lower (0.6–0.8) is focused and consistent; higher (1.0+) is wilder. Around 0.8 suits most roleplay.
- **Min-P / Top-P / Top-K** — filters that decide which words the AI is even allowed to consider. Min-P around 0.05–0.1 is a modern, reliable choice.
- **Repeat penalty** — discourages the AI from repeating itself. Small values (1.05–1.15) help; big ones make speech stilted.
- **Max output tokens** — a cap on reply length, in tokens (word-pieces — roughly ¾ of a word each).
- **Min output tokens** — a floor so tiny replies get pushed longer.
- **Context size** — how much of the prompt the model can see. A `.kcpps` preset can lock this.
- **Smooth Output Buffer** — Display Output: target tokens/sec and buffer seconds so text drips at reading speed, not GPU speed.
- **Advanced samplers** — dynamic temperature (Dynatemp Range), XTC threshold/probability, DRY strength, each with a tooltip. Safe to experiment; easy to reset.
- **Reasoning / Thinking** — for models that support it: ask for reasoning and pick an effort level. Private thought still lands in the Thought chip.
- **Stop sequences** — cut a reply off as soon as a marker appears. Works on every backend.
- **Banned phrases** — ban turns of phrase you're sick of. This one belongs to the local KoboldCpp backend only: on a remote or OpenAI-compatible backend the editor isn't shown at all, in Settings → Generation or in Chat Settings, so don't go hunting for it there. (The Output Sanitizer below tidies finished replies instead, and isn't restricted that way.)

**Three steering tools worth knowing:**

- **System Prompt** — permanent hidden instructions ("always write in third person"). There's a global one in Settings → General (with saveable presets and one-click starting points for API, KoboldCpp and group chats), and each character and group can carry its own.
- **Author's Note** — temporary scene direction the character experiences as part of *now* ("it's raining hard; they're exhausted"). Lives at the top of the chat sidebar with a strength dial **1–10** (Subtle / Moderate / Strong). Edit it mid-scene any time.
- **Output Sanitizer** — rules that clean up a reply *after* the model writes it: strip a tic, fix a formatting habit, delete a phrase. Enable it in Settings → Generation, or just for one chat in Chat Settings. Optional **Sanitise Existing History** rewrites saved chats when you open them — confirm the dialog; it is permanent. Rule syntax: [Output Sanitizer](output-sanitizer-syntax.md).

> **Note:** if a KoboldCpp launch preset (`.kcpps` file) is active, it controls context size and related values — the app locks those fields and shows a tooltip explaining why. **Generate `.kcpps`** from current launch settings lives in Settings → Backend.

---

## Slash commands

Type `/` in the box. Aliases (`/turn`, `/detect`, `/expression-clear`) exist; the helper list shows the names below.

| Command | What it does |
|---|---|
| `/create <name>: <concept>` | Make a new guest NPC and bring them in |
| `/join [--full] [name]` | Bring a library character in. `--full` = full member (turns a 1:1 into a group) |
| `/promote` | Everyone present becomes a full member (scene → group) |
| `/speak [name]` | Force a turn now |
| `/exit [name]` | Guest leaves (narrated); in a group, remove that member |
| `/turnorder [random \| <name>, …]` | Round-robin, random, or an explicit order |
| `/scan` | Look for a recurring name in the scene and offer to add them |
| `/expression [emotion]` | Set the portrait by hand (omit to clear) |
| `/afk [off] [--messages N] [--time 5m]` | Keep the scene ticking while you step away |
| `/image [me \| char \| raw <prompt> \| <description>]` | Picture the scene, you, the character, or a raw prompt |

Dynamic Responses (sidebar **Story Tools**, **1:1 only**) is the same AFK idea without typing: gear sets interval 30–300s, max 1–10 scenes, story-time pace (hours / half day / full day). Typing cancels. Groups use `/afk` only.

---

## Appearance

Make it yours, in Settings and the UI options:

![Settings](screenshots/new_settings.png)

- **Theme** — dark or light.
- **Chat themes** — ten complete looks you can drop on any single chat from **Main Settings → UI Settings**: Fantasy, Galactic, Neon Grid, Sakura, Noir, Enchanted Forest, Ocean Depths, Cyberpunk, Roman Empire and Steampunk. Each one sets its own colors, font and bubble border, and you can customize any of it afterwards without losing the rest.
- **Chat backgrounds** — a built-in set of scenes (cozy library, cyberpunk bedroom, cherry blossoms, beach, coffee shop, rooftop sunset, and more) plus your **own uploaded images**, nameable per chat.
- **Chat fonts** — pick from a set of quality fonts (Georgia, Roboto, Open Sans, Lato, Merriweather, Playfair Display, Source Code Pro and others), applied live.
- **Bubble colors and opacity** — per-character message colors, plus separate colors for quoted dialogue and \*actions\*.
- **Chat text size** — bigger or smaller message text.
- **Expression display** — show the character's live portrait in the **sidebar**, as the chat **background**, or **both**.
- **Grid zoom** — resize library cards to taste.

The app remembers your window size and position between sessions.

---

## The AI Backend

The "backend" is whatever actually runs the AI model. Front Porch supports three, switchable any time from Settings → Backend.

### Local (KoboldCpp) — private and free

KoboldCpp is a real program that runs alongside Front Porch — but the app downloads it, launches it, and shuts it down for you, so there's no command line, ever. Your hardware is detected automatically (NVIDIA, Apple Silicon, AMD, Intel, or plain CPU) and the right acceleration is chosen. **Start Backend** / **Stop Backend** in Settings → Backend is the on/off switch when you want one.

![The Model Hub](screenshots/model_hub.png)

- **Model Hub** — search Hugging Face for GGUF models (the standard file format for local AI), see sizes and memory estimates, download in one click.
- **Models you already have** — the app scans its models folder, subfolders included, so dropping a `.gguf` file in there is enough to make it show up. **Import from Computer** picks one from anywhere else, but be aware it *copies* the file into the models folder rather than pointing at it where it sits — a 20 GB model you import takes 20 GB twice until you delete the original.
- **Auto-configuration** — the app suggests how much of the model to put on your graphics card and how long its memory (context) should be, based on your hardware.
- **Advanced launch options** — a collapsible panel: **Automatic** acceleration, or pick Vulkan / ROCm (AMD) / CuBLAS (NVIDIA) / Metal. **Flash Attention** (~20–40% on RTX/Apple Silicon, auto-off for ROCm) applies on the *next* restart. **KV Cache Quantization** saves VRAM but **turns off Context Shifting**. GPU Layers, context chips (512–128K), mlock (Linux often needs a higher ulimit), GPU ID, Prefill batch. Sane defaults if you never touch them. A `.kcpps` preset locks the ones it owns.
- **Launch presets** — `.kcpps` preset files are supported; when one is active it takes charge of launch settings.
- A **log viewer** is there when you want to see what the engine is doing under the hood.

### OpenAI-compatible API — big models, or your own server

Point it at a URL and (if needed) an API key. That covers remote services like **OpenRouter**, **Nano-GPT** and **OpenAI**, and equally a server you run yourself such as **LM Studio** or **vLLM**. Useful when you want frontier-class models, or on hardware that can't run local ones. Many people mix: local for daily chat, remote for character creation or story generation.

### oMLX — Apple Silicon

Local inference through oMLX on Apple Silicon Macs. It expects oMLX running on port 8000.

> On **Intel Macs**, local inference isn't available. The app does *not* quietly switch you to a remote backend — it greys out the Local option and shows a banner telling you that only Remote API mode is available. Choosing **Remote API** in Settings → Backend, and giving it a URL and (if the service needs one) a key, is a step you take yourself. Until you do, the app is still pointed at the local backend it can't run, so that's the first thing to do on an Intel Mac.

For hardware advice and model recommendations, see [Getting Started](getting-started.md#powering-the-ai-local-or-remote).

---

## Backups & Data Safety

Your chats are irreplaceable, so the app protects them automatically — no setup, no account, no cloud.

**How it works:** every **30 minutes**, a snapshot of your database is saved locally. Retention is two-tier:

- the **10 newest snapshots** are always kept (fine-grained coverage of the last several hours), *plus*
- **one snapshot per day for the last 7 days** (so you can roll back to "yesterday" or "last Tuesday").

Old snapshots beyond those rules are pruned automatically, so backups never eat your disk.

### What a backup does and doesn't hold

A snapshot is **the database file, and only the database file**. That's your chats, messages, groups, personas, places, journals and objectives — the whole written record.

It is **not** a copy of your files on disk. Character card PNGs, avatar and expression images, chat backgrounds and downloaded models all live outside the database and are not in the snapshot. The practical consequence worth knowing:

> **A backup will not bring back a character you deleted.** Deleting a character removes its card image from disk, and no snapshot restores that. Restoring an older snapshot can bring the character's *record* back while its portrait stays gone. If you want a character to be genuinely recoverable, export the card — that's a real, portable copy of them. Backups protect the conversation history, not the library files.

**Managing them:** open **Backups & Restore** from the left sidebar. You can **Create Backup Now** before anything risky, and **Restore** any snapshot with one click. Since 1.2 a restore takes effect immediately — the app reloads your library on the spot instead of asking you to close and reopen it. If that live reload doesn't work for some reason, the app says so plainly and asks you to close and reopen Front Porch AI; the restore itself has already been written to disk at that point, so reopening is all it takes.

Restoring replaces your current database with the snapshot, so anything you did after that snapshot was taken is gone. The app asks you to confirm first.

> **On nightlies, snapshots keep running but can't be restored from inside the app.** The **Backups & Restore** page opens but its contents are replaced by a notice, so there is no way to browse or roll back a snapshot there. The automatic snapshots themselves keep running, against the nightly's own separate database.

**Moving to a new computer:** export your characters as card files and import them on the other machine — or copy your whole data folder, which does include the card images a backup leaves out. Backup snapshots can also be restored on a fresh install.

> **What happened to Cloud Sync?** Older versions offered syncing through Google Drive or WebDAV. It could occasionally resurrect deleted data across devices, so I retired it — it's gone. Automatic local backups are the replacement, and for moving characters between machines or sharing them with other people, card export/import and The Stoop do the job better.

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
