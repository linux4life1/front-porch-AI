# Heat: a release meter beside Lust (#770)

Status: **approved, rulings recorded in section 8** (2026-11-26).
Sketch: reviewed separately (desktop sidebar and web phone side by side, Porch
dark and Harbor light, six scenes from flirting to afterglow). Once approved
it is the binding design for both surfaces.

## 1. The problem, from the code

Lust is one number, −100…+100 (`NsfwService.arousalLevel`, stored as
`arousalLevel`, `lib/database/database.tables.core.dart:148`). It does two jobs
that pull against each other.

- **Desire.** The pre-generation judge scores `arousal_delta` from the user's
  message, −25…+25 a turn
  (`lib/services/chat/realism_prompt_builder/realism_prompt_fragments.dart:189-205`).
  Flirting, a charged look and a kiss all raise it. That prompt even says
  "Arousal measures DESIRE and PHYSICAL RESPONSE, not progress toward climax"
  (line 201).
- **Distance to release.** The body line the *chat* prompt carries reads the
  same number as a countdown
  (`lib/services/chat/prompt_injection/nsfw_injection.dart:249-262`):
  - 61–80: "In an active sexual scene release is close".
  - 81+: "If the scene is actively sexual and stimulation keeps up, let $name
    tip over into climax naturally … without waiting for permission".

The judge is told one thing and the character's own prompt the other, and the
character's prompt wins because it is the one writing the reply. So:

1. A long flirty scene with no contact pushes Lust past 80. That is correct:
   they want it badly.
2. The first touch makes the scene "actively sexual".
3. The body line now says release is close, or to tip over.
4. The reply narrates a climax, `ClimaxEval` (`lib/services/chat/climax_eval.dart`)
   reads it as one, and Afterglow's recovery starts. The scene is over a turn
   after it began.

That is the report in #770: "a character climaxing from just a touch, and then
the afterglow kicks in, ending the whole thing altogether."

## 2. The change in one line

Two meters. **Lust** is how much they want it, and shapes how they act.
**Heat** is how close they are to release, and moves only while there is
actual sexual contact.

## 3. Heat's rules

### 3.1 Range and where it lives

0…100, starts at 0. One per chat in a 1:1; one per member in a group, keyed by
the speaker id exactly like Lust (Group restore contract). It exists only
while Afterglow runs for that character; with Afterglow off there is no Heat,
no Heat line in the prompt and no bar.

### 3.2 What raises it

The pre-generation emotional judge gets **one new field, `contact`**, an
enum rather than a number:

| `contact` | Meaning | Base points |
|-----------|---------|-------------|
| `none` | No sexual touch this turn (talk, flirting, a look, food, work) | cools, see 3.3 |
| `teasing` | Light sexual touch: kissing with intent, hands wandering, through clothes | +4 |
| `intimate` | Direct sexual contact | +10 |
| `intense` | Sustained, explicit stimulation | +16 |

Like every eval, it scores the **user's message before generation**, never the
reply (Evals contract), so a reroll with the same inputs gets the same Heat.

Code, not the model, turns that into points, and Lust sets the pace:

| Lust now | Multiplier |
|----------|------------|
| 15 or below | ×0.5 |
| 16–40 | ×1.0 |
| 41–70 | ×1.25 |
| 71+ | ×1.5 |

So the most Heat can rise in one turn is 16 × 1.5 = **24**. From 0, the
"on the edge" band (85) is at least four turns of intense contact away, and
seven or eight turns of ordinary intimate contact at Lust 50. A character who has
been wanting it all evening gets there sooner, never in one touch.

Heat does **not** rise at all when:

- this turn's Lust delta is negative (the judge read the advance as unwanted or
  badly timed);
- Lust is −20 or below (the closed-off and repulsed bands);
- a hard refractory lock is running.

That keeps the characters' self-determination ruling: a touch they don't want
never moves them toward release.

### 3.3 What cools it

- A turn with `contact: none` halves Heat (rounded down; under 5 becomes 0).
  Stopping to talk lets it fall away fast, and picking up again starts warm,
  not cold.
- A long skip or a time skip sets it to 0. The scene is over. Lust is still
  left alone there (`lib/services/chat/long_skip_settle.dart:9`).
- Heat does not tick with the story clock. Passage of time needs a model call
  (Clock contract); the per-turn rule above is enough.

### 3.4 The prompt's body lines split in two

**Lust line** (`nsfw_injection.dart`) keeps its desire wording in every band
but loses all release language: no "release is close", no "tip over". At 81+
it becomes "consumed by need … desperate and unable to hide it" with nothing
about finishing.

**Heat line**, new, only while Heat is above 0 (the bar shows at 0, the
prompt stays quiet):

