# Needs on the clock — statement of work

Version 2, approved 2026-10-06.

Needs keep the Sims loop and get a ruler: the clock wears hunger, bladder and energy at fixed rates per story hour, the judge scores only events, and every line speaks one band quieter than before. With the clock off, nothing changes for the user.

## What changes and what stays

Three things change. The clock wears hunger, bladder and energy by a fixed rate per story hour, instead of the judge guessing a number for the span. The bands move down and the lines get quieter, so a bar at 50 reads as a passing thought, not a demand. The refractory counts story minutes instead of replies.

Everything else stands: seven needs, the per-need switches, Pace as the only speed control, the catastrophe beat at 0, Redo-with-critique, the Director, regen and delete rewinds, Continue extending the same moment, 1:1 and group parity, and the clock-off behaviour (bars move only when the story says so).

Version 1 of this document said there was "no points-per-hour table and no code tick" and that "the wear map stays empty"; version 2 reverses that on purpose, because what that sentence buried was seven per-reply tick sliders plus a strength multiplier, a flat tax on every message, while per-hour wear is zero on a same-moment reply, zero on Continue and zero with the clock off.

## Bands: when a need speaks

Nothing is said above 55. The old top band started at 65 with wording that belonged one band lower, which is why a character at 60 energy read as ready for bed.

| Value | Band | Voice in the prompt | Version 1 |
| --- | --- | --- | --- |
| 56–100 | quiet | no line | line from 65 down |
| 41–55 | mild | a half-clause, marked not urgent; easy to ignore | 46–65 |
| 26–40 | moderate | a mention; the character plans for it or brings it up if it fits | 31–45 |
| 11–25 | strong | changes what the character does this turn | 16–30 |
| 1–10 | crisis | urgent; dominates the turn | 1–15 |
| 0 | empty | the beat (accident, collapse, reek) fires once, then the floor | 0 |

All seven needs inject from the mild band. Version 1 held hunger and bladder back until the moderate band while the other five started at mild; with honest mild wording the split is not needed. Still at most three needs speak per turn, worst first.

Bar colour follows the bands on desktop and phone: amber from 40 down, red from 25 down. Version 1 turned red at 20 and had no amber. The desktop bars and the collapsed group member chips read the two thresholds from the engine (`needUrgentThreshold`, `needCriticalThreshold`); the phone's `needTone` carries the same two numbers.

## Wear: how fast the bars fall

Three needs wear with story time. The other four move only on events, as before.

| Need | Per story hour, day or night | Full to empty | Starting bar reaches mild (55) after |
| --- | --- | --- | --- |
| Hunger | 6 (1 per 10 min) | 16 h 40 min | 3 h 20 min from 75 |
| Bladder | 15 (1 per 4 min) | 6 h 40 min | 1 h 40 min from 80 |
| Energy | 5 (1 per 12 min) | 20 h | 5 h from 80; 9 h from 100 |

- The span is the minutes the clock applied to that reply, the same number the time chip shows. Same moment: nothing. Continue: nothing.
- The rate is the same by day and by night. Nothing in code assumes a night was slept. An all-nighter (gaming till dawn, the overnight shift, a long drive) leaves the wear where it fell, down to the skip floors below.
- Sleep is an event, scored by the judge when the reply shows or implies it: energy +60 to +100 and the morning bathroom, bladder +60 to +100. A nap is +15 to +35.
- Pace scales the wear exactly as it scales a scene drop: Sloth two thirds, Normal as is, Fast four thirds. A plus is never scaled.
- Fractions carry over between replies, so ten 2-minute beats cost hunger 2 points, not 0 and not 10. Each character keeps a small remainder per need in the needs snapshot; regen rewinds it with the bars.
- Wear lands before the judge runs, so the chip can show the time part and the scene part separately.
- A drink is not wear: the judge still scores it as bladder -10.

## Floors, skips and nights

Four rules keep wear from ambushing anyone.

1. **A scene drop cannot empty a bar.** The judge's drop stops at 1.
2. **On-screen wear gives one warning turn.** A beat's wear stops at 1 unless the bar was already in the crisis band (10 or below) when the beat began. So there is always a turn of "fighting to hold on" before the accident, whatever the beat's length.
3. **A skip cannot empty a bar.** Off-screen, people look after themselves. A skip (OOC skip, narrative skip, time away, next morning) wears the span, but bladder never lands below 60, hunger never below 45, energy never below 25. If the story says they could not ("locked in the cellar all day"), the judge drops the bar further, under rule 1.
4. **A night is not assumed.** A skip through the night wears like any other span, down to the floors, so a character who stayed up gaming or worked the overnight shift is at energy 25 at dawn, "worn out", which is the truth. If the reply shows or implies they slept, the judge restores energy and the morning bathroom; the skip beat note asks it that question in so many words. If the model misreads a night, Redo-with-critique corrects it like any other event.

