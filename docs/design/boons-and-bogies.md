# Boons & Bogies — character traits that grow (design)

Status: **design v2 amended 2026-11-21 — shipped through phase 3 (PR #762,
Rawhide): schema v68–v69, PressureRoll
physics, ladders, Master guard, undo, Porch Life switches, the Growth panel
sections (PR #754), and the card `traitKit` — kit editors on both surfaces,
seed-on-first-touch with the retroactive offer (ruling 13), Stoop display.**
Phase 4+ (overcome milestone UX polish, the `linkedTo` link UI) remain.
Ruling 18 (three-layer participation) and the §3 absence amendment are law
for phases 4–5.
v1 (2026-11-19) proposed
the feature; a maintainer interview on 2026-11-20 replaced its approval model,
its advancement physics and its rollout. Every "today" claim below names the
file it was read from, at `ba5b37a2f`.

## 0. Rulings (locked — do not relitigate)

1. **Approval.** New boons, new bogies, a trait reaching Master, and a bogey
   being overcome always go through a milestone. Reaching Skilled does not —
   it is a chip with Undo. Ordinary rings keep following `growthReviewFirst`.
2. **Tier names:** Novice / Skilled / Master. The physics tiers underneath
   (emerging / developing / established) are unchanged.
3. **Roll numbers:** base 3, growth 4 (jittered 2–6), cooldown 2 (jittered
   1–3), chance ceiling 45%, one roll per reply. The median gap is pinned to
   7–9 replies by a simulation test, not by hope. Separate from Porch Life
   Chaos frequency.
4. **Default:** Boons & Bogies ships **off**.
5. **Heavy scenes:** a bogey that would fire during a heavy scene is held —
   the roll is skipped and pressure keeps its value.
6. **Growth doc:** `docs/design/growth-rings.md` stays deleted. This doc is the
   Growth reference; phase 0 repoints the code comments here.
7. **Flaw changes are silent.** The growth pass may make a bogey worse or
   better without a popup. Every change stores the previous strength, advance
   count and text; Undo is available from the reply chip and from the trait's
   panel row, any time, across restarts.
8. **Master always asks.** Silent changes stop one step below Master. A trait
   going permanent is a milestone with Accept / Reject. A boon Master is
   confetti; a bogey Master is the permanence question. Master is also
   **never seeded**: a card kit tops out at Skilled (amended 2026-11-21 —
   the editor once offered an "established" seed, which read as seeding a
   Master and is withdrawn; see §4).
9. **Popup budget.** At most one milestone per 8 user messages. Anything over
   budget lands unread in the **Moments** list in the Growth panel and can be
   replayed, celebration included. Nothing is lost.
10. **Ladders.** Boons advance on growth passes where the story used them
    (3 → Skilled, 8 → Master). Bogies advance on times they actually fired
    (4 → Skilled, 12 → Master). Ordinary traits, stances, habits and scars keep
    today's physics untouched.
11. **Card budget.** A card carries at most 6 boons and bogies combined. Card
    bogies share the 3-bogey limit, so a card with 3 flaws leaves no room for
    the model to add one. Card entries use a separate budget from the 12 story
    rings.
12. **Rollout.** v1 is the working loop with a static celebration. v2 is the
    deterministic particle sim and the boon link. No phase ships half a
    surface.
13. **Existing chats.** Turning the feature on offers the card's kit once,
    naming the whole cast. Decline changes nothing; the offer can be re-run
    from the panel.
14. **Stoop.** A flaw that is bigotry, a slur, or a stereotype of a real group
    is rejected. Flaws are personal, not demographic.
15. **Redo is cut from v1.** The milestone is Accept / Reject. Reject drops
    the proposal; the next growth pass may propose a different one.
16. **Chance Time wins a turn.** If a Chance Time event fires, the bogey roll
    is skipped and pressure holds. Two loud instructions in one prompt make a
    local model do the loud one.
17. **Roll state lives in columns, not ring metadata.** Pressure, cooldown,
    pending injection, delivered flag, advance count and the Master-declined
    latch are `growth_rings` columns (v68). Metadata holds only the undo
    snapshot, written by the same applier that writes content.
18. **Participation has three layers.** Boons & Bogies follow the
    realism/needs pattern: a global kill switch (Porch Life), a
    character-editor default that new chats inherit, and a per-member
    sidebar toggle for mid-chat opt-out. An opted-out member's existing
    rings freeze — visible, injectable, but no fade, no advance, no
    rolls, no proposals; off never deletes. Phase 4's roll wiring is
    born owner-aware. The participation UI ships with the next PR that
    touches the Porch Life or group-sidebar surfaces on both stacks;
    it does not wait for phase 5. (Migrated from issue #765, 2026-11-21.)

## 1. Pitch

A character carries **boons** (abilities that get better: a ninja's stealth)
and **bogies** (flaws that show up now and then: the same ninja is clumsy).
Boons climb tiers as the story earns them. Bogies fire on a pressure roll —
never every turn, never twice in a row, and guaranteed eventually while
staying unpredictable when. The payoff loop is the two touching: a boon growing
can wear a bogey down until the character overcomes it. When any of that
happens, a center-screen moment (confetti for a boon, purple smoke for a bogey)
lets the user accept or reject it.

Card authors pre-seed a kit; the model proposes new boons and bogies as the
story goes.

## 2. What exists today (read from the code, 2026-11-20 @ `ba5b37a2f`)

| Piece | Where | What it already does |
|---|---|---|
| Growth ring | `lib/database/database.tables.features.dart:190` (`GrowthRings`) | Per-chat, per-character row: `category`, `strength` 0..1, `pinned`, `retired`, receipt positions, `metadata` JSON pouch. Rings never cross chats and die with the chat. |
| Tiers + physics | `lib/services/chat/growth_physics.dart` | New ring 0.30; reinforce +0.20; fade −0.05/pass; developing ≥ 0.35; established ≥ 0.80 (permanent). Cap: 12 active rings per owner; `capVictim` skips pinned and established, and the cap *yields* when every ring is protected. Max 2 new rings per pass. "LLM proposes, code disposes." |
| Growth pass | `lib/services/chat/growth_service.dart`, `growth_prompt.dart`, `growth_ops.dart` | Own background job with its own cursor; every 5 user messages by default (`memory_settings.dart:55`) or on a salience kick. The **growth prompt sees every active ring** (`growth_service.dart:226` → `growth_prompt.dart:84-95`). |
| Chat injection | `growth_service.dart:239-240` | The reply prompt sees `GrowthPhysics.injectionSelection`: top 8 rings, 2 slots reserved for non-established. This is the only place the chat model learns a ring exists. |
| Review + the one applier | `lib/services/chat/growth_review.dart` | Every op becomes a `GrowthProposedOp`; `applyOwnerProposals` is the single write path. `growthReviewFirst` (default off, `memory_settings.dart:56`) parks the batch. A parked batch is one `cursorTarget`, all-or-nothing, in-memory, replaced by the next park. |
| Pressure roll | `lib/services/chat/chaos_mode_service.dart:262` (`checkAndTickChaosPressure`), `:316` (`checkAndTickMember`) | Pressure grows each turn; chance = base + pressure; a hit zeroes pressure and starts a cooldown. Group twin reads/mutates only the speaking member's bag. |
| Chaos frequency | `lib/services/chat/chaos/chaos_frequency.dart:23-25` | Rare 2/2/4, Normal 5/5/2, Wild 10/10/0, described in the UI as roughly one event every twelve / six or seven / three messages. |
| Runtime state precedent | `lib/database/database.tables.core.dart` (`sessions`), `group_member_realism.dart` | 1:1 gauges are `sessions` columns (`chaosPressure`, `pockets`, …); group members carry theirs in `group_realism_state`. Pockets exists because 1:1 once had no home for its record and reopened empty. |
| Emotional judge | `lib/services/chat/realism_prompt_builder/realism_prompt_fragments.dart:151` | Emits `emotion_intensity: mild / moderate / strong`. One-shot mode returns before the three judges (`realism_judges.dart`); Continue never runs pre-gen judges. |
| Card identity fields | `lib/models/character/front_porch_extensions.dart:96,127` | `ambitions`, `likes`, `dislikes` travel with the card. A new field has the same fan-out — `ambitions` appears in 137 files across `lib/`, `web_ui/`, `test/` — plus a `group-card-field-manifest.json` entry. |
| Flame | `pubspec.yaml:101` (`flame: ^1.38.2`), `lib/ui/chat_components/ambient/ambient_stage_game.dart` | Drives the ambient weather stage; reduce-motion is already read in `ambient_stage_mount.dart`. |
| Porch Life dependencies | `lib/ui/settings/widgets/feature_tree.dart:29` (`FeatureNeed`), `lib/ui/settings/tabs/porch_life_memory_group.dart:170` | `FeatureRow` carries `need`, `dependsOn`, a dependency badge and jump-to. Growth Rings is `memory.characterEvolutionEnabled`. |
| Web surface | `web_ui/`, `docs/design/settings-parity-manifest.json` | Every settings control and chat surface has a web twin; parity is test-guarded. |
| Schema | `lib/database/database.dart:286` | `schemaVersion` 67. New columns land as v68. |

**Note:** `docs/design/growth-rings.md` was deleted in `dc473cf66` and is still
cited by 19 comments in 18 files, several with section numbers (§4.2–§4.4) that
no longer exist anywhere. Per ruling 6 it stays deleted: the table above is the
Growth reference, and phase 0 repoints those comments to this doc without
section numbers.

## 3. The model

### 3.1 Kinds

- **Boon** — a `skill` ring tagged `bb.kind = boon`. Shown as "Boon" in the UI.
  It keeps the `skill` category but gets the boon ladder (§3.2) instead of the
  ordinary one. The v1 doc's claim "no new physics" was what produced Master
  after three uses; it is withdrawn.
- **Bogey** — a **new** model-writable category `bogey`. Not `scar`: a scar is
  something that happened to the character; a bogey is a recurring flaw that
  fires on a roll.

### 3.2 Advancement ladders

Ordinary rings (trait / stance / habit / scar) are untouched: 0.30 birth,
+0.20 per reinforce, −0.05 per unreinforced pass, 0.35 / 0.80 thresholds.

**Boon.** Two conditions, both required, so the model noticing a skill is not
enough — the story has to use it.

| Tier | Needs | Realistic time |
|---|---|---|
| Novice | born at 0.30 | — |
| Skilled | 3 growth passes where it was used **and** strength ≥ 0.50 | ~20–30 messages of real use |
| Master | 8 such passes **and** strength ≥ 0.90 | ~50–80 messages |

The advance count increments **at most once per ring per growth pass** (a pass
that reinforces the same boon twice counts once). Fade still applies: an unused
boon loses strength and can drop back to Novice — a chip, not a milestone.

**Bogey.** The evidence is the roll itself, not the model's opinion.

| Tier | Needs |
|---|---|
| Novice | born |
| Skilled | 4 times it actually fired |
| Master | 12 times it actually fired (~85 replies at the target rate) |

A fire increments the count; a growth pass where the story shows the character
coping decrements it by 1 (floor 0). A bogey's `strength` is kept equal to
`0.30 + 0.05 × count` (clamped 0.30..0.90) so existing sorting and injection
code keeps working, but its tier is derived from the count. The growth prompt
is told never to reinforce a bogey for merely appearing; only the story making
it worse, and the roll does that.

**Absence is not coping** (amended 2026-11-21, from issue #764): the Growth
pass records a third per-ring outcome, `not offered`, alongside reinforced
and coped-against. A ring the scene never had a surface to touch gets
neither fade nor advance; charging silence as recovery is how a bar-bound
flaw withers when the story leaves the bar. Roll injection already knows
what a scene contains — the verdict must record what it implicitly reads.

**Master.** Reaching Master always produces a milestone. On Accept the trait
becomes permanent. On Reject `master_declined` latches: a boon is never
re-proposed; a bogey can be re-proposed only after its count falls below 4 and
climbs back to 12. No nagging every pass.

**Overcome.** An accepted proposal retires the bogey regardless of count and
regardless of tier. This is the one deliberate exception to "pinned rings are
never AI-retired" (`ed7683bcc`): pinned means no *silent* retirement, and this
path always asks. The exception gets its own test.

### 3.3 Where state lives

Six additive columns on `growth_rings` (schema v68):

| Column | Used by | Written |
|---|---|---|
| `advance_count` | boon scenes / bogey fires | applier (boon), roll (bogey) |
| `bogey_pressure` | 0..100 gauge | roll |
| `bogey_cooldown` | replies left | roll |
| `bogey_pending` | the injected sentence | roll |
| `bogey_delivered` | regen/swipe re-inject | injection builder |
| `master_declined` | no-nag latch | applier |

`metadata.bb` holds only the undo snapshot and the seed/link identity:

```json
{
  "bb": {
    "kind": "boon|bogey",
    "seeded": true,
    "linkedBoon": "<ring id>",
    "undo": { "strength": 0.50, "advance": 3, "text": "…", "at": 0 }
  }
}
```

Undo is one step per ring, not a history stack: it restores strength, advance
count and text together, then clears itself. It is written inside
`applyOwnerProposals`, so the one-write-path invariant still holds for content.

Why columns and not the group bag: the bag exists only for groups; 1:1 gauges
live on `sessions`, and choosing the bag would mean two implementations and
inherit the Pockets bug class. Rings are already keyed
`(session_id, character_id)`, so columns are one path for both.

### 3.4 What the two prompts see

- **Growth prompt:** every active ring, including bogeys. This is what lets the
  model fade a flaw when the story shows coping, and propose overcoming it.
- **Chat injection:** `injectionSelection` with bogeys filtered out. A bogey
  reaches the reply prompt only on the turn the roll injects it. Without this
  filter, "Lately, Mira is clumsy" sits in context every reply and the roll is
  theatre.

## 4. Pre-seeding from the card

- New card field `traitKit` on `FrontPorchExtensions`:
  `[{kind: boon|bogey, text, tier: emerging|developing, pinned, linkedTo?}]`.
  Identity, like `ambitions`: it travels with the card, exports, imports, and
  goes through Stoop review.
- **Seed cap (amended 2026-11-21, ruling 8):** a kit seeds at Skilled at
  most. `established` survives in pre-cap card JSON and clamps to
  `developing` when parsed — on both stacks, in the one reader each. The
  kit editors (desktop and web) offer Novice and Skilled only; nothing
  user-facing prints "Master" for a seed.
- **Budget:** at most 6 entries combined (ruling 11), enforced in the creator
  and at review. Card entries use a separate budget from the 12 story rings, so
  a kit never evicts story growth. Card bogies share the 3-bogey limit.
- **Seeding is a copy, not a link.** On the chat's first Growth touch, each kit
  entry becomes a ring at its tier's strength (emerging 0.30, developing 0.60 —
  `kDistillSeedStrength`), with `bb.seeded = true` and
  `advance_count` set to the tier's floor. Each chat's ninja starts with the
  same kit and grows apart from there.
- Seeded bogies start **pinned at Skilled, unpinned at Novice** (amended
  2026-11-21): an earned habit the author means cannot fade out in the
  first thirty turns, but a flaw authored as a crack stays fragile until
  the story says otherwise. The author can override either way; the pin
  does not block the accepted overcome path (§3.2).
- Groups: each member is seeded from their own card, once.
- **Existing chats:** switching the feature on offers the kit once, naming the
  whole cast. Decline writes nothing. The offer is re-runnable from the panel.
- Character creator: a "Boons & Bogies" block in the realism step
  (`lib/ui/character_creator/steps/realism_step.dart`); character editor and
  web editor get the same block. New field lands in
  `docs/design/group-card-field-manifest.json`.

## 5. The model creating new ones

The Growth prompt learns two more things it may do: add a `bogey`, and link a
bogey to a boon. Code keeps the guardrails, not the prompt:

- **Cap: 3 active bogies per character**, shared with card-seeded flaws. An add
  over the cap is dropped, not trimmed — existing flaws are the user's story.
  Boons have no new cap beyond the 12-ring budget.
- **New ones are proposals.** Adds and Master crossings go to the milestone
  (ruling 1), always. Skilled crossings and ordinary flaw changes apply
  silently with Undo (rulings 7–8).
- **Silent changes need `growthReviewFirst` off.** With it on, everything parks
  in the review list as today; the chip is then redundant, not wrong.
- **Prompt semantics for flaws:** a fire fades the flaw's *reputation* — it
  does not deepen it; coping fades it faster; only the story making it worse
  (or the roll count) advances it. Never reinforce a bogey for merely
  appearing. No test can prove a prompt obeyed this: hand-check and live test.
- Same transports as today (XML and native tools); the parser normalizes or
  drops unknown categories, so an old model ignoring `bogey` costs nothing.
- **Half-built guard:** until the milestone surface ships (phase 5), the
  applier holds advancement one step below Master, so "Master always asks"
  cannot be violated by a partial build.

## 6. Bogey rolls

- **Shared math, separate service.** Extract grow → roll → cooldown from
  `ChaosModeService` into a pure `PressureRoll` helper, with the current chaos
  numbers as its first caller and golden vectors proving chaos is bit-for-bit
  unchanged. Bogies call it with their own numbers and keep their own pending
  slot, so a Chance Time event and a bogey never share `_pendingChaosInjection`.
- **One roll per reply, for the speaker only.** Roll once; choose at most one
  bogey (highest pressure, ties random). The rate must not scale with the
  number of flaws, or three flaws means a moment every 2–3 replies.
- **Rate.** Base 3, growth 4 jittered 2–6, cooldown 2 jittered 1–3, chance
  capped at 45%. The v1 numbers (cooldown 4, no ceiling) actually produced a
  gap near 10–11, not the promised 6–9. A pure-function simulation test runs
  10k replies and asserts the median gap is 7–9; tuning moves the constants,
  not the test.
- **Injection** is a soft nudge, not an event: *"This reply, let {{char}}'s
  clumsiness show in a small, natural way."* Regen and swipe re-inject the same
  bogey (the chaos delivered-flag pattern); the slot clears on the next user
  turn. Continue does not roll.
- **Scene check:** if the emotional judge read `emotion_intensity: strong`, the
  roll is skipped and pressure holds. If the judge did not run (one-shot,
  Continue), the gate is **closed** — no roll on an unknown scene. Known v1
  limits: a strong joy scene also holds (a harmless delay); a muted grief scene
  reads moderate and can fire. A dedicated `scene_weight` field on the
  emotional judge is a v2 refinement, not a v1 blocker.
- **Chance Time precedence:** if a Chance Time event fired this turn, skip the
  bogey roll and hold pressure (ruling 16).
- **Boon link (v2):** each tier of the linked boon slows pressure growth; at
  Master it makes an overcome proposal likely. v1's overcome does not need it.

## 7. Milestones

A center-screen moment, shown **after the reply finishes streaming**, never
mid-stream. **Accept / Reject** (Redo cut, ruling 15). The effect plays on
Accept.

| Moment | Effect |
|---|---|
| New boon | Gold burst, rising glow |
| New bogey | Purple smoke, a cracked-glass shimmer — playful, not scary |
| Master (boon) | Confetti + the Master badge stamping in |
| Master (bogey) | Smoke + the permanence question |
| Bogey overcome | The smoke burns off into confetti |

**Budget and queue.** At most one milestone per 8 user messages
(`kMilestoneMinGapMessages`). Anything over budget is written to
`growth_moments` (session, character, ring, kind, tier, created, seen) and
listed unread in the **Moments** panel, replayable with its celebration.
Nothing is lost, nothing bombards.

**v1 vs v2 celebration.** v1 uses one static burst asset per kind, the same
SVG on both surfaces, scaling in — parity by construction, no Flame, no canvas,
no vectors. v2 replaces it with the deterministic sim: `milestone_burst.dart` ↔
`milestoneBurst.ts`, every particle decided from `(kind, seed)`, fixed 1/60 s
steps, units in card widths, pinned by
`test/fixtures/growth/milestone_burst_vectors.json` read by a Dart test and a
vitest. The palette (`milestone_palette.dart`: gold, gold deep, on-gold, bogey
violet, smoke, overcome green) is fixed in every theme; the web twin is marked
`theme-keep`. The card chrome follows the app theme.

**One UI.** The card is identical on desktop and web: title "✦ Milestone", kind
line, ring box with name, sentence and tier, receipt line, Accept / Reject on
one row at phone width. Only card padding and width may differ at phone size.
Desktop opens it through `showWarmDialog`. A milestone mockup shows desktop and
web phone rendered side by side at phone width — never a desktop render with
the web "themed to match." The v1 burst is one asset file used by both
surfaces, not a lookalike; the v2 sim is one shared spec pinned by one vectors
file. Reduce motion: no particles; the card appears at once with a static
badge. A group pass names the member on each card.

## 8. Porch Life switch

In the Memory group, nested under Growth Rings:

```
Growth Rings                                   [ ● ]
└─ Boons & Bogies          needs Growth Rings   [ ● ]
   ├─ Bogey rolls                               [ ● ]
   └─ Milestone popups                          [ ● ]
```

- `Boons & Bogies` — `FeatureNeed.needs`, `dependsOn: 'Growth Rings'`.
  Without Growth, nothing can advance or be proposed.
- `Bogey rolls` — progression without random flaws firing.
- `Milestone popups` — off means proposals land in the Growth panel's review
  list and Moments list instead of center screen.
- **Off is never destructive.** With Boons & Bogies off (or Growth off),
  existing boon and bogey rings stay in the chat and in history; nothing new is
  proposed, no bogey rolls, and seeded kits are not copied into new chats.
- New keys in memory settings, the web facade (`chat_tools_facade.dart`,
  `chat_tools_snapshot.dart`) and `settings-parity-manifest.json`.
- Default: **off** (ruling 4).

## 9. Groups

Parity by construction: rings are per character, roll state rides the ring
columns, the roll runs for the speaker only, and milestones name the member.
The Story Tools / Growth panel shows the focused member's boons and bogies,
like the chaos card does (`docs/design/chaos-per-character.md` §1). The
retroactive kit offer names the whole cast and seeds each member from their own
card.

## 10. Build phases

Each phase leaves the app working on both surfaces. v1 ends at phase 5; phases
6–7 are v2 and are not a promise attached to v1.

0. Repoint the 19 `growth-rings.md` comments (18 files) to this doc, dropping
   the dead section numbers. Comments only; no behaviour change.
1. `PressureRoll` extraction with chaos golden vectors — no behaviour change.
2. `bogey` category, v68 columns, `advance_count`, both ladders, prompt +
   parser support, silent changes with Undo snapshots and chips, panel, settings
   (default off), Moments table. Master is held one step below until phase 5.
3. Card `traitKit` + 6-item cap + seeding + retroactive offer + creator/editor
   on both surfaces + manifest + the Stoop line.
4. Bogey rolls + injection + regen/swipe behaviour + scene gate + Chance
   Time precedence. Rolls respect ruling 18: opted-out members are not
   rolled, and the pass prompt records `not offered` (§3).
5. Milestone card (static burst), budget, Moments list, Master and
   overcome, queue, group naming. Ships the ruling-18 participation UI
   (character default + sidebar toggle, both stacks) and lifts the BETA
   markers everywhere — the #763 checklist executes here.
6. (v2) Deterministic particle sim: Flame + canvas, shared vectors, golden,
   parity entry.
7. (v2) Boon link and its slowdown; a linked Master makes overcome likely.

## 11. Repo rules this has to meet (CLAUDE.md)

- **One UI:** every phase that touches UI ships desktop and `web_ui/` in the
  same PR, with screenshots in the PR body; new settings get
  `settings-parity-manifest.json` entries; the milestone card gets a golden.
- **Path-complete:** Growth is on the list. Bogey injection and boon/bogey
  proposals must cover regen, swipe, Continue (no new roll, no consumed bogey),
  delete/edit, and group speaker restore — matrix in
  `docs/design/path-complete-chat-work.md`.
- **Size law:** new files under 500 lines; `ChaosModeService` (377 today)
  shrinks when `PressureRoll` comes out. Bogey logic goes in its own leaf under
  `lib/services/chat/`, reached through the realism door, not `ChatService`.
- **Tests:** chaos golden vectors must fail if the extraction changes a roll;
  the rate simulation must fail if the median gap leaves 7–9; no
  scripted-answer tests for "the model picked a good bogey" — that is a `live`
  test or a hand check.
- **Rendered text** never shows `{{char}}`/`{{user}}` (rings are stored
  resolved already — `growth_ops.dart`).

## 12. Invariants

- The card is never written by a chat; rings never cross chats.
- **Content** changes go through `GrowthReview.applyOwnerProposals` (including
  the undo snapshot). **Gauges** have exactly one other writer,
  `setBogeyGauge`, which touches only the six gauge columns. Two writers, two
  disjoint column sets, stated out loud.
- At most one bogey injection per reply, for the speaker only.
- At most one milestone modal per 8 messages; overflow is never dropped.
- Chaos Mode behaviour is bit-for-bit unchanged (golden vectors).
- Turning any switch off loses no data.
- Pinned rings are never *silently* retired; the accepted overcome moment is
  the single, tested exception.

## 13. Risks

- **Popup fatigue.** With Master-only and the budget, the ceiling is one modal
  per 8 messages. Without the budget the estimate is one per 6–10, bursty,
  which is why the budget exists.
- **Over-acting.** Small models exaggerate anything they are reminded of. The
  chat prompt sees a flaw only on a firing turn, and the injection says "small";
  the filter at `injectionSelection` is the main defence, not the wording.
- **Bogey creep.** Hard cap of 3, shared with cards, and user acceptance on
  every new one.
- **Model judgment on overcome.** v1 lets the model propose "they beat it."
  Reject is the only safety net; the trigger is a hand-check, not a test.
- **Receipts are positions.** `sourceMessageIds` are message positions, not DB
  ids, so deleting a message can shift them. The ladders use the advance
  counter, not receipt count, for exactly this reason; receipts stay display
  text.
- **Identity churn at 12 rings.** A long chat with 2 new rings per pass will
  evict weak rings to stay at 12. The panel must show retired rings as past
  growth, not deletion, or the character reads as forgetful.
- **Two surfaces.** The web milestone is real work, not a port — which is why
  v1 uses one shared SVG and v2 carries the sim.

## 14. Open, non-blocking

Named so they are not discovered in review:

- Chip copy ("Clumsiness got worse — Undo") and panel layout.
- Where the Moments list sits inside the Growth panel and its unread badge.
- The exact Stoop line wording, drafted against the rubric's tone. It lands in
  the moderation repo (`stoop-bulk/moderation/rubric.md`), not this one.
- Whether the v1 static burst is enough to feel like a celebration, or whether
  v2's sim should be pulled forward. The phases are ordered so pulling it
  forward costs no rework.