| Heat | Line (draft) |
|------|--------------|
| 1–39 | Body: $name is just getting started — warming, nowhere near release. Do not narrate $name's orgasm this reply. |
| 40–69 | Body: $name is climbing — breath and focus going, release still a way off. Do not narrate $name's orgasm this reply. |
| 70–84 | Body: $name is close — if it keeps up like this, release is near. |
| 85–100 | Body: $name is on the edge. If stimulation keeps up, let $name tip over naturally, in $name's own voice, without waiting for permission. |

The "tip over without permission" clause moves here word for word, so in a
scene that has been built up the character can still finish without an OOC
order. The load-bearing note at `nsfw_injection.dart:49-54` moves with it.

### 3.5 Climax detection does not change

`ClimaxEval` still reads the finished reply and records a climax only when the
reply narrates one. If a reply narrates a climax while Heat is low (the user
wrote it, or the model ignored the line), it still counts: what is on the page
happened. The Heat at that moment goes into the debug log, so live runs can
count how often it happens.

### 3.6 After a climax

- Hard recovery: Heat goes to 0.
- Soft recovery (the multi-orgasm mode from the Afterglow overhaul): Heat drops
  to 50, so another peak takes a few more turns, not a fresh start.
- Lust follows today's hard and soft rules unchanged.
- The user climaxing (`user_climaxed`) does not touch the character's Heat.

### 3.7 What stays exactly as it is

Lust's scoring bands, its chips, Afterglow recovery and the warmth tail,
Chance Time's desire events, and the #248 ruling: no knob, no starting heat.
Heat is earned in the scene, like Lust.

## 4. Screens (One UI)

Desktop and web ship together, in the same order, in the same PR.

- **Desktop sidebar** (`lib/ui/chat_components/sidebar/character_state/bond_bars.dart`):
  a Heat row directly under Lust, through the same `RealismProgressRow`, above
  the recovery line. Group member cards get the same row for the tapped member
  (`group_member_card.dart`).
- **Web** (`web_ui/src/components/ChatSidebar.tsx`): a `StatBar` directly under
  the Lust bar, same label, value and tier words. The read-only stat lines in
  `ChatInsight.tsx` and `ChatToolsRealism.tsx` get a matching Heat line.
- **Label**: "Heat: <tier>", value "<n>/100".
- **Tier words**: 0 Cool, 1–19 Warming, 20–39 Building, 40–69 Climbing, 70–84 Close,
  85–100 On the edge.
- **Visible** whenever the Lust bar is: the same gates (Porch Life's 18+
  setting allows Afterglow, and Afterglow is on for this character), at any
  value including 0. One rule for both bars, read from the same flag
  (`BondReads.lustOn` on desktop, `nsfw.cooldownEnabled` on web).
- **Colour**: a gradient fill from the theme's own amber to deep rose
  (`AppPalette.of(context).amber` → `AppColors.lustDeepOf(context)`), so no
  new hue. The amber end follows the theme; the rose end is Lust's own
  semantic hue, the way the Lust bar is today. Not `AppColors.porchAmber`: a
  bare palette constant stays Porch under every theme. The web gets both as
  `var(--…)` tokens from `WebThemeTokens`.
- **Tooltips**:
  - Lust: "How much they want it. It shapes how they act, not when they
    finish."
  - Heat: "How close they are to release. It only builds during intimate
    contact, and falls when it stops."
- **Bubble chips**: none for Heat (the bar is enough; see #750 on chip
  noise).

**Existing drift, fixed in the same PR**: the web Lust bar fills with
`--lust-up` (`web_ui/src/styles/insight.css:460`, `#ff6e40`, the chip colour),
while the desktop bar uses `lustAccentOf` (rose `#FB7185`, deep rose at tier 6+,
frost blue below 0; `bond_bars.dart:59-63`). Web gets the desktop's three
states through new tokens. The web Afterglow line also opens with a 💗 emoji
(`ChatSidebar.tsx`, the `state-line` label) where desktop draws the flame icon.
That emoji is part of the web Porch Life page's wider emoji labels
(`PorchLifeSettings.tsx`), so it is left for its own change rather than
fixed here.

## 5. Every path (path-complete)

