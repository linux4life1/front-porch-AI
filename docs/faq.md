# Frequently Asked Questions

Short answers. Where to click. What has to be running first.

If this page doesn’t cover it, try [Troubleshooting](troubleshooting.md). Still stuck? The [Discord](https://discord.gg/e4tET6rpdv) is friendly.

---

## Table of Contents

### Start here
- [Is it free?](#is-it-free)
- [Does it spy on me?](#does-it-spy-on-me)
- [What computer do I need?](#what-computer-do-i-need)
- [Do I need the internet?](#do-i-need-the-internet)
- [Stable vs Nightly?](#stable-vs-nightly)

### Chat
- [The AI won't talk](#the-ai-wont-talk)
- [How do I pick a model?](#how-do-i-pick-a-model)
- [Can I use ChatGPT / Claude / Gemini?](#can-i-use-chatgpt--claude--gemini)
- [It's slow](#its-slow)
- [It repeats itself](#it-repeats-itself)
- [The character is acting wrong](#the-character-is-acting-wrong)
- [Where do I get characters?](#where-do-i-get-characters)
- [SillyTavern / Backyard cards?](#sillytavern--backyard-cards)

### Pictures (Image Studio)
- [I don't see a picture button](#i-dont-see-a-picture-button)
- [How do pictures actually work?](#how-do-pictures-actually-work)
- [Draw Things (Mac)](#draw-things-mac)
- [ComfyUI](#comfyui)
- [Automatic1111 / Forge](#automatic1111--forge)
- [Cloud pictures (Remote API)](#cloud-pictures-remote-api)
- [Create vs Edit](#create-vs-edit)
- [It says not connected](#it-says-not-connected)
- [Edit / expression check is grey](#edit--expression-check-is-grey)

### The Stoop
- [What is The Stoop?](#what-is-the-stoop)
- [Do I need an account?](#do-i-need-an-account)
- [Why was my upload blocked?](#why-was-my-upload-blocked)
- [Worlds / Places](#worlds--places)
- [Comments, reports, gold/blue checks](#comments-reports-goldblue-checks)
- [Forgot password](#forgot-password)
- [What data does The Stoop collect?](#what-data-does-the-stoop-collect)

### Living characters
- [Where did the switches go?](#where-did-the-switches-go)
- [How does time work?](#how-does-time-work)
- [Why isn't the clock moving?](#why-isnt-the-clock-moving)
- [How do I skip time?](#how-do-i-skip-time)
- [Why does it say they're at work?](#why-does-it-say-theyre-at-work)
- [What are Pockets?](#what-are-pockets)
- [What is the Realism Engine?](#what-is-the-realism-engine)
- [Does Realism make chat slow?](#does-realism-make-chat-slow)
- [Reset bond / trust](#reset-bond--trust)

### Voice
- [No sound](#no-sound)
- [Better voices](#better-voices)
- [Voice call cuts me off](#voice-call-cuts-me-off)

### Other buttons people ask about
- [AI Enhance](#ai-enhance)
- [Arrows on the portrait](#arrows-on-the-portrait)
- [AFK / they keep talking while I'm away](#afk--they-keep-talking-while-im-away)
- [Where do I set their job?](#where-do-i-set-their-job)
- [Custom weather / seasons](#custom-weather--seasons)
- [Porch Stories — how do I start?](#porch-stories--how-do-i-start)
- [Import a lorebook](#import-a-lorebook)
- [Reprocess Needs](#reprocess-needs)
- [Scan & Clean vs Reclaim](#scan--clean-vs-reclaim)

### Phone, backups, updates
- [Chat from my phone](#chat-from-my-phone)
- [What's missing on the phone?](#whats-missing-on-the-phone)
- [Backups](#backups)
- [Where is my data?](#where-is-my-data)
- [Two computers](#two-computers)
- [Updates](#updates)
- [Report a bug](#report-a-bug)

---

## Start here

### Is it free?

Yes. No subscription. No account for chatting.

Optional paid stuff if *you* turn it on: OpenRouter (cloud AI, pay per use), ElevenLabs (fancy voices). The app itself is free.

### Does it spy on me?

No ads. No trackers. Chats stay on your computer.

The only internet bits, and only if you turn them on:

1. Cloud AI (OpenRouter etc.) — your prompts go there.
2. Cloud voices — the text being spoken goes there.
3. [The Stoop](#what-is-the-stoop) — that's the only Front Porch account.

[Privacy Policy](https://github.com/linux4life1/front-porch-AI/blob/main/PRIVACY.md).

### What computer do I need?

- **Windows** 10 or 11
- **Mac** — macOS 12 Monterey or newer. Apple Silicon (M1+) can run local models. **Intel Macs cannot.** On Intel, open Settings → Backend and pick **OpenAI-Compatible API** yourself. The app will not do that for you.
- **Linux** — APT, RPM, AUR, AppImage, `.deb` / `.rpm`

8 GB RAM minimum, 16 GB nicer. A GPU helps. No GPU is fine with a small model or a remote API.

Step-by-step install: [Installation](install.md). First-run walkthrough: [Getting Started](getting-started.md).

### Do I need the internet?

To download the app, the AI engine, and a model — yes.

After that, chatting, memory, and local voices work offline.

**Two extra programs you might run yourself:**

1. **KoboldCpp** — talks to local chat models. The app **downloads and starts this for you** (Settings → Backend).
2. **A picture program** — Draw Things, ComfyUI, or Automatic1111/Forge. Front Porch **does not** install or start that. You do. Then you point Image Studio at it.

You need the internet for: cloud AI, cloud voices, The Stoop, downloading new models.

### Stable vs Nightly?

- **Stable** — the one you should install. Current is **v1.3.1, "Clock In"**.
- **Nightly** — new stuff, rougher. Uses a **different folder** (`FrontPorchAI-Beta`) so it cannot eat your real library. On nightlies, Backups & Restore shows a notice (auto-snapshots still run; you just can't click restore there).

---

## Chat

### The AI won't talk

Do this in order:

1. Settings → **Backend**. If it says local isn't running, hit **Start Backend**.
2. You need a **model**. Sidebar → **Manage Models** → download a GGUF. Dropping a `.gguf` in the models folder also works.
3. **Intel Mac?** Local will never work. Settings → Backend → **OpenAI-Compatible API** + a URL/key.
4. Still nothing? [Troubleshooting](troubleshooting.md#the-ai-engine-wont-start).

### How do I pick a model?

Sidebar → **Manage Models**. The app estimates if it fits *before* you download.

| Your computer | Start here |
|---|---|
| 6–8 GB GPU | 7–9B at **Q4** |
| 12–16 GB GPU | 12–14B at Q4 |
| 24 GB+ GPU | bigger quantized models |
| Apple Silicon 16 GB+ | 7–13B |
| No GPU | 3–7B, or a remote API |

**7B / 13B** = size (bigger = smarter, hungrier). **Q4** = compression (Q4 is the sweet spot). Start small. Modern 8B models are good at roleplay.

### Can I use ChatGPT / Claude / Gemini?

Yes, through **OpenRouter** (one key, lots of models) or any OpenAI-compatible URL. Settings → **Backend**. That is *your* key and *their* bill.

### It's slow

Usually the model is too big and spilled into regular RAM.

- Smaller model, or Q4 instead of Q8
- Settings → Advanced → lower **GPU Layers**
- Check it actually sees your GPU: [GPU not detected](troubleshooting.md#gpu-not-detected)
- Giant context (16k+) is slow even on a good card

### It repeats itself

Settings → **Generation**: Temperature ~0.8–1.1, Repeat Penalty ~1.05–1.15, DRY Strength ~0.8.

Also: thin character cards (no example dialogue) repeat. Add examples. Some models just suck at this — try another.

### The character is acting wrong

1. Card is thin — add examples and a real personality.
2. Model too small.
3. Temperature way too low or way too high. Try 0.85–1.0.
4. Settings → **General** → system prompt fighting the card. Clear it or use a preset.
5. Realism Engine off — no leftover mood between turns. Settings → **Porch Life**.

### Where do I get characters?

1. Sidebar → **The Stoop** (or [hub.frontporchai.app](https://hub.frontporchai.app)) → download.
2. Home → **Import Cards** (PNG or JSON from any site).
3. **AI Create** on the home screen (one-line idea → a card).
4. Discord.

### SillyTavern / Backyard cards?

Yes. **Import Cards** for PNG/JSON. **Import Backyard AI** for `.byaf`. Lorebooks have their own import wizard.

---

## Pictures (Image Studio)

**Front Porch does not draw the picture.** It sends a prompt to **another program** (or a cloud image API) that you already have running. Your *chat* model is not the picture-maker.

### I don't see a picture button

1. Settings → **Voice & Media** → **Image Generation** → **on**. Until this is on, the ✨ button is **hidden**.
2. Open a **chat**. ✨ is in the bar at the bottom.
3. Full Image Studio is **desktop**. Phone: **Models** can still generate one picture, or type `/image` in chat.

### How do pictures actually work?

**Two programs.**

| Program | Job |
|---|---|
| Front Porch | Chat, ✨ Studio, send the prompt |
| Draw Things / ComfyUI / A1111 / Forge / a cloud image API | Actually paint the pixels |

Recipe:

1. Turn **Image Generation** on (above).
2. **Start the picture program** and load an image model in *that* program. Leave it running.
3. Open a chat → ✨.
4. Pick the matching backend chip (Draw Things, ComfyUI, Automatic1111, or Remote).
5. Wait until the card says **connected** (it lists how many models it found). If it doesn't, [It says not connected](#it-says-not-connected).
6. Pick **Create**, pick a subject (Freeform / Character / You), hit **Generate**.

URL and model lists live **inside the Studio**, not on the Voice & Media switch.

### Draw Things (Mac)

Mac only. Windows/Linux will not show this chip unless you already saved it.

1. Open Draw Things.
2. Turn on its **gRPC server**.
3. Default: host `127.0.0.1`, port **7859**.
4. Load an image model in Draw Things.
5. In Studio, tap **Draw Things**. Wait for connected.

**Edit** tab: use **Use recommended** on the recipe strip. Weird CFG on Qwen-Image-Edit often returns a **blank** image.

### ComfyUI

1. Start ComfyUI. Default address: `http://127.0.0.1:8188`.
2. Load a workflow / model there.
3. Studio → **ComfyUI**. Wait for connected.

**Edit:** pick a built-in recipe, or **Upload your own** workflow.

### Automatic1111 / Forge

1. Start the WebUI **with `--api`**. Without `--api`, Front Porch cannot talk to it.
2. Default address: `http://127.0.0.1:7860`.
3. Studio → **AUTOMATIC1111** (Forge uses this same chip).
4. Wait for connected.

### Cloud pictures (Remote API)

This is **not free**, and it is **not a separate key**.

It uses the **same** URL + API key as Settings → **Backend** (OpenRouter etc.). If that key is empty, Generate will look fine and then do nothing useful.

Studio → **Remote**. Pick an *image* model from the list (not your chat GGUF).

### Create vs Edit

- **Create** — brand-new picture from a prompt.
- **Edit** — change a picture you already have. Needs an **edit** image model (Qwen-Image-Edit, Flux Kontext, …). A normal “make a picture” checkpoint will not do Edit. The app tells you why; it will not silently fake it.

`/image` in chat = “picture this scene.” `/image me`, `/image char`, `/image raw …` exist too. If **Review AI prompts** is on, `/image` pauses so you can edit the prompt first.

### It says not connected

Read the grey hint on the card:

- Draw Things — is gRPC on? Port 7859?
- ComfyUI — is it running on 8188?
- A1111 — did you start it with **`--api`**?
- Remote — is Settings → Backend filled in?

Then hit **Retry**. The picture program must stay open.

### Edit / expression check is grey

**Edit:** wrong *image* model. Switch the image model, not the chat model.

**Expression pack QC** (the app looking at faces): your *chat* model must be able to **see** pictures (vision GGUF + mmproj in Model Settings → Vision, or a vision API). “Couldn't check vision” usually means the server is still loading — wait, retry.

Starter pack = 8 faces. Full = 28. You need a **base portrait** first.

Full walkthrough: [Image Studio](image-studio.md).

---

## The Stoop

### What is The Stoop?

A character shop built into the app (sidebar → **The Stoop**) and the web ([hub.frontporchai.app](https://hub.frontporchai.app)).

Download a single, a whole group, or a Place. Uploads wait for a moderator. Strictly 18+. Suggestive cards stay hidden until you tap 🔞.

The rest of Front Porch never needs this.

### Do I need an account?

**No** to look and download on the **web hub**.

**Yes** to follow, vote, comment, report, or share.

**Confirmed email** (click the link they send) to: share, profile picture, comment, report. Banner → send again. Check spam. Don't mash the button.

Throwaway emails are rejected. If the rules page (AUP) updates, you'll have to tick it again.

Share from the **desktop** wizard, or drop a PNG/JSON on the hub. Phone **cannot** upload.

### Why was my upload blocked?

1. Email not confirmed.
2. Incomplete card — first message + scenario + description *or* personality + **a picture**. Groups: every member needs a name, identity, **and** avatar. Places: climate + **cover**.
3. Intimate prefs filled in → the listing is 18+. A *member* with prefs 18+'s the **whole group**.
4. Still **Pending** — that is not a reject. Read the note if it says Not approved / Taken down.

Also: the card has to be a real character (not a blank), readable, no porn cover on a SFW listing, credit **Original creator** if it isn't yours.

Stoop **groups** only open in Front Porch. Solo V2 cards work in SillyTavern; the Realism extras do not.

### Worlds / Places

Yes, share them. Download lands in Worlds. File export is `.fpworld` (needs app **1.2+**). Updating a Place = new listing. Characters/groups can update in place. Hub cap ~**8 MB**.

### Comments, reports, gold/blue checks

Comments are **off** until the creator turns them on. Confirmed email to post. No links. You can report a comment.

**Report** on a card: sign in, confirm email, pick a category, **write a reason**. Guests don't even see the button.

Starburst check (not a circle): **gold** = owner, **blue** = someone they trust. You cannot buy or apply. ★ Mod's Pick = a mod featured it.

### Forgot password

Sign-in → **Forgot password?** → email → link lasts **45 minutes**. 2FA still needed after reset. Stoop 2FA ≠ the phone-web 2FA.

### What data does The Stoop collect?

Only if you sign in: email, name, 18+ tick, hashed password, optional profile, the cards you upload, votes/downloads, a hashed IP + install id for bans (90 days), optional anonymous “what GPU do people have” ping (off switch on signup).

Never: your chats. Delete the account from the app to wipe Stoop data. [Privacy](https://github.com/linux4life1/front-porch-AI/blob/main/PRIVACY.md).

---

## Living characters

### Where did the switches go?

**Settings → Porch Life.** Not General.

Journal, clock, Chaos, Pockets, Objectives each have **their own** switch. Realism is not the master key. Full list: [Porch Life](porch-life.md).

**18+ themes** is still Settings → **General**.

### How does time work?

The story has **its own clock**. It is **not** your wall clock and it does **not** follow today's real date.

**Turn it on:** Settings → **Porch Life** → **Passage of Time**.

That row does **not** need the Realism Engine. Two different cases:

| Realism Engine | What the clock does |
|---|---|
| **On** | Clock is judged as part of work the engine already does. No extra switch. |
| **Off** | Passage of Time being on is **not enough**. You must also turn on **Keep the clock running without the engine** (the small switch under that row). That costs **one extra AI call per turn**. Leave it off and the clock **holds still**. |

**What “auto” means**

1. You send a message. They reply.
2. **After** the reply, the app asks the AI: “how many minutes did that beat take?”
3. The clock moves by that amount. Next speaker is told the new time.

- A hello might be 2 minutes. A long drive might be two hours.
- **Hard cap: 180 minutes (3 hours) per turn.** Bigger jumps are skips (below), not auto.
- If that AI call fails or returns garbage: the clock creeps **5 minutes**. It never freezes on a failed call.
- If it still hasn't moved after **12 turns**, the app hops to the next time of day by itself.
- **Continue does not tick.** Same beat. New message = new beat.
- **Regenerate / swipe** rewind the clock to before that reply, then judge again. It will not double-advance.
- In a **group**, one clock for the whole scene (guests included).

**What you see**

Sidebar **Character State**: something like **Morning · 9:00 AM** and **Wed, Mar 3 · Day 3**.

Six periods (and the time they land on if the app only knows the period):

| Period | About |
|---|---|
| Dawn | 6:00 |
| Morning | 9:00 |
| Late morning | 11:30 |
| Afternoon | 2:30 |
| Evening | 6:30 |
| Night | 10:30 |

Past midnight = next **story** day. Sleeping through the night in-scene can start a morning — only when the scene actually says so.

Set the **opening date and clock** on the character card if this is 1887, not “today.” Existing chats keep the clock they already have.

**What rides on the clock**

- **Story Weather** — needs Passage of Time.
- **Dreams** — needs Journal **and** Passage of Time (🌙 banner after a story night).
- **Clock In** (job/hours) — uses this clock. “They're at work” is the occupation feature, not a stuck clock.
- **Planner** — needs Time + Objectives + Journal.

[Porch Life](porch-life.md). Deep numbers: [Realism Engine](realism-engine.md#the-passage-of-time).

### Why isn't the clock moving?

Do these in order:

1. Settings → **Porch Life** → **Passage of Time** is on (and the **chat** didn't override it off in Character State → tune).
2. Realism Engine **off**? Then **Keep the clock running without the engine** must be on, or the clock is supposed to sit still.
3. You hit **Continue** — that does not advance time. Send a new message.
4. No model / backend not running — auto time is an AI question. It cannot judge minutes without a model.
5. You expected a 6-hour jump from one reply — auto **cannot** do that. [Skip](#how-do-i-skip-time).

### How do I skip time?

Auto will never jump more than **three hours**. For “next morning” / “a week later,” you skip.

**1. Type it (fastest)**

Works if the message looks like a skip, including:

- `(OOC: several hours later)` / `[OOC] skip ahead` / `OOC: time skip`
- “a few hours”, “hours later”, “the next morning”, “the next day”, “a week later”, “next week”, “a month later”
- “slept through the night”, “sleep until morning”, “woke up”

“Let's go to bed” is **a scene**, not a skip. A **finished** night is.

A night skip lands **morning**, can restore energy a bit (hunger/bladder stay). You'll see a small **time-skip chip** on the next reply.

**2. Nudge one period**

**‹ ›** next to the date in Character State — back or forward one bucket (dawn → morning → …).

**3. Set the clock exactly**

**Tap the date** → **Story Calendar**. Pick the day and the time. Days with memories are marked; tap one to read what they remember.

AFK / Dynamic Responses can also eat story-time per scene (hours / half day / full day) — that is the AFK gear, not the calendar.

### Why does it say they're at work?

**Clock In.** They have a job and hours on the **story** clock. Skip a turn during a shift → banner. Night skip lets them rest. They can still talk to you from work (“with you” is scored after they speak).

Not a stuck clock. Change hours, skip to after the shift, or turn occupation off. [Clock In](porch-life.md#clock-in).

### What are Pockets?

Clothes and stuff they carry. Own switch on Porch Life. Does **not** need Realism. Journal → **Belongings**. [Pockets](porch-life.md#pockets--wardrobe).

### What is the Realism Engine?

Optional. Mood, bond, trust, needs, goals. **Off** by default on new singles; **on** by default on new groups. The **story clock is a separate switch** (Passage of Time) — it is not “the engine.” Full tour: [Realism Engine](realism-engine.md).

### Does Realism make chat slow?

A bit. Extra short AI questions after each turn. Character State gear → **One-Shot Eval**: **Auto** (fuse when the backend can), **On**, or **Off**. Or turn Realism off.

### Reset bond / trust

Start a **new chat**. There is no reset inside an old one. Editor “starting values” only affect chats you start *after* you change them.

---

## Voice

### No sound

First time, Kokoro downloads ~380 MB. Wait.

Settings → **Voice & Media**. Kokoro = free local. ElevenLabs/OpenAI = key + internet.

If you switched engines, pick the character's voice again (old engine voices don't exist on the new one).

### Better voices

Kokoro = best free. ElevenLabs = best paid. Piper = lots of distinct voices (import `.onnx` + `.onnx.json` on **desktop**). Each character can have their own voice.

### Voice call cuts me off

It sends after ~2 seconds of silence. Headset. Lower mic gain. Hang up and call again. Or tap **Send** yourself. **Phone has no Voice Call** — only hold-to-talk, and only on HTTPS.

---

## Other buttons people ask about

### AI Enhance

Home screen → **right-click the character** → **AI Enhance**. Pick a chat. It interviews you, you tick what to rewrite, it saves **Name (Enhanced)**. You can bring those chats along. It is **not** in Porch Life.

### Arrows on the portrait

◀ ▶ on the sidebar face = different **looks** from the Avatar Gallery for *this chat*. Not the mood/expression pack.

### AFK / they keep talking while I'm away

**One-on-one:** sidebar **Story Tools** → **Dynamic Responses**. The gear: reply every 30–300 seconds, stop after 1–10 scenes, how much *story time* each scene eats (a few hours / half day / full day). Typing cancels it.

**Groups:** that panel is hidden. Use `/afk` (see [User Guide slash table](user-guide.md#slash-commands)).

### Where do I set their job?

Open the character → **Details**: Occupation, a short brief, hours, which weekdays. That is Clock In. Skip a turn during those hours → “at work” banner.

Likes / dislikes are **chip lists** on Details, not the personality paragraph. Intimate into/not-into only show if Settings → General → **18+ themes** is on. Worn / carrying on the card *seeds* Pockets; you still need the Pockets switch in the chat.

### Custom weather / seasons

Worlds → edit the Place → climate editor. **2 to 8** seasons (not stuck at 4). Each season has a start month/day — overlap blocks save. Day–night swing = how hard it cools after sundown. You can start from a built-in biome. Atmosphere: Breathable / Thin / Unbreathable / Hostile. Gravity: Earth / Low / High / Micro.

### Porch Stories — how do I start?

Backend must be running. Home → Porch Stories → new project. Steps: **Engine → Concept → Style → Format → Cast → Review**. If you ticked “use chat history,” a Distiller pass runs *before* the bible so it tracks what actually happened. Then Architect (bible) → Act Structurer → scene beats → prose. Chat → **Turn Into a Story…** is the shortcut (desktop).

### Import a lorebook

**Import Lorebook** (not the same as importing a character): pick a file → send it to a new Place, characters, a group, or the current chat. You can also pull another card's lore into this character from the editor.

Same-name import asks **skip / replace / keep both**. One-file Import Cards can ask for tags; bulk folder import does not.

SillyTavern **SQLite** import is a real path too (characters + chats), not only PNG/JSON.

### Reprocess Needs

Turned Needs on mid-chat, or an eval went weird: **Reprocess Needs Deltas** rebuilds Needs history from that conversation. [Porch Life](porch-life.md#reprocess-needs).

### Scan & Clean vs Reclaim

Settings → **Advanced**:

- **Scan & Clean** — orphan avatars, leftover embeddings, dead sessions.
- **Reclaim Disk Space** — old sidecar leftovers. Different button. Do not mix them up.

---

## Phone, backups, updates

### Chat from my phone

1. Desktop: Settings → **Advanced** → **Web Server** → on.
2. Same Wi-Fi: open `http://YOUR-PC:8085`.
3. First visit: create a web login. Away from home / not localhost: also type the **setup code** from that Settings page.
4. Desktop must stay on. It is the brain.

Add to Home Screen: Android may pop a banner; iPhone is Share → Add to Home Screen.

Away from home: Tailscale (phone has a **Remote** page: HTTPS, optional ngrok, QR).

### What's missing on the phone?

**Desktop only:** full Image Studio (Create/Edit/packs), Voice Call, Suggest Actions, attach a photo, Stoop **upload**, Backups, Scan & Clean, Turn Into a Story.

Phone **can** still make a picture from **Models** or `/image`. Mic needs **HTTPS** (`http://192.168…` will refuse the microphone).

[Web & Phone](web-phone.md).

### Backups

Automatic every 30 minutes. Last 10 + one per day for 7 days. Sidebar → **Backups & Restore**. Since 1.2, restore usually doesn't need a restart.

A backup is the **database** (chats, memories). It does **not** put back a deleted character PNG or your GGUF files. Copy the whole `FrontPorchAI` folder for a full spare.

Nightlies: restore UI is hidden; auto snapshots still run.

### Where is my data?

- Windows: `Documents\FrontPorchAI\`
- Mac / Linux: `~/Documents/FrontPorchAI/`
- Nightly: `FrontPorchAI-Beta`

Change the folder: Settings → **Advanced** → Data directory.

### Two computers

No cloud sync (it was deleted on purpose). Copy the `FrontPorchAI` folder, or use the web server from the other machine.

### Updates

Windows/Mac: in-app “What's New.” Linux APT/RPM: normal system update. AppImage: in-app too. AUR is behind (1.1.2 vs current 1.3.1) — use APT/RPM/AppImage if you want Places files.

### Report a bug

[GitHub Issues](https://github.com/linux4life1/front-porch-AI/issues) or [Discord](https://discord.gg/e4tET6rpdv). Run from a terminal if you can — the errors help. [Troubleshooting](troubleshooting.md) first.
