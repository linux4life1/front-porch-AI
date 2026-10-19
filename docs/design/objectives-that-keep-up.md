# Objectives that keep up — statement of work

Version 1, approved 2026-10-16. Status at the end.

Objectives stop being a checklist frozen on the turn it was written. Each check becomes a sync that asks where every open goal stands and rewrites the next step to fit the story; a time skip makes the sync re-plan; the character only takes up a new want when it is genuinely new; and landing or losing a goal is something the character feels and remembers. The test is the product's north star: a goal is worth keeping only if it reads as something the character wants for themselves, and the tracker's job is to remember their life, not to steer them.

Built on mood with bite (#542): the mood door is the reward channel. Bond and trust are not touched (ruling 2026-10-13: the user's goals can conflict with the character's).

## What the engine does today (from the code and the maintainer's library)

| Finding | Evidence |
| --- | --- |
| The narrative judge proposes most turns. It sees only the main quest, never the side quests or recent retirements, and dedups on exact text, so it files rewordings of the same wish. | Senjumaru, 103 messages: a new side quest on 19 of the first 47 character turns |
| The cap of four side quests evicts the oldest unstarted one almost every turn. | 64 evictions in 287 objective rows |
| Steps are written once, from the last ten messages, and never revised. The check can only tick the FIRST open step, so progress out of order is invisible. The prompt carries a hedge admitting the tracker lags. | `author_note_builder.dart` staleness hedge; 56 eval-made quests retired with steps still open |
| Retirement for irrelevance needs two explicit "no" verdicts in a row, an "unsure" resets the count, the count lives in memory and dies on restart. | 3 stale retirements in 287 rows |
| A time skip never touches objectives. Only the planner's today line clears on a day roll. | Tess: a bedroom-scene main quest stayed live for 8 messages after a 27-day skip |
| An autonomous quest whose steps have not been generated yet is "achieved" by the first check (taskless + "be generous"). | Zinnia: two main quests achieved 2 and 6 messages after birth, with no steps |
| Every row has `created_at = 0`; the objective block skips macro expansion (`{{user}}` reaches the model in 14 rows); the card's authored task can be imported more than once. | library snapshot |
| Landing a goal changes nothing the character feels or remembers: no mood, no journal card, and the next proposal does not know it happened. | no achieved quest in the library appears in any journal card |

## What changes and what stays

Six things change. The check becomes a sync with a living step list. A time skip makes the next sync a re-plan. The proposal sees what the character already wants and has recently finished or dropped, and stops filing duplicates. A newborn goal cannot be won before it has steps. The prompt speaks in two voices. Finishing or losing a goal moves the mood, writes a diary card, and adds to a per-character tally the user can see.

Everything else stands: the per-quest Check-every slider and the mention gate (the cadence), one model call per check (the sync replaces the check, it is not added to it), the Objectives switch and its live AND, regen and delete rewinding a turn's objective changes through the existing turn ops, user-typed quests not auto-generating steps, the today line's own life, ambitions advancing only on a whole quest achieved, and 1:1 and group behaving the same per character.

## 1. The check becomes a sync

The same call at the same cadence, with a richer answer per open goal:

| Field | Meaning |
| --- | --- |
| status | `on_track`, `done`, `overtaken` (the story made it moot), `dormant` (still theirs, cannot be acted on now) |
| steps_done | which steps the exchange shows done, in any order (numbers), not only the first open one |
| next_step | the next concrete step, rewritten to fit where the story is now, or empty to keep the current one |

How the app applies it:

- `done` retires the goal as achieved (the ambition tick and the rewards below fire, as today).
- `overtaken` retires it as let go. One verdict is enough, because the sync is asked a direct question with the story in front of it; the in-memory two-in-a-row counter goes away.
- `dormant` keeps the goal but takes it out of the prompt and greys it in the sidebar with "set aside". A later sync can mark it `on_track` again.
- `steps_done` ticks those steps; `next_step` replaces the first open step's text (the old text is kept in the turn op so regen puts it back). The staleness hedge leaves the prompt.
- "Unsure" stays safe: a missing or confused answer changes nothing, as today.

Tools first, the text floor second, on the same `fireStructuredEval` fork; `status` is a required field (the is_climax lesson), strings say "none" rather than empty (the salvage lesson from #542).

## 2. A time skip re-plans

When the story clock has crossed a day since the last sync (an OOC skip at the start of a send, "next morning", time away, a calendar move), the next pre-reply check runs whatever the cadence says, and its prompt says how much time passed: "About two weeks have passed since these goals were last looked at." A goal tied to a scene that is over comes back `overtaken` or `dormant`; a long-running want comes back `on_track` with a next step that fits the new day. No goal is retired by the clock alone. The planner's today line keeps retiring on its day roll, as now.

## 3. Proposals that are genuinely new

- The narrative judge is shown every open goal and the last three finished or let-go ones, with a line asking for a want that is NOT one of those and not a rewording.
- The app also rejects a proposal whose content words overlap an open goal's beyond a threshold (the mention-gate tokenizer, cast names excluded).
- A side quest cannot be filed within four messages of the last one the character took up.
- At the cap, a new side quest is not filed; nothing is evicted to make room. The main quest is unchanged: a free main slot still takes the next proposal.

## 4. A newborn goal cannot be won

An autonomous goal is not synced until its steps exist. If step generation fails, it retries once on the next check; if that fails too, the goal stays as a taskless want that only an explicit `done` (never a lenient one on the turn it was born) can retire.

## 5. Two voices in the prompt

| Goal came from | Voice |
| --- | --- |
| The user (typed in the panel) or the card's authored task | Where the story is heading: `[Story direction: <goal>. Next: <step>.]` |
| The character (proposed by the judge) | Their own want, never an order: `<Name> wants: <goal>. What they'd do next: <step>.` |

"Actively drive the story toward this" leaves the character's own wants. A dormant goal is not injected. The block is macro-resolved like every other block.

This needs to know where a goal came from: a new `origin` column (`user`, `card`, `character`, `planner`), schema v58, additive. Rows from before read `user` unless they serve an ambition (then `character`), which is how they were made.

## 6. Feeling and remembering it

- **Mood.** Achieving a goal moves the mood through the door (`proud`, moderate; strong for the main quest), with "pulled off: <goal>" as the cause. Letting one go moves it to `disappointed`, mild, "had to let go of: <goal>". The quest only moves a mood that is weaker than its own: a character who is furious with you and also finishes something stays furious. Dormant moves nothing.
- **Diary.** With the Journal on, each achieved or let-go goal writes one card in the character's voice ("I finally …", "I had to give up on …"), cited at the reply, so deleting that reply takes the card with it.
- **The proposal remembers.** The last three finished or let-go goals ride the narrative judge's prompt (part 3).
- **A tally for the user, words for the model.** The sidebar's Objectives card and the phone show a running count per character for the chat ("3 landed · 1 let go"). The model gets at most one line, in words, when there is a streak worth saying ("lately, things she sets out to do have been coming together" / "lately, her plans keep falling through"); never a number.

## Housekeeping

- Every insert stamps `created_at`.
- The card's authored task is not imported when the chat already has an active goal with the same text.
- The two-in-a-row stale counter and its Porch Life picker go away (one `overtaken` answer replaces them); the setting's stored value is ignored.

## Desktop and web

No new screen. The Objectives card (desktop) and the phone's objectives panel show a dormant goal greyed with "set aside", the step list as it now is (rewritten steps, ticks in any order), and the tally line. The Porch Life row loses the "retire after N" picker on both.

## Two pull requests

1. **The engine:** sync (part 1), skip re-plan (2), proposals (3), newborn guard (4), two voices (5), housekeeping, desktop and web display of dormant and the living steps.
2. **The rewards:** mood, diary card, proposal memory, tally (part 6), desktop and web tally line.

Each runs live on the media server before merge.

## Tests

Guards proven red then green, appended to the existing objective test files, plus one journey on a real `ChatService` with a scripted judge: a goal with steps is synced out of order and its next step rewritten; regen puts the old steps back; a two-week skip turns a scene goal `overtaken` and keeps a long want with a new step; a reworded proposal is refused; a newborn goal survives a "done" before its steps exist; the prompt shows the two voices and no dormant goal. The rewards PR adds: achieved → proud with the goal as cause, a stronger mood kept, a diary card that a delete removes, the tally.

## Status

- 2026-10-16: draft from the 2026-10-13 diagnosis and rulings (mood is the reward channel, no bond/trust, no forced cooperation, north star). Awaiting the maintainer's word on the open items below.
- 2026-10-16, rulings: a dormant goal puts nothing in the prompt; a goal won while a stronger feeling stands leaves that feeling (the diary and tally still record the win); the tally reads "3 landed · 1 let go"; two PRs, engine first.
- 2026-10-16, PR 1 (engine) built. Guards proven red then green: both transports refuse a reworded proposal and file nothing at the side-quest cap; open and ended goals ride after the shared judge prefix; a set-aside goal is silent and a card goal is story direction; the web snapshot carries `dormant` and `origin`; a goal finished with steps open counts as a milestone and one let go does not; v58 backfills origin and stamps a real creation time; greeting swipes keep one copy of the card's goal. Journeys on a real `ChatService` against the loopback backend: out-of-order ticks with a rewritten next step, rewound by regen; a set-aside goal woken by regen; a two-week skip forcing a sync past the cadence with "About 2 weeks" in its prompt, and the last-sync stamp surviving a reload. What a sync decides after a skip (overtaken, kept with a new step) and a newborn goal sitting out the sync until its steps exist are pinned at the decision and eligibility level, not in the journey. Live run below.
- 2026-10-16, live runs on the media server (CPU KoboldCpp, Qwen3-4B, Custom backend; a five-turn scene with a character goal, a user goal and "Two weeks later"). Worked as designed: steps ticked out of order, the character's next step rewritten to the scene, the user's steps never reworded, a two-week skip re-planning past the cadence, a reworded proposal and an in-cooldown proposal declined, side goals won, two voices in the prompt. Two decisions changed from what the live runs showed, both pinned red then green: `dormant` now applies only to the character's own goals (the 4B judge set the user's goal aside on the first sync, which muted it), and a next step already on the list is not written (the judge named a step it had just ticked, which duplicated it and told the model to do it again). Seen but left to the model: a 4B judge is generous with ticks and slow to call a goal done after a skip.
- 2026-10-16, PR 2 (rewards) built. Rewards are for the character's own goals only (origin `character`): the user's and the card's goals are story direction, and the planner's day plan already moves the mood through its own path. Achieved → proud (strong for the main goal, moderate otherwise), "pulled off: <goal>"; let go → disappointed, mild, "had to let go of: <goal>"; a mood as strong or stronger stands. With the Journal on, a card in the character's voice cited at the reply. The tally ("3 landed · 1 let go") is cached when the goal list loads and shown on the desktop Objectives card and the phone panel; the model gets one bracketed line in the goals block when the last three ended the same way. In a group, the goal's owner may not be the turn's speaker, so their mood is set on their member record and the old one rides the turn ops (`mood`); a regen or delete puts it back. Guards proven red then green: the reward rules and tally, the streak line's place in the prompt, the web tally only for the loaded character, the phone tally line, and journeys on a real chat service (a win makes them proud with a card and a count; a stronger mood stands; a user goal earns nothing; regen and delete take the card and the count back). The group mood path and its turn-op rewind have no test of their own (there is no group objective harness); only the shared rules under them are pinned.

- 2026-10-19, issue #551 (a character stuck on one goal, replaying the scene while the user steers elsewhere). Two brakes, no new model call. **Fixation brake:** when the character's last three replies all touch a goal (the mention gate's word match) and no user line since touches it, that goal is left out of the prompt, and stays out for three replies after the run ends. It is read from the transcript, so a regen decides the same way; a user line that raises the goal ends it at once. In a group only the owner's replies count. **Stuck-step count:** each task carries `stuckChecks`, the goal checks its open step sat through with nothing ticked and no new step. At three the prompt stops naming the step (the goal line stays) and the goal check is told the step has not moved, so it can write a step that fits (not for the user's or the card's steps). A tick, a rewritten step, or the user editing the step resets it; the count rides the task list, so regen rewinds it with the `tasks_changed` op. Checking every turn would not help: during a fixation the mention gate already fires the check every turn.