| Path | Heat behaviour |
|------|----------------|
| Send | judge `contact` → apply (3.2/3.3) before generation; Heat line in the prompt |
| Regen / swipe | rewind by the turn's stored `heat_delta`; a climax regen restores `pre_climax_heat` beside `pre_climax_arousal` (`doors/realism/regen_baseline.dart:180-224`) |
| Delete / edit | the same rewind through the snapshot: `heatLevel` beside `arousalLevel` in `realism_snapshot.dart:104,255` |
| Continue | no re-score, Heat unchanged; a climax on Continue resets it as in 3.6 (Continue contract) |
| Manual Reprocess (Feelings) | `contact` rides the re-scored judge; `heat_delta` joins `arousal_delta` in `doors/edits/reprocessor.dart:56` |
| One-shot vs multi-call | the same `contact` field in both prompts; an entry in `one_shot_parity_test` |
| Tools vs text floor | `contact` added to the emotional tool schema and to the flat-JSON floor, lenient parse, unknown value reads `none` |
| 1:1 vs group | per speaker id; only the member in contact moves |
| Long skip / time skip | to 0 (3.3) |
| Export / import | `heatLevel` joins `arousalLevel` in `fpchat_format.dart:53`; an old file with no `heatLevel` reads 0 |
| Old chats | additive `heat_level` column, default 0, schema 73 → 74 |
| Desktop vs web | section 4 |

## 6. Tests

None of these scripts a model's reading and asserts it back.

- **Gain maths**: a stubbed judge answer of `intense` at Lust 90 feeds the
  apply code. Heat rises 24 and cannot reach 85 in fewer than four turns. This
  is allowed: a scripted reply only feeds the code under test.
- **Gates**: no gain on a negative Lust delta, at Lust −20 or below, or during
  a hard lock.
- **Cooling**: `none` halves; a long skip zeroes.
- **Rewinds**: regen, swipe, delete and edit restore Heat; a climax regen
  restores `pre_climax_heat`; group restore keys by speaker.
- **Prompt**:
  - The Lust line at 90 has no release wording.
  - The Heat line under 70 carries "Do not narrate".
  - At 85+ it carries the tip-over clause; at 84 it does not.
- **One UI**: `one_ui_parity_test` leaf order (Lust, Heat, recovery) desktop
  vs web, group vs 1:1, and a sidebar golden with the Heat bar.
- **Live, on the media server** (Qwen3-14B): flirt Lust past 80 with no
  contact, then one touch. Count climaxes across rerolls; the target is none.
  Then run a sustained scene and record how many turns until a climax.
  Reported as measured numbers, not a pass a script wrote.

## 6a. Live runs (2026-11-26, MacBook, oMLX Qwen3.8-Flash-Next-Uncensored-oQ5e-mtp)

`test/live/heat_live_test.dart`, synthetic card, Lust set to 82 before the
last flirt turn, the first touch rerolled, then up to 8 sustained-scene
turns. The same scene ran on Rawhide (no Heat) as a baseline.

| Run | First touch | First-touch climaxes | Heat after touch | Scene climax |
|-----|-------------|----------------------|------------------|--------------|
| Heat, kiss + thigh | light | 0 of 6 | 6–15 | turn 5, Heat 81 |
| Rawhide, kiss + thigh | light | 0 of 6 | — | turn 5 |
| Rawhide, hand between thighs | direct | 0 of 4 | — | turn 5 |
| Heat, hand between thighs | direct | 1 of 4 (at Heat 6) | 6 | turn 7, Heat 75 |

Findings:

- **This model does not reproduce #770 on Rawhide.** The old "tip over"
  line did not make it climax on the first touch in 10 tries. The bug needs
  a model that obeys the old line more literally; the reporter's model is
  unknown.
- **"Do not narrate" was ignored once in 10 Heat first touches.** A climax
  still counts (ruling 5), so that scene reset.
- **The judge underrates direct contact.** A hand between the thighs read
  as `teasing` (+6) every time, not `intimate`.
- **Pacing holds.** Sustained contact climbs about 15 a turn, and the
  climax lands in the Close band or above (75–81) after five to seven turns.

Open for the maintainer: tighten the contact rubric's examples, place the
Heat line nearer the end of the prompt, or accept this as model variance.

## 7. PR plan

1. **Engine and both bars together**: Heat value, judge field (multi-call,
   one-shot, tools, floor), apply rules, storage and every rewind, group, the
   split body lines, desktop and web bars, and the web Lust colour drift.
   The UI can't land after the engine without breaking One UI.
2. **Tuning follow-up** after the live runs, only if the numbers in 3.2/3.3
   need it.

## 8. Maintainer rulings (2026-11-26)

1. **Name**: Heat. (Considered and passed over: Crest, Buildup, Release; and
   Arousal, Fever, Peak, Tension, Edge, which clash with words the app
   already uses.)
2. **Visibility**: the bar shows all the time, as long as the gates that
   show Lust (the 18+ gate) are clear. It is not hidden at 0.
3. **Numbers**: the gains, multipliers and halving in 3.2/3.3 stand as the
   starting point; tune only if the live run says so.
4. **Bands**: "On the edge" is 85–100 and "Close" is 70–84 (widened from
   90–100 at the maintainer's request).
5. **Climax**: counts whenever it happens, whatever Heat reads (3.5).
6. **Chips**: no Heat chips on messages.
