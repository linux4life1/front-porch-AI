# Boons & Bogies — character traits that grow, built on Growth Rings (proposal)

Status: **proposal, 2026-11-19. Nothing is built.** Every "today" claim below
names the file it was read from.

## 0. Rulings (maintainer, 2026-11-19)

1. **Approval:** new boons, tier-ups, new bogies and bogey retirements always
   go through the milestone popup, even with `growthReviewFirst` off.
   Ordinary rings keep following `growthReviewFirst`.
2. **Tier names:** shown as **Novice / Skilled / Master**. The physics tiers
   underneath (emerging / developing / established) are unchanged.
3. **Roll numbers:** base 3, growth 4 per reply, cooldown 4 replies. Separate
   from the Porch Life Chaos frequency.
4. **Default:** Boons & Bogies ships **off**.
5. **Heavy scenes:** a bogey that would fire during a heavy scene is held:
   the roll is skipped and pressure keeps its value, so the flaw shows up
   once the scene calms. Keyed on the emotional judge that already runs (the
   exact output field is checked in `realism_judges.dart` at build time).
6. **Growth doc:** `docs/design/growth-rings.md` stays deleted. This doc is
   the Growth design reference; phase 0 repoints the code comments here.

## 1. Pitch

A character carries **boons** (abilities that get better: a ninja's stealth)
and **bogies** (flaws that show up now and then: the same ninja is clumsy).
Boons climb tiers as the story earns them. Bogies fire on a pressure roll —
never every turn, never twice in a row, but guaranteed to surface. The payoff
loop is the two touching: a boon growing can wear a bogey down until the
character overcomes it. When any of that happens, a center-screen moment
(confetti for a boon, purple smoke for a bogey) lets the user accept, redo,
or reject it.

Card authors can pre-seed a kit; the model can propose new boons and bogies
as the story goes.

## 2. What exists today (read from the code, 2026-11-19 @ 8cc55bfc1)

| Piece | Where | What it already does |
|---|---|---|
| Growth ring | `lib/database/database.tables.features.dart:190` (`GrowthRings`) | Per-chat, per-character row: `category` (trait/stance/habit/skill/scar/archive), `strength` 0..1, `pinned`, `retired`, receipts, a `metadata` JSON pouch "additive future". Rings never cross chats and die with the chat. |
| Tiers + physics | `lib/services/chat/growth_physics.dart` | New ring 0.30; reinforce +0.20; fade −0.05/pass if unreinforced and unpinned; developing ≥ 0.35; established ≥ 0.80 (permanent, never fades). "LLM proposes, code disposes." |
| Growth pass | `lib/services/chat/growth_service.dart`, `growth_prompt.dart`, `growth_ops.dart` | Own background job with its own cursor; fires on an interval or a salience kick. Model emits ring ops (add/reinforce/revise/retire) via XML tags or native tool calls; garbage yields zero ops. |
| Review + the one applier | `lib/services/chat/growth_review.dart` | Every op becomes a `GrowthProposedOp`; `applyOwnerProposals` is the single write path. `growthReviewFirst` (default **off**, `lib/services/storage/settings/memory_settings.dart:56`) parks the batch for accept/discard. |
| Pressure roll | `lib/services/chat/chaos_mode_service.dart:262` (`checkAndTickChaosPressure`), `:316` (`checkAndTickMember`) | Pressure grows each turn without a hit; chance = base + pressure; a hit zeroes pressure and starts a cooldown. Group twin reads/mutates only the speaking member's bag. |
| Card identity fields | `lib/models/character/front_porch_extensions.dart:96,127` | `ambitions`, `likes`, `dislikes` travel with the card; per-chat state lives elsewhere. |
| Flame | `pubspec.yaml:101` (`flame: ^1.38.2`), `lib/ui/chat_components/ambient/ambient_stage_game.dart` | Drives the ambient weather stage; reduce-motion is already read in `ambient_stage_mount.dart`. |
| Porch Life dependencies | `lib/ui/settings/widgets/feature_tree.dart:29` (`FeatureNeed`), `lib/ui/settings/tabs/porch_life_memory_group.dart:170` (Growth Rings row) | `FeatureRow` carries `need`, `dependsOn`, a dependency badge and jump-to. Growth Rings is `memory.characterEvolutionEnabled`. |
| Web surface | `web_ui/`, `docs/design/settings-parity-manifest.json` | Every settings control and chat surface has a web twin; parity is test-guarded. |

**Note:** `docs/design/growth-rings.md` was deleted in `dc473cf66` and is
still cited by 19 comments in 18 files, several with section numbers
(§4.2–§4.4) that no longer exist anywhere. Per ruling 6 it stays deleted:
the table above is the Growth reference, and phase 0 repoints those
comments to this doc without section numbers.

## 3. The model

### 3.1 Kinds

- **Boon** — rides the existing `skill` category. Shown as "Boon" in the UI.
  Its tier *is* advancement: Emerging → Developing → Established (the tiers
  `GrowthPhysics` already derives), shown as Novice → Skilled → Master
  (ruling 2). No new physics.
- **Bogey** — a **new** model-writable category `bogey`. Not `scar`: a scar is
  something that happened to the character; a bogey is a recurring flaw that
  fires on a roll.

### 3.2 What goes in `metadata`

No migration — the pouch exists for this:

```json
{
  "bb": {
    "seeded": true,              // came from the card kit
    "linkedBoon": "<ring id>",   // bogey only: the boon that wears it down
    "pressure": 12,              // bogey only: 0..100
    "cooldown": 0                // bogey only: replies left with no roll
  }
}
```

Roll state lives on the ring, so it is per chat and per character by
construction — the group-tick-everyone trap cannot happen here because there
is no shared scalar to tick.

## 4. Pre-seeding from the card

- New card field `traitKit` on `FrontPorchExtensions`:
  `[{kind: boon|bogey, text, tier: emerging|developing|established, pinned, linkedTo?}]`.
  Identity, like `ambitions`: it travels with the card, exports, imports, and
  goes through Stoop review.
- **Seeding is a copy, not a link.** On the chat's first Growth touch, each kit
  entry becomes a ring at its tier's strength (emerging 0.30, developing
  0.60 — the existing `kDistillSeedStrength` — established 0.80), with
  `bb.seeded = true`. Each chat's ninja starts with the same kit and grows
  apart from there. Editing the card later does not rewrite running chats.
