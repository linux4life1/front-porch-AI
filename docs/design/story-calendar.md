# The Story Clock & Calendar (full time-subsystem rewrite)

**Status:** IMPLEMENTED (2026-07-20, Rawhide) — see "As built" at the end for
the deltas from this sketch.
**Scope:** rewrites the passage-of-time subsystem (`lib/services/chat/time_service.dart`)
around a real datetime clock, adds the calendar surface, and dates the Journal
(`docs/design/journal-memory.md`).
**Maintainer license:** a full rewrite of the time-of-day subsystem is
explicitly approved (conversation 2026-07-20); the `sessions` schema addition
still needs its own sign-off (§5).

## 1. Motivation

Passage of time today is four loosely-coupled scalars: a six-period
`timeOfDay` string, an integer `dayCount`, a `startDayOfWeek` weekday anchor,
and a turn counter. Every behavior — nudges, OOC skips, AFK advancement, the
hold/new_day eval — is a hand-rolled walk over the six-period array, and the
system cannot express dates, durations shorter than "a period", or anything
like "a week later". Characters can remember (via the Journal) how they felt —
never *when*.

The rewrite collapses all of it into one canonical value: **the story clock**,
an actual datetime. Accurate months, days, years, weekdays, and leap years
come from Dart's calendar for free; every current behavior becomes a
one-line clock mutation; and the Journal, the prompt, and a new calendar UI
all get real dates and times of day.

## 2. The new model

### Canonical state (TimeService, rewritten)

```dart
DateTime _clock;          // the story's current moment (UTC, minute granularity)
DateTime _startDate;      // Day 1's date (date-only, UTC midnight)
bool _passageOfTimeEnabled;
int  _turnsSinceClockMoved;   // stall backstop only — the 6-turn pacing gate is gone (§2)
```

### Everything else is derived (nothing else is stored in memory)

```dart
String get timeOfDay;        // dawn/morning/late_morning/afternoon/evening/night, from _clock.hour
int    get dayCount;         // _clock.date − _startDate + 1  (Day 1-based, as today)
String get narrativeWeekday; // weekday(_clock) — the modulo-7 math dies
DateTime get storyDate;      // date part of _clock
String get displayClock;     // "9:40 AM"
String get displayDate;      // "Tuesday, March 3rd" (+ ", 1887" when ≠ current real year) — intl
```

Period boundaries (hour → period) and the reverse map (period → representative
time, used when seeding from legacy period-only data):

| period       | hours   | representative |
|--------------|---------|----------------|
| dawn         | 05–08   | 06:00          |
| morning      | 08–11   | 09:00          |
| late_morning | 11–13   | 11:30          |
| afternoon    | 13–17   | 14:30          |
| evening      | 17–21   | 18:30          |
| night        | 21–05   | 22:30          |

