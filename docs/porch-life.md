# Porch Life

Every living-character switch lives in **Settings → Porch Life**. Not General.

**Realism Engine is not the master key.** Journal, the story clock, Chaos, Pockets, and Objectives each have their own switch. Turn on what you want. New chats pick up those defaults. An open chat can still override them (Character State → **tune**, or Group Settings → Realism).

**18+ themes** is Settings → **General**. Off hides After Dark and intimate card fields. It does not erase what you already set.

**AI Enhance** is not on this tab. Home → right-click a character.

The numbers, moods, and needs deep-dive is the [Realism Engine guide](realism-engine.md). This page is the switches and the clock.

---

## The rows

| Row | Needs | What it does |
|---|---|---|
| **Realism Engine** | — | Mood, bond, trust, lingering feeling. Off by default on new singles; on by default on new groups. |
| **Needs** | Engine, to turn a need into a mood | Hunger, energy, social, … |
| **Passage of Time** | A model (see clock below) | Story clock. Own switch. |
| **Story Weather** | Passage of Time | Sky from the *story* date. °F is display-only under this. |
| **Temperatures in °F** | Weather | Display. Characters still get weather in words. |
| **The Journal** | — | Memory cards + “where we are,” per chat. |
| **Dreams** | Journal **and** Time | 🌙 after a story night. |
| **Promises** | Engine | Kept / broken / hanging. |
| **Pockets & Wardrobe** | — | Clothes and carried things. Extra model call when inventory changes. |
| **Hand things between characters** | Pockets | Group pass. |
| **Standing Mood** | Engine | A bad day that is not about you. |
| **Growth Rings** | Engine | They change over a long story. Optional review dialog before apply. |
| **Objectives** | — | Goals. |
| **Ambitions** | — | Long-held wants (card chips + engine). |
| **Notice new characters** | — | Offer to add someone the story named. `/scan` still works if this is off. |
| **Planner** | Time + Objectives + Journal | They plan; you add or delete the line. |
| **Chaos Mode** | — | Chance Time events. |
| **Welcome-back recap** | — | Banner after a long real-world gap. Coarse (“a few days”). |
| **Character notices your absence** | Recap | One in-character mention. Off by default. Never guesses what you were doing. |
| **Afterglow** | 18+ themes | Desire settles after a scene. Old name: NSFW Cooldown. |
| **Acts on desires** | 18+ | Card intimate prefs are said and acted on, not only scored. |

---

## Passage of Time

The story has **its own clock**. It is not your wall clock. It is **not allowed** to follow today’s real date when you reopen the chat.

### Turn it on

Settings → Porch Life → **Passage of Time**. Per chat: Character State → **tune** → Automatic Passage of Time.

| Realism Engine | Clock |
|---|---|
| **On** | Judged as part of work the engine already does. |
| **Off** | Passage of Time **on is not enough.** You must also enable **Keep the clock running without the engine** (nested under that row). That is **one extra AI call per turn**. Default **off** — otherwise every engine-off user would suddenly pay that call. Left off, the clock **holds still on purpose**. |

### Auto (after each reply)

1. You send. They reply.
2. **After** the reply, the app asks: how many minutes did that beat take?
3. The clock moves. The next speaker is told the new time.

- Cap: **180 minutes (3 hours)** per turn. Bigger jumps are **skips**.
- Failed / garbage eval: **+5 minutes**. Never a freeze on a failed call.
- Still stuck after **12 turns**: snap to the next period.
- **Continue does not tick.**
- **Regenerate / swipe** rewind to `story_clock_before`, then judge again (no double advance).
- **Group:** one clock for the scene, guests included.

Sidebar: **Morning · 9:00 AM** and **Wed, Mar 3 · Day 3**.

| Period | Lands around |
|---|---|
| Dawn | 6:00 |
| Morning | 9:00 |
| Late morning | 11:30 |
| Afternoon | 2:30 |
| Evening | 6:30 |
| Night | 10:30 |

Past midnight = next **story** day.

Opening date/time is on the **character card** (new chats only). Existing chats keep the clock they already have.

### Skip time

Auto will never jump a week. Skip instead.

1. **Type it** — `(OOC: several hours later)`, `[OOC] skip ahead`, `OOC: time skip`, “a few hours”, “hours later”, “the next morning”, “the next day”, “a week later”, “next week”, “a month later”, “slept through the night”, “sleep until morning”, “woke up”.

   “Let's go to bed” is a **scene**, not a skip. A **finished** night is. Night skip lands **morning** (energy can recover a bit; hunger/bladder stay). Time-skip chip on the next reply.

2. **‹ ›** next to the date — one period.

3. **Tap the date** → **Story Calendar** — set day and time. Marked days have memories.

AFK story-time pace (hours / half day / full day) is the Dynamic Responses gear, not the calendar.

### Clock not moving?

1. Passage of Time on (chat tune didn’t override it off).
2. Engine off → standalone nested switch on.
3. You hit Continue.
4. No model running — auto time *is* an AI question.
5. You wanted a 6-hour jump — skip.

Short version: [FAQ](faq.md#how-does-time-work).

---

## Birthdays

Year, month, and day on the **character** (Porch Life chips) and on your **persona** (the Persona page, Speak as…, and the phone Settings persona editor). February 29 is not allowed.

Age and “how many days” follow the **story calendar**, not your wall clock. The Journal keeps **one** card per person (`I'll be 28` becomes `I'll be 29` next year — it does not duplicate). That card heats up in the two weeks before; it is a background thought, not a shopping list. Quiet days far from a birthday do not rewrite the card, and neither does Continue — heat only moves once the story date is inside those two weeks, on the day, or the two days after. A cake or present in Pockets is a gift if you actually hand it over.

Objectives: inside those two weeks they may get a frozen outing from their likes. Up to four side quests, so both birthdays can plant without kicking yours. Planner Today is not used — both birthdays live in the Journal, so they can fall on the same day. Off = they can still know the date from the diary when Journal is on.

## Clock In

Occupation, weekdays, hours — on the character **Details** tab.

Skip a turn during a shift → “at work” banner. That banner uses the **story** clock. Night skip lets them rest. **With you** is scored after they speak — they can be at work and still talking.

Change hours, skip to after the shift, or turn occupation off. Not a bug.

---

## Pockets & Wardrobe

Own switch. Does **not** need the engine.

Wear, carry, set aside. Hand them something; take it back; in a group, **Hand things between characters** lets them pass it.

Card chips (worn / carrying) **seed** a new chat. The switch still has to be on in the chat. Journal → **Belongings** is the ledger. Per-item editor: name, notes, worn vs carried.

If they “forget” an object, check the switch and Belongings before blaming the model.

---

## Reprocess Needs

Needs history can get out of date if you turned Needs on mid-chat or an eval went bad. **Reprocess Needs Deltas** rebuilds that history from the existing conversation. It does not start a new chat.

---

## Growth review

If **Review growth before it applies** is on, proposed Growth Rings wait on a checkbox dialog. Nothing writes until you approve.

---

## See also

- [FAQ living characters](faq.md#where-did-the-switches-go)
- [Realism Engine](realism-engine.md)
- [Chatting](chatting.md)