A nap is an event, scored by the judge (energy +15 to +35), not a night.

## The judge: events only

The needs judge keeps its job of reading the reply and reporting what the scene did. It loses the job of guessing how much a span cost.

| | Version 1 | Version 2 |
| --- | --- | --- |
| Beat note | "THIS BEAT lasted 20 min... hunger and bladder must move with that span. You choose the size." | "Time has already been charged for this beat. Score only what the scene did. On a skip through the night: did they sleep? If the scene shows or implies it, restore energy and the morning bathroom; if they stayed up, leave energy where the time left it." |
| Zero rule | "Zero on hunger or bladder is only legal when that need was restored"; all seven zero is a failed eval and triggers a retry | A quiet reply is a legitimate all-zero; no retry. One fewer eval round on local models when nothing happened. |
| Events it scores | the same list | meal +50 to +90, snack ~+15, drink bladder -10, bathroom +60 to +100, shower +50 to +90, nap +15 to +35, sleep +60 to +100, exertion, sex, a mess, closeness; unchanged magnitudes |
| The loop-breaker | describing the current bar is not a new cost | kept word for word |
| Pace | scales its drops | unchanged |
| Director, Redo-with-critique, the away (AFK) prompt | as before | as before; the away prompt's restorative list stays |
| Tools and text transports | shared prompt, one difference in the format lines | unchanged |

The verifier rule that rejects a hunger *gain* when nobody ate stays. The rule that accepted any drop because "the span justified it" goes, since the span is no longer the judge's to charge.

## Wording: the five lines for each need

Each line renders after a header that names the character ("Hunger: ..."), so the lines stay pronoun-free. `{{user}}` is allowed. The mild line always carries its own "not pressing" so a small model does not escalate it. Bladder lines say "a bathroom" and leave the rest to the model, the Sims way: the meter keeps its name, and the accident beat at 0 stays what it is. The five catastrophe beats (the one-time "it is happening" events at 0) are unchanged.

### Hunger

| Band | Line |
| --- | --- |
| 41–55 mild | Could eat. A passing thought of food, nothing pressing; easily set aside. |
| 26–40 moderate | Getting hungry: the stomach starting to feel empty; a meal within the hour would be good, and may say so or suggest food if it fits. |
| 11–25 strong | Properly hungry: a hollow, gnawing stomach that is hard to ignore; a little short-tempered and distracted, actively looking for a chance to eat. |
| 1–10 crisis | Ravenous and shaky: light-headed, hands unsteady, thoughts pulled back to food every few moments; eating has become the priority. |
| 0 | Starving to the point of collapse: grey-faced, vision swimming, knees going. A real physical crisis, not a mood. |

### Bladder

| Band | Line |
| --- | --- |
| 41–55 mild | Could use a bathroom at some point. A faint awareness, nothing pressing; no need to act on it yet. |
| 26–40 moderate | Needs a bathroom before too long: a steady, noticeable pressure; keeping an eye out for a natural moment to slip away. |
| 11–25 strong | Needs a bathroom soon: a strong, insistent pressure that makes it hard to settle; shifting in place and looking for any excuse to go. |
| 1–10 crisis | Desperate for a bathroom: fighting to hold on, thighs pressed together, voice tight; minutes matter and an accident is close. |
| 0 | Control gives out: an accident, right now, in the scene. Hot, unstoppable, and the shame is immediate. |

### Energy

| Band | Line |
| --- | --- |
| 41–55 mild | A little tired. Could do with sitting down for a bit; nothing that changes the moment. |
| 26–40 moderate | Tired: movements a touch slower, less animated than usual; a yawn may slip out, and a rest or an early night sounds good. |
| 11–25 strong | Worn out: heavy limbs, slow thoughts, every task taking effort; openly wanting to lie down and likely to say so. |
| 1–10 crisis | Fighting to stay awake: head nodding, words slow and thick, eyes drifting shut mid-sentence; sleep could take over any moment. |
| 0 | Collapsing from exhaustion: the body simply gives out, eyes fluttering closed, slumping to the floor or into {{user}}'s arms. |

