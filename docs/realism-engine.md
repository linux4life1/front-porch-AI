# The Realism Engine

The Realism Engine is Front Porch AI's signature feature — the system that turns a character from a clever text generator into someone who *remembers how they feel about you*. This guide walks through every part of it in plain language: what it tracks, what you'll see on screen, and how to tune it.

---

## Table of Contents

1. [What Is the Realism Engine?](#what-is-the-realism-engine)
2. [Turning It On](#turning-it-on)
3. [What You Will See](#what-you-will-see)
4. [Bond: How They Feel About You](#bond-how-they-feel-about-you)
5. [Trust: How Safe You Seem](#trust-how-safe-you-seem)
6. [Emotions That Linger](#emotions-that-linger)
7. [Desire and Intimacy Pacing](#desire-and-intimacy-pacing)
8. [The Passage of Time](#the-passage-of-time)
9. [Objectives: Goals of Their Own](#objectives-goals-of-their-own)
10. [Fixations: Thoughts That Won't Let Go](#fixations-thoughts-that-wont-let-go)
11. [Character Evolution](#character-evolution)
12. [Chaos Mode (Chance Time)](#chaos-mode-chance-time)
13. [The Needs Simulation](#the-needs-simulation)
14. [Expressions: Seeing the Mood](#expressions-seeing-the-mood)
15. [Group Chats](#group-chats)
16. [The Director (Optional Quality Check)](#the-director-optional-quality-check)
17. [Speed, Cost, and Tuning](#speed-cost-and-tuning)
18. [When Things Look Weird](#when-things-look-weird)

---

## What Is the Realism Engine?

Without the Realism Engine, every message you send is judged in isolation. A character can pour their heart out one turn and greet you like a stranger the next. Nothing deepens, nothing heals, no time passes.

With it on, the app quietly asks your AI model a few short follow-up questions after each exchange — things like *"Did that change how she feels about him?"* and *"Is she still upset about earlier?"* — and keeps a running score of the relationship. Those scores are then woven back into the next reply, so the character's warmth, guardedness, mood, and sense of time all carry forward naturally.

What that feels like in practice:

- **Kindness compounds.** A genuinely sweet gesture can warm a character for dozens of turns. A betrayal can sour things for a long while.
- **Moods have weight.** Emotions drift and linger instead of snapping back to neutral after every message.
- **The world keeps time.** Mornings turn to evenings, days accumulate, and characters remember where they are and what they were doing.
- **Nothing overrides personality.** The Realism Engine colors *how* a character expresses themselves — a prickly character at maximum bond is still prickly, just softer around the edges with you.

The whole system is optional and **off by default**. When it's off, no extra evaluation calls run at all and chats behave like a traditional character AI.

---

## Turning It On

You can control the Realism Engine at three levels:

**1. In Settings (your default for new chats).** Open Settings and find the Realism options. The master toggle turns the engine on for new conversations, along with sub-features like NSFW Cooldown and Automatic Passage of Time.

**2. On the character card.** The character creator and character editor both have a Realism Engine panel where you can enable it for that specific character and set the opening state of a brand-new chat: starting bond, trust, emotion, time of day, and which sub-features begin switched on. These settings only seed *new* conversations — existing chats keep the state they've already built up.

**3. In the chat itself.** The chat sidebar has a **Realism Mode** section where you can flip the engine (and its sub-toggles, like **Automatic Passage of Time** and **One-Shot Eval**) for the conversation you're in right now. Turning realism on mid-chat makes the engine read back through the recent conversation so it can catch up instead of starting cold.

![The settings page, where the Realism Engine defaults live](screenshots/new_settings.png)

> **Tip:** The engine even runs once on the character's greeting — before you've typed anything — so the opening mood matches the opening message. You'll see a brief *"Reading the room..."* overlay when that happens.

---

## What You Will See

Three things change on screen when the Realism Engine is active:

- **Chips under replies.** When something meaningful shifts — bond up, trust down, a mood change, a time skip — small chips appear under the character's message showing exactly what moved and by how much. Quiet turns produce few or no chips; that's by design.
- **The sidebar.** The chat sidebar shows the character's current bond and trust levels, their mood, the in-story time and day, any active fixation or objective, and (if enabled) their needs bars.
- **A brief processing overlay.** After a reply, you may see a short "thinking" overlay while the engine runs its check-ins. There's a cancel button if you'd rather skip it — interrupting is always safe.

![A chat with the Realism sidebar and message chips visible](screenshots/chat.png)

---

## Bond: How They Feel About You

Bond is the heart of the system, and it comes in two layers that move at very different speeds.

**Short-term bond** is the character's current feeling toward you, on a scale from **−300 to +300** with named tiers along the way — from open hostility at the bottom to utter devotion at the top. Ordinary conversation nudges it a point or two at a time; only genuinely meaningful moments move it in big jumps. It also slowly drifts back toward neutral over time (about one point every ten turns), so relationships never get permanently stuck at an extreme — you have to keep showing up.

**Long-term bond** uses the same −300 to +300 scale but grows much more slowly, from *sustained* patterns rather than single moments. Keep the short-term relationship warm for a long stretch and the long-term bond quietly climbs; keep hurting someone and it erodes. Once earned, it's sticky: a character with deep long-term attachment keeps an undercurrent of affection even during a short-term fight — which is exactly how real relationships weather bad days.

Both feed directly into how the character writes: how open they are, how much warmth or frost is in their voice, how far they'll let you in.

---

## Trust: How Safe You Seem

Trust is deliberately separate from bond. Bond asks *"How do I feel about you?"* Trust asks *"How safe are you?"* — and you can absolutely have one without the other.

Trust runs from **−100 to +100** and moves conservatively. Only your behavior moves it; the character's own actions never do. At deeply negative trust a character questions every motive and keeps everything surface-level. Around zero, their natural personality does the talking. At high trust, the mask comes down: they share real feelings and real vulnerability — expressed the way *that* character would express it.

**Trust repair.** If you badly damage trust in a single turn, the engine watches your very next message closely. A sincere, personality-appropriate attempt to make it right can win back a meaningful chunk of what was lost. A glib "sorry" usually gets the reception it deserves.

---

## Emotions That Linger

Every active turn, the engine updates the character's emotional state — not a flat "happy" or "sad," but a nuanced feeling (*wistful*, *flustered*, *guarded*, *smoldering*...) with an intensity from mild to strong, filtered through who the character is.

The key idea is **inertia**. Small moments cause small drift. Big moments — a fight, a confession, an intimate scene — leave a mark that takes several turns to fade. Characters stop emotionally teleporting, and the conversation gains a believable emotional throughline.

The current mood shapes tone, body language, and word choice in the next reply, and it survives app restarts, swipes, and regenerations.

---

## Desire and Intimacy Pacing

For mature roleplay, the engine can track physical desire on a scale from **−100 to +100**, with descriptive tiers from completely unmoved up to overwhelming. This is about *current desire and physical response* — it shapes how the character's body reacts and whether they would (or wouldn't) escalate.

**NSFW Cooldown** is the sub-feature that makes intimate scenes end the way real ones do. When the engine notices a scene has naturally reached its peak, it starts a recovery window — usually a handful of turns, judged from the character's personality. During recovery the character is written as genuinely spent: oversensitive, wanting closeness rather than another round, gradually settling back to normal in phases. They'll deflect immediate re-escalation because, honestly, they need a minute.

None of the mechanics ever appear in the chat itself — no numbers, no "cooldown" talk. The character just behaves like a person. You can turn the **NSFW Cooldown System** on per character in the editor or in your realism settings.

---

## The Passage of Time

With **Automatic Passage of Time** on, the story develops its own clock:

- Time of day advances on a steady rhythm — after every **6 character replies**, the scene moves to the next period (morning → afternoon → evening → night...).
- The model gets exactly one veto: if the scene is visibly mid-action (a fight, a kiss, a crisis), it can hold the clock until things settle. It can never skip ahead on its own.
- Night rolling over into dawn advances the day counter, and the sidebar shows the story's weekday and day count (like *Wednesday · Day 3*). Sleeping and waking in the story can also trigger a new day.

**You stay in control:**

- Type an out-of-character note like `(OOC: we drive for several hours)` and the clock jumps immediately, with a small time-skip chip on the next reply.
- Use the **‹ ›** chevrons next to the date in the sidebar to nudge time backward or forward by hand.

Even with the clock switched off, the engine keeps light track of *where* everyone is — sitting on the windowsill, standing in the rain — so characters stay physically grounded between turns instead of teleporting around the scene.

---

## Objectives: Goals of Their Own

Characters can have objectives — ongoing goals that give them a life beyond reacting to you.

- **Autonomous objectives.** Every so often, when the story genuinely supports it, the character will adopt a personal goal on their own ("find out who sent that letter"). When that happens, the engine automatically breaks it into **three concrete, sequential tasks** the character can pursue, and quietly checks progress as the story unfolds.
- **Your objectives.** You can also type in an objective for the character yourself from the sidebar. Objectives you create deliberately do *not* auto-generate tasks — you stay in control — but there's a button to generate tasks for one whenever you want them.

Most turns produce no new objective at all. That's intentional: goals should feel like story beats, not spam.

---

## Fixations: Thoughts That Won't Let Go

Sometimes something lands hard enough that a character can't stop thinking about it — a worry, a hope, a memory, something you said three scenes ago. The engine calls these **fixations**.

When one takes hold, it subtly colors the character's responses for the next **3 turns**: a stray thought here, a loaded pause there, the topic resurfacing if the conversation drifts near it. It never hijacks the scene — it just gives the character a believable inner life that keeps running between moments. The active fixation is visible in the sidebar, and fixations fade naturally on their own.

---

## Character Evolution

Over a long story, people change. Character Evolution lets your characters do the same.

Periodically (roughly every ten of your messages), the engine looks back at everything that's happened and considers whether the character has grown — a new soft spot, a changed outlook, a scenario that has moved on. Approved changes are layered onto the character's personality *for that chat*: your original character card is never modified, and other chats with the same character are unaffected.

The evolution count shows in the character's summary, and the newest builds let you tune how often evolution runs, per character. It's a separate toggle from the main Realism switch, but the two together are where the "living character" feeling really comes from.

---

## Chaos Mode (Chance Time)

Chaos Mode is the drama engine — for when you want the story to surprise *you*.

While it's on, pressure builds behind the scenes: a **5% base chance** of an event each turn, growing by **5% every turn** nothing fires, up to a guaranteed maximum. When it triggers, a full spinning-wheel overlay takes over the screen, you spin, and fate hands the scene an event the character *must* react to — there's no dismissing it, only **Accept Your Fate**.

The pool holds **more than 175 events** across four flavors — 🟢 fortune, 🔴 misfortune, 💛 chaos, and 💜 wild cards — plus a healthy stack of pure slapstick. A 🌶️ toggle adds a spicier event pool for mature chats. Events are written as natural story beats (a stranger pays for the character's meal; a very personal delivery arrives at the worst moment), and the character reacts to them in-fiction without ever mentioning the game mechanics.

A few practical notes:

- The sidebar shows the current pressure, and a **SPIN NOW** button lets you trigger the wheel on demand.
- A triggered event survives regenerates and swipes — no rerolling your way out of it. It clears when you send your next message.
- Pressure resets to zero after each event fires.

---

## The Needs Simulation

The Needs Simulation is an optional layer on top of the Realism Engine that gives characters a body and a daily rhythm, in the spirit of classic life-sim games. Each character tracks **seven needs**, each on a 0–100 scale:

| Need | When it runs low... |
|---|---|
| **Hunger** | Stomach growls; they'll want to eat, and eventually can't ignore it |
| **Bladder** | Increasingly distracted; will excuse themselves if you don't |
| **Energy** | Yawning, flagging, genuinely exhausted |
| **Social** | Craves real connection and attention |
| **Fun** | Restless and bored; wants stimulation, mischief, *anything* |
| **Hygiene** | Feels grimy; wants to freshen up |
| **Comfort** | Physically uncomfortable; wants to shift, stretch, or relocate |

**How it plays out.** Needs drain gradually as story time passes. Below **35** a need becomes urgent and starts shading the character's behavior; below **20** it's critical and they will act on it. Let one hit rock bottom and you get a genuine story consequence — a character who hasn't eaten in far too long doesn't just mention it, they hit a wall. Needs also interact: a deeply bored character finds company less soothing, and nobody's comfortable with a desperately full bladder.

**The scene feeds the simulation.** What actually happens in the story is what moves the numbers. A meal restores hunger. A bath restores hygiene. A nap restores energy. Laughter, affection, and adventure top up fun and social. Intimate scenes ripple through several needs at once — and right after a peak, a character honestly has less in the tank for a while.

**What you'll see.** Chips under each reply show which needs moved and *why* ("Scene action," "Natural decay"...) — needs that didn't change stay out of the way. The sidebar shows live bars for every need, and in group chats each member's card shows their own.

**Making it yours.**

- Each need's behavior can be tuned per character in the editor, including a **Needs delta strength** dial (1×–5×) if you want gentler or much more dramatic swings from the same scenes.
- There's even an option for characters who canonically *enjoy* being a mess — low hygiene reads as contentment for them instead of distress.
- The numbers never appear in the story itself. The character just gets hungry like a person, not like a video game.

The Needs Simulation is newer than the rest of the engine and still being tuned — if you're trying it for the first time, start with a fresh chat and see how it feels before enabling it on a long-running story you treasure.

---

## Expressions: Seeing the Mood

If you use Character Expressions (emotion-driven portraits), the Realism Engine feeds them directly: the nuanced mood it tracks is matched to your character's expression image set, so the portrait genuinely reflects how they feel — covering a wide range of emotions, and compatible with standard SillyTavern expression packs. See the [User Guide](user-guide.md) for setting up expression images.

---

## Group Chats

Everything above works in group chats, per character. Each member keeps their **own** bond, trust, mood, desire, fixations, objectives, and needs — warm up to one character while another still doesn't trust you, and both will act like it. The character currently speaking is the one whose state shapes the reply and gets updated afterward, which keeps things fast no matter the group size.

![A group chat with per-character realism state](screenshots/group_chat_new.png)

A few group-specific notes:

- Chips and sidebar values always belong to the character who spoke.
- Newer builds are starting to track how group members feel about *each other*, too — not just about you.
- **Director Mode is the exception.** When you're directing scenes rather than living in them, realism and needs tracking pause (state is preserved and resumes when you switch back). Directing is storyboarding; regular group chat is the lived-in simulation.

The engine's behavior in a group is deliberately identical to a one-on-one chat — a character should feel like the same person whether you're alone with them or not.

---

## The Director (Optional Quality Check)

Smaller local models occasionally produce sloppy realism updates — numbers that don't match the scene you just read. **The Director** is an optional, per-character quality check that reviews each realism and needs update against the actual scene before it's applied, and sends obviously-wrong ones back for another pass.

- Turn it on in the character editor under Optional Features (it's **off by default** and costs nothing while off). Two sliders control how many correction passes it may attempt (1–5) and how strict it is (1–5).
- While it works you'll see *"🕵️ Verifying Realism output"* in the processing overlay, and afterwards a small chip on the reply: **"✓ Director accepted"** or **"🕵️ Director corrected"** — so you always know when the numbers you're seeing were double-checked.
- It does add extra evaluation calls, so it's best on a fast backend or a strong model. If your realism numbers already look sensible, you don't need it.

---

## Speed, Cost, and Tuning

The engine's check-ins are small and quick compared to the main reply, but they're real work — here's how to keep things snappy:

- **One-Shot Eval** (toggle in the chat sidebar's Realism section) folds the separate check-ins into a single combined call. It tracks the same things with noticeably less waiting — the go-to choice on slower machines and pay-per-token remote APIs. Very small models occasionally handle the combined question less gracefully than the separate ones; if your results get flaky, switch it back off.
- **Cancel anytime.** The processing overlay has a cancel button, and interrupting an evaluation never corrupts anything.
- **Toggle per chat.** Want a quick, lightweight conversation? Flip Realism Mode off in that chat's sidebar and it costs nothing at all.
- The engine's notes to the model add only a few hundred tokens and are always counted inside your context budget — they will never push your conversation history out of the window.

---

## When Things Look Weird

A few quick answers to the most common head-scratchers:

- **Bond and trust barely move.** That's usually correct behavior — ordinary chatting is *supposed* to produce small or zero changes. If nothing ever moves, check that Realism Mode is actually on for that chat, and consider a stronger model: very small models sometimes ignore the check-in questions.
- **Evaluations come back empty.** A known quirk of some local models. The app already uses the most tolerant format it can; if you see it often, a different model usually fixes it. More in [Troubleshooting](troubleshooting.md).
- **Time won't advance.** The model may be legitimately holding the clock mid-action — it re-tries after the next few turns. Check that Automatic Passage of Time is on, or nudge the clock manually with the sidebar chevrons.
- **You want a clean slate.** Start a new chat with the character — the starting state on their card applies fresh, and the old chat keeps its own history.
- **Everything is slow.** Turn on One-Shot Eval, or disable realism for that particular chat. Running several heavy things at once (a big model, TTS, image generation) compounds on modest hardware.

For deeper fixes, see [Troubleshooting](troubleshooting.md) or ask on [Discord](https://discord.gg/e4tET6rpdv) — I'm around, and so is a friendly community.

---

**One last thing.** The Realism Engine is the reason this app exists. Leave it on for a few long sessions with a character you like — the difference between "talking at an AI" and "having a relationship that grows, breaks, heals, and changes" is honestly night and day.
