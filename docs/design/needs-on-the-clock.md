# Needs on the clock — statement of work

Rewrite the needs engine. Keep the chat looking and behaving as it does now.

The old engine stays in place until the new one is finished. Then it is deleted. Do not extend it. The per-need tick rates, the 1×–5× strength slider, the keyword fallback, the night-skip number patches, and the "drain a fixed bite before the reply" tick were all ways to wrestle deltas that moved too fast. None of them come forward.

## What the user still sees

Unchanged in the chat, on desktop and on the phone:

- The needs on/off switch, for the whole system.
- A bar for each need that is turned on, in the sidebar, for the solo character and for each group member. All seven start on, so an untouched character looks as it does today.
- Starting values on the character.
- "Enjoys low hygiene."
- Chips under the reply for what changed, with the reason, and redo / revert on the last reply.
- The character still speaks from the bars (hungry, exhausted, and the rest).
- Hitting empty still has a consequence (an accident, a collapse, and the rest).
- Regen and swipe still put the bars back and replay that reply.
- Continue still extends the same moment.

The character editor and the group needs tab lose the seven decay sliders and the strength slider. In their place, one pace control per character: **Sloth**, **Normal**, **Fast**. Normal is the default. An older card still opens. Its saved tick rates and strength values are not read and are not written back. Each need also has its own on/off, on desktop and on the phone.

## Needs can be turned off one by one

Each character chooses which needs are alive. All seven start on.

A need that is off:

- has no bar, no chip, and no line in the prompt
- does not wear when time passes
- ignores a scene number, even if the model sends one
- does not collapse when it would have hit empty

The number already stored for that need stays. Turning it back on shows the same bar.

Pace only scales the drops of needs that are on. The master needs switch still turns the whole system off.

No new need is added in this work. The seven stay the list. A later need is one more row with the same switch, not another rewrite.

## How a turn works

Two jobs.

- **Code** wears the body because time passed, and applies pace.
- **The model** changes the bars because of what the scene did. It sees the bars that are on, and how long the beat was. It picks the numbers as if pace were Normal. Code does not price a meal or a walk.

## Pace

Pace is a speed control on drops only. It never changes a plus.

The model answers once, at Normal. Code then multiplies every minus by the character's pace and leaves every plus alone. That includes time-wear, which is always a minus, and a scene number that came back negative.

- **Sloth** — two thirds of the drop.
- **Normal** — the drop unchanged.
- **Fast** — four thirds of the drop.

A 30 minute bath that the model scores as hygiene up lands on the same plus at Sloth, Normal, and Fast. A two hour run that the model scores as hygiene −30 lands on −20 at Sloth, −30 at Normal, and −40 at Fast.

If one beat has both, they are handled apart. The bath's plus stays. The run's minus, and the time-wear, are what the slider changes. Pace is applied before the result is added to the bar.

**Clock on.**

1. The character replies from the body they already have. Nothing wears yet.
2. The clock decides the minutes.
3. Code wears every need that is on for that awake time, at Normal, then pace scales that drop.
4. The model reads the reply and reports only the scene, at Normal.
5. Code scales any minus in that report by pace, leaves every plus alone, and adds both on top of the wear. One reply cannot empty a bar by itself.
6. The next reply is the first one that shows both.

**Clock off.** One send wears the body by one ordinary beat, scaled by pace. The model still reports only the scene. No minutes are invented.

**Continue.** Same beat. The model scores the new text. Code does not wear the body again.

**Night, skip to morning, or time away.** Awake wear does not run across those hours. The model is the only writer for that beat, and it is told the span: next morning, or gone for about four hours. Its report is the whole change.

**A group.** The minutes pass for everyone who is present, each at their own pace. Only the speaker gets the scene. Someone who is away uses the away beat.

## Time chip on every turn

Today the only time chip is **Time skip**, and it appears only when a skip lands on a clock time (`Time skip: 8:00 AM`). A normal reply can move the clock and show nothing.

Every reply that moves the clock gets a chip for how much time passed.

- The number is the minutes the clock actually applied on that reply. Same number the needs model is told.
- Wording: `12 min`, `1 hr`, `2 hr 30 min`. Under a minute, no chip.
- Clock off, Continue, or a reply that does not move the clock: no chip.
- A skip still uses the existing **Time skip** chip, for where the clock landed. It does not also get a duration chip.
- A jump to the next morning is one chip: `Next morning`.
- In a group, the chip sits on the reply that moved the clock.
- Regen and swipe show the minutes for that swipe.
- Desktop and the phone use the same words.

The chip uses the clock that already exists. It does not wait on the rest of this rewrite.

## Needs chip

When both time and the scene moved a bar, the chip shows both. The time, and the scene. One reason must not hide the other.

## Done means

- Chat screens listed above still work, desktop and phone, solo and group.
- Pace is the only speed control, and it scales drops only. A plus is the same at Sloth, Normal, and Fast. No tick rate remains in the editor, the save file's live path, or the engine.
- Each need can be turned off per character. Off means no bar, no wear, no scene number, no prompt line. Turning it back on restores the stored bar. All seven default to on.
- The new engine is new code. The old simulation, decay tables, and tick call are removed, not wrapped.
- A short clock-on exchange wears less than a long one. Clock off wears one beat per send. Continue does not wear twice. A night or time away does not also run the awake wear.