### Social

| Band | Line |
| --- | --- |
| 41–55 mild | A small wish for company. A touch warmer and more attentive than usual; nothing more. |
| 26–40 moderate | Missing real connection: a little keener than usual for conversation or closeness, and inclined to draw it out. |
| 11–25 strong | Lonely: the lack of real connection is starting to hurt; quieter, clingier or more fragile than usual, reaching for meaningful moments. |
| 1–10 crisis | Painfully isolated: hollow and raw, close to breaking down without some genuine connection soon. |
| 0 | Overwhelmed by loneliness: on the edge of breaking down; any real warmth will be clung to. |

### Fun

| Band | Line |
| --- | --- |
| 41–55 mild | A little under-stimulated. Open to something fun or different if it comes up; not bothered otherwise. |
| 26–40 moderate | Getting bored: the current situation feels flat; fidgety, and hoping for a change of pace. |
| 11–25 strong | Thoroughly bored: restless and fidgeting, ready to suggest almost anything to break the monotony. |
| 1–10 crisis | Bored to the point of recklessness: dangerously restless, liable to do something rash or inappropriate just to feel something. |
| 0 | Climbing the walls: unable to sit still another minute; will act out, unwisely, for any kind of stimulation. |

### Hygiene

| Band | Line |
| --- | --- |
| 41–55 mild | A little grubby. Faintly aware of it, not bothered. |
| 26–40 moderate | Starting to feel unkempt: a quiet discomfort, and a wish to freshen up when there is a chance. |
| 11–25 strong | Noticeably dirty and self-conscious about it: thoughts keep returning to a wash or a change of clothes; may hold back from close contact. |
| 1–10 crisis | Genuinely grimy and very aware of it: an urge to cover up or pull away from contact until there is a chance to clean up. |
| 0 | Filthy: the grime or smell strong enough to be distressing; acutely self-conscious, and it stays until a wash. |

### Hygiene, for a character who enjoys low hygiene

The scale is inverted: too clean is the bad state. Scent only, never a drive to get dirty.

| Band | Line |
| --- | --- |
| mild | A faint just-washed freshness. A touch too clean for comfort; barely registers. |
| moderate | A little too clean: the familiar natural scent is thin, and its absence is quietly missed. |
| strong | Uncomfortably fresh: too soft, too soapy; that thorough wash already regretted and the natural musk wished back. |
| crisis | Scrubbed and scentless in a way that feels wrong on the skin: exposed and on edge without the familiar scent. (About missing a natural body scent, never about seeking out filth.) |
| 0 | Stripped of every trace of natural scent: raw, exposed and unsettled; nothing feels right until it returns. (About missing a natural body scent, never about seeking out filth.) |

### Comfort

| Band | Line |
| --- | --- |
| 41–55 mild | Slightly uncomfortable. A minor physical irritation (a stiff neck, a warm room), easily ignored. |
| 26–40 moderate | Uncomfortable: a persistent irritation, whether temperature, pressure or stiffness, that makes it hard to fully relax; may shift position or mention it. |
| 11–25 strong | Clearly uncomfortable: constantly adjusting position or surroundings, unable to settle, and looking to fix whatever is causing it. |
| 1–10 crisis | In real physical distress: too hot, too cold, cramped or aching badly; focus on anything else is a struggle. |
| 0 | Unbearable: impossible to stay like this a moment longer; relief will be sought whatever it disrupts. |

## A day at Normal pace

Default card: hunger 75, bladder 80, energy 80. Clock on. H / B / E are the bars after that row.

| Story time | What happened | H / B / E | What the character says |
| --- | --- | --- | --- |
| 9:00 AM | porch chat starts | 75 / 80 / 80 | nothing |
| 9:15 | coffee (judge: bladder -10) | 73 / 66 / 79 | nothing |
| 10:00 | an hour of talk, five replies | 69 / 55 / 75 | "could use a bathroom at some point" |
| 10:10 | slips away (judge: bladder +70) | 68 / 100 / 74 | nothing |
| 12:30 PM | 2 h 20 min later | 54 / 65 / 62 | "could eat" |
| 12:45 | lunch with a drink (judge: hunger +55, bladder -10) | 100 / 51 / 61 | "could use a bathroom at some point" |
| skip to 6 PM | 5 h 15 min off-screen | 68 / 60 (floor) / 35 | "tired: a rest sounds good" |
| 8:00 PM | 2 h on-screen | 56 / 30 / 25 | "needs a bathroom before too long"; "worn out" |
| 8:10 | bathroom, then dinner (judge: +80, +60) | 100 / 100 / 24 | "worn out, wanting to lie down" |
| 11:00 PM | evening | 83 / 58 / 10 | "fighting to stay awake" |
| next morning, 7 AM | the skip wears to the floors; the reply says she slept (judge: energy +80, morning bathroom +70) | 45 / 100 / 100 | "could eat" and breakfast |
| the other 7 AM | the reply says they gamed till dawn (judge: nothing restored) | 45 / 60 / 25 | "worn out, wanting to lie down"; "could eat" |