All boundary/representative constants and pure conversions live in one new
pure leaf, **`chat/story_clock.dart`** (no I/O, fully unit-testable — the
subsystem's `journal_physics.dart` analog). TimeService keeps ownership,
orchestration, and the callbacks; the math lives in the leaf.

### Behaviors, rewritten as clock mutations

Every hand-rolled six-element array walk in the current service (nudge,
advanceTimePeriods, OOC skip, hold-eval rollover — four separate copies)
reduces to `_clock = _clock.add(...)` / snap-to-period helpers in the leaf:

- **Continuous per-turn time (the 6-turn gate and the veto die):** with a
  real clock, "time is frozen for six turns, then lurches a whole period
  unless the LLM vetoes" is backwards — the AI should report how much time
  each exchange took, every turn. Crucially this costs **zero extra LLM
  calls**: the scene-time eval already fires every turn today (the
  "not-yet-eligible" branch runs a posture-only call each turn, and in
  one-shot mode posture rides the fused JSON each turn) — the gate was
  never saving a call, only withholding the time question from it. The
  per-turn schema (flat, no grammar — the GBNF gotcha stands):
  `{"minutes_elapsed": 0–180, "new_day": bool, "posture": "..."}`.
  - `minutes_elapsed: 0` is legitimate (mid-fight slow-motion — the old
    "hold", now expressible per turn instead of once per six).
  - **Clamped hard** to [0, 180] per turn — the LLM paces scenes, it never
    teleports the timeline. Bigger jumps belong to `new_day` (→ 08:00 next
    day, valid from evening onward as today) and the OOC skip detector.
  - **Deterministic floor:** eval failure/absence/tool-less garbage →
    +5 minutes (a typical exchange), so a flaky local model degrades to
    gentle real-time drift, never a freeze.
  - **Stall backstop:** `_turnsSinceClockMoved ≥ 12` forces a snap to the
    next period's representative time — preserving the old system's one
    real guarantee ("time can never freeze forever") without its gate.
  - Retired with the gate: `turnsPerTimePeriod`, `hold_time`, the
    eligible/not-eligible/passage-disabled triple prompt branching in
    `evaluateTimeProgressAndPostureIfNeeded` (three prompt variants
    collapse into one per-turn prompt; passage-disabled keeps a
    posture-only variant).
  - **Pacing character changes, deliberately:** instead of frozen-then-lurch,
    the clock creeps naturally (a chatty hour is an hour; a terse scene
    barely moves). This is the accuracy the calendar promises, and the
    per-message chips + time strip make it visible and auditable. Manual
    chevrons and OOC skips remain the user's override at all times.
- **Nudge chevrons (±1):** snap to the previous/next period's representative
  time; day rollover falls out of the datetime math instead of the manual
  wrap. Same last-message `realism_state` patch callback for swipe survival.
- **OOC time-skip detector (kept, upgraded):** the detector stays and still
  fires on *both* trigger styles it recognizes today — explicit OOC markers
  ("(OOC: skip ahead)") **and** in-narrative skip phrasing with no marker at
  all ("we drive for several hours", "a few hours later", "the next
  morning…"). What changes is the payload: instead of counting fuzzy
  periods, the same vocabulary maps to real durations — "an hour" +60 min,
  "a few hours" +120, "several hours" +180, "next morning" → next day
  08:00 — and grows the cases the old model could not express: "a week
  later" +7 days, "next month" → the 1st of the following month ("that
  winter…" parked as a future nicety). Same `passageOfTimeEnabled` gate,
  same pending-metadata chip, which now names the destination
  ("Skipped to Mon, Mar 9 · 2:40 PM" instead of "Skipped to Afternoon").
- **AFK idle mode:** `advanceTimePeriods(count)` becomes count
  snap-to-next-period steps — identical observable result.
- **One-shot parity (contract upheld):** the fused one-shot JSON carries the
  same per-turn `minutes_elapsed`/`new_day` fields the dedicated eval does;
  both paths apply the same clamp, floor, and backstop to the same clock.
  Parity holds because there is only one clock and one mutation site — and
  the rewrite actually *simplifies* the one-shot contract, since the old
  "one-shot must remember to tick the gate counter" trap (which once shipped
  as frozen-time) no longer exists.

### Explicitly out of scope

Needs decay, mood decay, and the long-term relationship counters stay
**turn-based**. Driving simulation decay off elapsed story time is a
tempting sequel but a behavioral change to the Realism/Needs parity surface —
its own proposal if ever.

## 3. Compatibility: the wire formats keep speaking period + day

`timeOfDay`/`dayCount` are not private state — they are interchange contracts.
The rewrite treats each as *written-derived, read-as-seed*:

| Surface | Written as | Read as |
|---|---|---|
| `Sessions.timeOfDay/dayCount/startDayOfWeek` | derived from the clock on every save (Card Forge + rollback keep working) | legacy seed when `storyClock` is null |
| `Sessions.storyClock`, `Sessions.storyStartDate` (new, §5) | canonical ISO-8601 | canonical |
| `realism_state` message snapshots | legacy keys **and** additive `storyClock`/`storyStartDate` | prefer new keys; synthesize from legacy (swipe/regen/convert on old chats) |
| Group realism blobs (`group_realism_blobs.dart`) | same additive-keys pattern | same |
| V2 card extensions (`day_count`, `time_of_day` — travels via The Stoop) | keep both, add `story_clock`/`story_start_date` | prefer new; old cards seed via synthesis |
| Web facade (`chat_tools_facade.dart`) | existing fields unchanged + additive `clock`, `storyDate`, `storyStartDate` | n/a |
| Seeding editors (§3a) | keep their period+day pickers, now writing through synthesis; gain the calendar block | n/a |

### 3a. Seeding: creators, editors, and cards (first-class, same PR)

Every place a character's *starting* time state is authored gets the
calendar. The lucky break: they all already share **one widget** —
`RealismFormSection` (`lib/ui/widgets/realism_form_section.dart`) is the
form used by the manual creator (`create_character_page.dart`), the AI
creator's Realism step (`character_creator/steps/realism_step.dart` +
`creator_state_engine.dart`), and the edit-character page — so the calendar
plugs in at one widget plus the card model, not five screens.

The form's time block becomes:

- **"Story begins…"** — two modes: *"the day the chat starts"* (default —
  what every existing card implicitly means; the date anchors to the real
  world when a chat begins) or *a fixed date* (date picker, any year — a
  card set in "London, June 1888" carries its own era).
- **Starting time of day** — the existing six-period dropdown stays as the
  friendly picker, with an optional exact clock time for authors who care
  ("the story opens at 11:47 PM"). Period-only input seeds the
  representative time via the §3 synthesis — no author is forced to think
  in minutes.
- **Starting day** — the existing Day counter stays (Day 3 of a fixed-date
  story means startDate + 2, exactly as you'd expect).

`CharacterCard` gains the additive extension fields (`story_start_date`,
`story_clock`) alongside the kept `day_count`/`time_of_day`, so authored
cards round-trip through export/import/The Stoop; old apps reading a new
card simply ignore the new keys and still get the period+day it also
carries. The group surfaces (`create_group_chat_page.dart`,
`group_realism_dynamics_editor.dart` — where scene time is authored
group-wide — and the per-member expanders via `group_member_realism_editor`)
get the same block; per-member editors keep only what is per-member
(time stays chat-scoped, so the calendar block lives at the group level).
The speaker-objective external seeding path (`chat_service_speaker_objectives.dart`)
keeps its whitelisted `timeOfDay`/`dayCount` fields, additively accepting
the new keys.

After creation, the same authored values remain editable per-chat in the
calendar dialog's gear (§6) — creator sets the default, the chat can always
override.

**One synthesis function** (in `story_clock.dart`) covers every legacy read:

```dart
StoryClockState fromLegacy({timeOfDay, dayCount, startDayOfWeek})
// clock = anchorDate + (dayCount−1) days, at timeOfDay's representative time
// anchorDate chosen so Day dayCount falls on today, slid 0–6 days back so
// weekday(anchor) honors a set startDayOfWeek — the visible "Tue · Day 5"
// never jumps across the upgrade; it just gains "Mar 3, 9:40 AM".
```

This is the successor to `resolveStartDayOfWeek`'s legacy-row trick, applied
once, in one place, instead of per-consumer.

### User override (the period-roleplay door)

The calendar UI lets the user set the story's start date to anything — 1887,
2187 — and set the current clock directly. Re-anchoring shifts `_startDate`
and `_clock` together (elapsed days preserved); setting the clock inside the
current day is just a set. Weekdays and month lengths follow the real
(proleptic) Gregorian calendar at any year.

## 4. Journal linkage — memories that know *when*

Deterministic stamping, no LLM, no new pass — same philosophy as emotion
stamping. When the maintenance pass creates a card it writes the
`JournalMemories.metadata` pouch (reserved for exactly this; **zero journal
migration**):

```json
{ "storyDay": 5, "storyClock": "2026-03-03T21:40" }
```

`storyDay` comes from the cited source messages: their `realism_state`
snapshots already carry the time state at writing (modal `dayCount` among
cited positions; fallback: pass-time value). The full timestamp means a
memory knows it happened *at night* — "that night on the pier" — not just on
Day 5. Displayed dates re-derive live from `storyDay` + the anchor, so a
later anchor edit retro-dates every memory consistently.

- **Injection suffix** (words-only, per the prompt-state-injection doctrine):
  `- I still think about the pier. (felt: warm · Day 5, last Tuesday night — 9 days ago)`
  Unstamped (pre-feature) cards render exactly as today.
- **Diary UI:** cards grouped under date headers ("Day 5 — Tuesday, March
  3rd"); sidebar peek shows the compact form. Unstamped cards group under
  "Before the calendar".
- Invariants untouched: cards stay session-scoped; no-RAG floor unaffected;
  revisions keep their stamp (a reworked memory still happened when it
  happened).

## 5. Persistence & migration

Two additive, nullable TEXT columns on `Sessions`:

```dart
TextColumn get storyClock => text().nullable()();      // ISO-8601 datetime
TextColumn get storyStartDate => text().nullable()();  // ISO-8601 date
```

> ⚠️ **Maintainer approval required before implementation.** `sessions` is
> written directly by Character Card Forge with raw SQL. Nullable additive
> columns are the safest shape, but a raw `INSERT` that does not name its
> columns would still break — needs a check of how Card Forge writes.

`startDayOfWeek` logic (`resolveStartDayOfWeek`,
`ensureStartDayOfWeekAnchored`, both modulo-7 weekday computations) is
**deleted**; the column remains, written as `weekday(storyStartDate)` so any
external reader sees consistent values. Migration is lazy — no data
rewrite; legacy rows synthesize on first load and persist the canonical
columns on first save.

## 6. The calendar surface

**Desktop:** `TimeStrip` (still the ONE scene-time widget) shows
`🌙 9:40 PM · Tue, Mar 3 · Day 5` with the existing chevrons and period dots
(dots derive from the period as before). Tapping the date opens the
**calendar dialog** (AppColors + porch amber; not a wizard — the
step-indicator rule doesn't apply):

- month grid, current story date highlighted (amber fill, `onChaosAccent` ink),
- a dot on each day holding journal memories for the focused participant
  (one `cardsFor` read on open — cards are capped, in-memory grouping;
  async, never in `build`),
- tap a marked day → that day's memories (diary dialog, pre-filtered),
- gear → "story begins on…" date picker, "set current date & time" picker,
  and the relocated passage-of-time toggle — one coherent time-settings spot,
- month/year chevrons; days outside [Day 1, today] dimmed.

**Web/mobile (`web_ui/`) — same body of work, not a follow-up.** Facade
fields per §3; journal payloads additively carry the stamp; the web UI ships
the same calendar with distinct phone (full-screen sheet) and desktop
(dialog) presentations per the layout addendum.

## 7. Prompt changes

`TimeInjection` becomes:

```
It is 9:40 at night on Tuesday, March 3rd (day 5 of the story).
```

Clock digits and the day digit are normal fiction (the doctrine's meter ban
is about stats, not dates); the year appears only when it isn't the current
real-world year. `buildTimeInjection` inside TimeService (the "thin wrapper"
duplicate of TimeInjection) is deleted in the same pass — one builder.

## 8. Contracts honored

- **1:1 ↔ group parity:** time stays chat-scoped — one clock per chat, same
  load/save/capture sites. No `_groupRealism` involvement.
- **One-shot vs normal:** identical fields, one clock, one mutation site (§2).
- **Cross-platform:** pure `DateTime.utc` math (DST-proof) + `intl`
  formatting — no paths, no processes, no natives.
- **Local-model floor:** flat JSON / single tool call, stop-sequences + regex,
  no grammar; deterministic fallback advances on any eval failure so time
  never freezes (as today).

## 9. Implementation shape

1. **Core rewrite:** `chat/story_clock.dart` (pure leaf: conversions,
   synthesis, formatting) + TimeService rewritten around `_clock`/`_startDate`
   (nudge/OOC/AFK/eval collapse onto the leaf; deleted outright: the four
   period-array walks, both weekday computations, `resolveStartDayOfWeek`,
   `ensureStartDayOfWeekAnchored`, TimeService's duplicate
   `buildTimeInjection`, the 6-turn gate (`turnsPerTimePeriod`), `hold_time`,
   and the triple prompt branching in
   `evaluateTimeProgressAndPostureIfNeeded`). Per-turn eval schema with
   parity across one-shot. Sessions columns (post-approval) + every wire
   format in §3. Unit tests target the leaf
   (boundary/rollover/leap-year/synthesis) and the service (clamp, floor,
   stall backstop, restore paths).
2. **Journal stamping** (§4): pass writes the pouch; injection suffix;
   diary/panel date groups.
3. **Calendar UI** desktop + **web parity** (§6).
4. **Docs:** this file graduates to as-built; `docs/Rawhide.md` gets the
   user-facing bullet ("📅 A real calendar and clock — your story has actual
   dates now, and characters remember *when* things happened").

Phases 1–2 are one PR (the rewrite plus its first consumer proves the
stamping path); phase 3 may follow immediately after in the same effort.

## 10. Open questions for the maintainer

1. **Sessions columns approval** (§5) — the hard gate.
2. **Continuous per-turn time** (§2): the 6-turn gate + veto are retired in
   favor of per-turn `minutes_elapsed` riding the eval that already fires
   every turn (zero extra calls; clamp + floor + stall backstop as
   guardrails). This deliberately changes the pacing *feel* from
   frozen-then-lurch to a naturally creeping clock — approved per the
   maintainer's 2026-07-20 direction, noted here since it is the one
   observable-behavior change in the rewrite. Tuning knobs (per-turn clamp
   180, floor 5, backstop 12) are constants in `story_clock.dart`.
3. Clock digits in the injection (§7) — recommended yes; confirm.
4. Group calendar dots: focused participant only (matches the journal
   panel — recommended) or union of all members?
5. OOC week/month vocabulary in the same PR (recommended) or parked?

## 11. As built (2026-07-20)

Everything above shipped as designed, with these deltas:

- **Card extension field:** the exact opening time ships as
  `story_start_time` ("HH:MM"), not a full `story_clock` datetime — a card
  seeds *relative* time (Day N + clock time), and a full datetime would have
  fought `day_count`. `story_start_date` is as designed.
- **Diary date headers (§4):** the diary dialog KEEPS its category grouping
  (About-you / About-us / Moments / Promises are meaningful) and instead
  stamps each card with "Day 5 · Tue, Mar 3" on its feeling line; the
  **calendar dialog is the date-grouped view** (tap a day → that day's
  memories). Two groupings, each on the surface where it reads best.
- **Passage-of-time toggle:** stays in Character State settings — the
  calendar gear carries only "story begins on…" and "set date & time"
  (relocating the toggle would have duplicated a control for no UX gain).
- **Group creation wizard:** initially shipped without the calendar block
  because the group creator's scene-time seed had **no runtime application
  path** to the chat-scoped clock (editor-carried state only — a
  pre-existing latent gap). **Fixed in the follow-up commit:** group-wide
  time now lives as canonical TOP-LEVEL keys on `defaultMemberRealismState`
  (`timeOfDay`/`dayCount`/`storyStartDate`/`storyStartTime` — adopting the
  spot the group settings dialog already wrote), `parseGroupTimeSeed` reads
  them (falling back to the per-member baseline copy, so pre-fix groups'
  authored time finally applies too), and both fresh-group paths
  (`_loadLastSession` 0-session + `startNewChat` group branch) seed the
  clock through the same `seedFromV2OrExt` the 1:1 card path uses. The
  authoring UI is one shared widget — `StoryBeginsRow`
  (`ui/widgets/story_begins_row.dart`), extracted from RealismFormSection's
  private row — used by the 1:1 form, the group creation wizard's global
  scene time, the group dynamics editor, and the group settings dialog.
  Per-member baseline time copies keep being written for older apps reading
  exported group cards. (The web group creator is a minimal name+members
  flow with no realism seeding step at all, so no web change — web groups
  author dates via the calendar modal.)
- **Web parity:** `GET /api/chat/tools/calendar` (owner-scoped day/card
  payload), additive `time.{clock,date,dateLong,storyClock,storyStartDate}`
  fields, `POST /api/chat/tools/time` additive `{setClock}`/`{setStartDate}`
  forms, and `StoryCalendarModal.tsx` (phone: full-screen via the shared
  `[data-layout="phone"]` override). Journal memory *cards* themselves
  remain desktop-only outside the calendar view — the web diary is a
  pre-existing gap owned by the journal effort, not widened here.
- **Open questions 2-5** resolved as recommended (continuous per-turn time;
  clock digits in the injection; focused-participant dots; week/month OOC
  vocabulary shipped).