- Seeded bogies start **pinned** by default so the author's core flaw cannot
  fade out in the first thirty turns; the author can untick that.
- Groups: each member is seeded from their own card, once.
- Character creator: a "Boons & Bogies" block in the realism step
  (`lib/ui/character_creator/steps/realism_step.dart`); character editor and
  web editor get the same block. New field lands in
  `docs/design/group-card-field-manifest.json`.

## 5. The model creating new ones

The Growth prompt learns two more things it may do: add a `bogey`, and link a
bogey to a boon. Code keeps the guardrails, not the prompt:

- **Cap: 3 active bogies per character** (code constant in `GrowthPhysics`,
  enforced in the applier; an add over the cap is dropped, not trimmed —
  existing flaws are the user's story). Boons have no new cap beyond the
  ring cap.
- **New ones are proposals.** Adds and tier changes for boons and bogies go
  to the milestone popup (§7) for accept / redo / reject, always — even with
  `growthReviewFirst` off (ruling 1). Ordinary rings in the same pass keep
  following `growthReviewFirst`, so one pass can apply some ops and park
  others.
- Same transports as today (XML and native tools); the parser normalizes or
  drops unknown categories, so an old model ignoring `bogey` costs nothing.

## 6. Bogey rolls

- **Shared math, separate service.** Extract the grow → roll → cooldown step
  from `ChaosModeService` into a pure helper (`PressureRoll`), with the
  current chaos numbers as its first caller and golden vectors proving chaos
  is bit-for-bit unchanged. Bogies call it with their own numbers and keep
  their own pending slot, so a Chance Time event and a bogey on the same turn
  never fight over `_pendingChaosInjection`.
- **One roll per reply, for the speaker only.** Pick at most one bogey per
  reply (highest pressure wins ties at random) so two flaws never stack.
- **Injection** is a soft nudge, not an event: *"This reply, let
  {{char}}'s clumsiness show in a small, natural way."* Regen and swipe of that
  reply re-inject the same bogey (the chaos delivered-flag pattern); the slot
  clears on the next user turn.
- **Scene check:** if the pre-generation emotional judge reads a heavy scene,
  the roll is skipped and pressure holds (ruling 5). No extra model call —
  the judge already runs. The exact output field is read from
  `realism_judges.dart` at build time, not assumed here.
- **Boon link:** each tier of the linked boon slows the bogey's pressure
  growth. When the linked boon reaches Established, the next Growth pass may
  propose **retiring** the bogey — the "overcame it" moment.
- Starting numbers (tunable code constants, like `GrowthPhysics`): base 3,
  growth 4/reply, cooldown 4 replies → roughly one bogey moment every 6–9
  replies per active bogey (ruling 3). Porch Life's Chaos frequency does not
  scale these.

## 7. The milestone popup

A center-screen moment, shown **after the reply finishes streaming**, never
mid-stream. It is the approval card itself: **Accept / Redo / Reject**. The
effect plays on Accept.

| Moment | Effect |
|---|---|
| New boon | Gold confetti burst, rising glow |
| Boon tier up | Confetti + the tier badge stamping in |
| New bogey | Purple smoke puff, a cracked-glass shimmer — playful, not scary |
| Bogey overcome (retired) | The smoke burns off into confetti |

**One UI, built the way Chance Time is.** Chance Time already ships one
screen on two engines; the milestone moment copies its structure piece for
piece:

| Chance Time today | Milestone moment |
|---|---|
| `lib/services/chat/chaos/chance_spin.dart` ↔ `web_ui/src/theme/chanceSpin.ts`: the spin as plain maths, outcome first, shared bit for bit | `milestone_burst.dart` ↔ `milestoneBurst.ts`: every particle's start, velocity, colour and life decided from `(kind, seed)` before anything moves; fixed 1/60 s steps; units are card widths from the card's centre, so a phone and a desktop burst are the same shape at different sizes |
| Pinned by `test/fixtures/chaos/chance_spin_vectors.json`, read by both `chance_spin_test.dart` and `chanceSpin.test.ts` | `test/fixtures/growth/milestone_burst_vectors.json`, read by a Dart test and a vitest, failing if either side drifts |
| Spin seeded from the event, so a reconnect replays it | Burst seeded from the ring id (plus the tier for a tier-up), so a second device or a reconnect shows the same burst |
| `chance_wheel_game.dart` / `chance_wheel_bursts.dart` (Flame) and `chanceWheelPaint.ts` (canvas) only *paint* the sim | `milestone_burst_game.dart` (Flame) and `milestoneBurstPaint.ts` (canvas) only paint it |
| `chance_time_palette.dart`: the game's own colours, fixed in every theme; web twin marked `theme-keep` | `milestone_palette.dart` (gold, gold deep, on-gold, bogey violet, smoke, overcome green): fixed in every theme, web twin `theme-keep`. Confetti in a fixed drop order |
| Card chrome (`.chance-card`: surface, border, text) follows the app theme | Same: the card follows the theme; only the kind line, Accept button and particles use the fixed palette |
| Centered, blocking, `aria-modal`; the parked send waits for Accept | Centered, blocking, `aria-modal`; shown after the reply finishes |
| Reduce motion: the wheel jumps to its stop | Reduce motion: no particles; the card appears at once |

- **Identical:** card structure (title "✦ Milestone", kind line, ring box
  with name, sentence and tier, receipt line), the three buttons and their
  order (Reject, Redo, Accept), wording, the four moments, burst shape and
  timing. Buttons stay on one row at phone width.
- **May differ:** only layout — card padding and width at phone size.
- Desktop opens the card through `showWarmDialog` with the Flame layer over
  it (the Chance Time overlay paints its wheel over the card the same way).
- A shared surface gets a golden and a `one_ui_parity_test` entry in the PR
  that adds it; PR screenshots show desktop and web phone side by side.
- **Reduce Motion:** no particles; the same card appears with a static badge.
- **Redo** reruns the proposal for the same message window (the Growth cursor
  has not moved for a parked batch, so this is safe — `growth_review.dart`).
- **Queue:** several moments in one pass show one at a time; a group pass
  names the member on each card.
- Text on the card is the ring sentence plus its receipt ("slipped past the
  guards without help — message 42").

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
  list instead of center screen.
- **Off is never destructive.** With Boons & Bogies off (or Growth off),
  existing boon and bogey rings stay in the chat and in history; nothing new
  is proposed and no bogey rolls. Seeded kits are not copied into new chats.
- New keys in memory settings, the web facade
  (`chat_tools_facade.dart`, `chat_tools_snapshot.dart`) and
  `settings-parity-manifest.json`.
- Default: **off** for the first release (ruling 4).

## 9. Groups

Parity by construction: rings are already per character, roll state rides the
ring, the roll runs for the speaker only, and popups name the member. The
Story Tools / Growth panel shows the focused member's boons and bogies, like
the chaos card does (`docs/design/chaos-per-character.md` §1).

## 10. Build phases (each leaves the app working on both surfaces)

0. Repoint the 19 `growth-rings.md` comments (18 files) to this doc, dropping
   the dead section numbers. Comments only; no behaviour change.
1. `PressureRoll` extraction with chaos golden vectors — no behaviour change.
2. `bogey` category, `bb` metadata, cap, prompt + parser support; boons and
   bogies show in the Growth panel. Settings switches land here (default off).
3. Card `traitKit` + seeding + creator/editor UI on both surfaces + manifest.
4. Bogey rolls + injection + regen/swipe behaviour + scene check.
5. Milestone popup: desktop Flame, web twin, reduce-motion, queue, redo.
6. Boon ↔ bogey link and "overcome" retirement.

## 11. Repo rules this has to meet (CLAUDE.md)

- **One UI:** every phase that touches UI ships desktop and `web_ui/` in the
  same PR, with screenshots in the PR body; new settings get
  `settings-parity-manifest.json` entries; the popup gets a golden.
- **Path-complete:** Growth is on the list. Bogey injection and boon/bogey
  proposals must cover regen, swipe, Continue (not a regen: no new roll, no
  consumed bogey), delete/edit, and group speaker restore — matrix in
  `docs/design/path-complete-chat-work.md`.
- **Size law:** new files under 500 lines; `ChaosModeService` (377 today)
  shrinks when `PressureRoll` comes out. Bogey logic goes in its own leaf
  under `lib/services/chat/`, reached through the realism door, not
  `ChatService`.
- **Tests:** chaos golden vectors must fail if the extraction changes a
  roll; no scripted-answer tests for "the model picked a good bogey" —
  that is a `live` test or a hand check.
- **Rendered text** never shows `{{char}}`/`{{user}}` (rings are stored
  resolved already — `growth_ops.dart`).

## 12. Invariants

- The card is never written by a chat; rings never cross chats.
- One write path: every boon/bogey change goes through
  `GrowthReview.applyOwnerProposals`.
- At most one bogey injection per reply, for the speaker only.
- Chaos Mode behaviour is bit-for-bit unchanged (golden vectors).
- Turning any switch off loses no data.
- Pinned rings are never AI-retired (the `ed7683bcc` fix stays true for bogies).

## 13. Risks

- **Over-acting.** Small models exaggerate anything they are reminded of. The
  pressure roll is the main defence; the injection wording must say "small".
- **Bogey creep.** Hence the hard cap and user acceptance.
- **Popup fatigue.** If it fires too often it will be switched off — the
  sub-switch exists for that, and tier-ups should be rare by physics.
- **Two surfaces.** The web popup is real work, not a port.