Two readings. First, the pull-up is the character acting on the line; nobody has to feed them. Second, energy at 5 per hour runs a long first day because the card starts at 80 rather than 100; from the second day on, bedtime readiness lands around 11 PM. If that first evening reads too tired, energy at 4 per hour is the one number to move.

## Refractory on the clock

The refractory becomes a timer in story minutes. In version 1 it was a count of replies, so a "next morning" skip left a five-turn refractory running through breakfast.

| | Version 1 | Version 2 |
| --- | --- | --- |
| Set at climax | the judge's `refractory_turns`, 3 to 7 | the same answer, 15 min per turn: 45 to 105 min. The tool contract does not change. |
| Ticks | one per reply; in a group only when that character speaks | every clock advance, by its minutes, for every present character at once |
| Same moment, Continue | no tick | no tick |
| Skip, time away, next morning | still counts replies | the whole span; a two-hour skip or a night ends it |
| First afterglow turn (the only one that may force limp, tired body language) | remaining >= total - 1 | a flag set at climax, cleared after the first reply; a same-moment second reply no longer counts as the opening turn |
| Chip | Refractory: 5 turns | Refractory: about 45 min |
| Prompt line | (5 turns left) | (about 45 min left) |
| Arousal physiology while it runs (halved swings, floor at -10) | as now | as now |
| Regen, swipe, delete | rewind the turn count | rewind the minutes the same way |
| Stored | two turn columns | two minute columns added; old turn values read once as turns x 15 |

Clock off: each reply counts as 15 minutes toward the refractory only, so it ends after the same number of replies as before. Chip and prompt then say replies: "Refractory: 3 replies", "(3 replies left)".

## Clock off

With Passage of Time off there is no story time, so nothing wears. This is version 1's behaviour, kept on purpose: the user turned time off, so the body is not on a clock.

| | Clock on | Clock off |
| --- | --- | --- |
| Hunger, bladder, energy | wear with story time, plus events | events only |
| Social, fun, hygiene, comfort | events only | events only |
| Gets hungry, tired or needs a bathroom from time alone | yes, when a person would | never; only if the story says so |
| Hitting 0 | from on-screen hours they could not act on | only if events push a bar there |
| Prompt lines, bands, pace, per-need switches, Redo, Director, regen, delete | all work | all work |
| Chip under the reply | `1 hr 20 min · lunch` | `lunch` only |
| Refractory | story minutes | 15 min per reply |

One line of copy, desktop and phone, under the Needs switch wherever it appears (chat sidebar gear, character editor and creators, an alternate greeting's Needs block, group Needs tab, group creation, Settings → Porch Life), shown only while the clock is off: **"With Passage of time off, needs change only when the story says so."** Without it a user who turns the clock off and sees the bars sit still thinks Needs is broken. "Off" is the Porch Life Passage of Time switch (`passageOfTimeDefault`), the live clock gate; the line shows whether or not that Needs switch is itself on.

## What you will see, and what does not change

On desktop and on the phone, in the same work:

- **Needs chip** under a reply shows the time part and the scene part apart: `1 hr 20 min · lunch: hunger +55, bladder -12`. The chip already has that slot (the reason the chip shows on hover and on tap carries both parts whole); the wear map it reads was empty in version 1.
- **Time chip** unchanged (`12 min`, `1 hr`, `Next morning`, `Time skip: 6:00 PM`).
- **Sidebar bars**: amber from 40 down, red from 25 down, for the solo character and each group member.
- **Refractory chip and sidebar countdown** in minutes (replies when the clock is off).
- **The clock-off line** under the Needs switch.
- **Character editor and group needs tab**: nothing new. Pace stays the only speed control. No rate is exposed; the three rates are engine constants.

Not changing, and pinned by the existing tests: Continue extends the same moment and wears nothing; regen and swipe rewind to the pre-wear stamp and wear the beat once; delete refunds the beat's wear to everyone present; group restore keys by the message speaker; `objectivesActive` and the chaos switch are untouched; evals score the user's message before generation, the needs judge scores the reply after it, both as now.

Groups: time wears every present body; only the speaker's events are scored, as now. A member who was away comes back worn for the away span with the off-screen floors.

## Carried from version 1

- **Per-need switches.** Each character chooses which needs are alive; all seven start on. A need that is off has no bar, no chip and no line in the prompt, does not wear when time passes, ignores a scene number even if the model sends one, and does not collapse when it would have hit empty. The stored number stays; turning it back on shows the same bar. The master needs switch still turns the whole system off.
- **Pace** is a speed control on drops only: Sloth two thirds, Normal unchanged, Fast four thirds. It never changes a plus. The model answers at Normal; code scales every minus, now including the clock's wear, before the result is added to the bar.
- **The time chip** shows the minutes the clock applied on that reply (`12 min`, `1 hr`, `2 hr 30 min`); under a minute, the clock off, Continue, or a reply that does not move the clock: no chip. A skip keeps the **Time skip** chip for where the clock landed, and a jump to the next morning is one chip, `Next morning`. Regen and swipe show the minutes for that swipe; desktop and phone use the same words.

## Decisions (all approved 2026-10-06)

- Reverse the "no points-per-hour table" sentence of version 1; this document is rewritten in the same work.
- Rates: hunger 6, bladder 15, energy 5 per story hour, day or night.
- Bands 0 / 10 / 25 / 40 / 55; all seven needs inject from mild; still three per turn.
- Floors: on-screen wear stops at 1 outside the crisis band; a skip floors at bladder 60, hunger 45, energy 25; a night is not assumed: sleep is an event the judge restores.
- Bladder lines say "a bathroom"; the meter keeps its name; the accident beat stays.
- The wording above, all 40 lines.
- Refractory at 15 min per judge turn; 15 min per reply with the clock off.
- The clock-off copy line, desktop and phone.
- Bar colours amber from 40, red from 25.
- No separate bowels need (#324, #301): the bathroom wording covers it without a whole new needs bar. The chip-abbreviation fix from that PR is welcome as its own PR.

## How each rule gets proven

Every guard is shown red first (the rule removed, the test failing), then green. One independent review per PR.

| Rule | Proof |
| --- | --- |
| Rates, pace, fractions | a pure table test: minutes in, points out, at all three paces; ten 2-minute beats equal one 20-minute beat |
| On-screen stop at 1; crisis band may reach 0 | a bar at 30 and a 3-hour beat lands on 1; a bar at 8 and a 40-minute beat lands on 0 and arms the catastrophe |
| Skip floors and the night rule | a 6-hour skip from 80 / 80 / 80 lands on 45 / 60 / 50; a night skip with no sleep in the reply leaves energy at 25; with sleep narrated, the judge restores energy and the morning bathroom |
| Regen reproduces wear | two regens of the same beat give the same bars; the chip shows the same time part |
| Delete refunds; Continue wears nothing | existing tests extended with a worn beat |
| The judge no longer charges the span | the prompt no longer contains the "zero is only legal" sentence; an all-zero reply applies as zero with no retry; a hunger gain with no meal is still rejected |
| Clock off wears nothing | a pinned test: clock off, three replies, bars unchanged; the copy line is present only then, desktop widget test and a vitest for the phone |
| Refractory | 75 min set at climax; a 20-minute beat leaves 55; a 2-hour skip ends it; clock off, three replies end a 45; the opening-turn flag clears after one reply; regen restores the minutes; old saved turns load as turns x 15 |
| Bands and injection | a bar at 56 injects nothing; 55 injects the mild line; the three-per-turn cap holds |
| Bar colours | widget tests over the desktop bar and the collapsed member chip against the engine's thresholds; vitests over `needTone` and the phone's insight panel |
| 1:1 equals group | the same beat on a solo character and on a group speaker lands on the same bars; a co-present member wears without speaking |
| Phone parity | the journey in `web_ui/e2e/journeys.spec.ts` reads the time-and-scene chip, the minute refractory chip and the clock-off line on phone WebKit and desktop Chromium |

Maintainer poke, with `flutter run`: a clock-on chat for a story day, watch the chips and the sidebar; one "skip to tonight"; one climax then a "next morning"; then the clock off for three replies.
