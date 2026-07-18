# Growth Rings — Character Evolution, Rebuilt on the Journal's Bones

Status: **SHIPPED** (all 3 phases, desktop + web, 2026-07-06 — mockup approved same day).
Implementation notes vs. this design: guest legacy evolved text (stored in the
1:1 guest blob, not session columns) is NOT distilled — guests start fresh
rings (documented trade-off); web receipts render as pills without
tap-to-jump (the web UI has no message-jump plumbing at all — pre-existing
platform gap).
Replaces the monolithic personality-rewrite system in `evolution_service.dart`.
Companion to `docs/design/journal-memory.md` (the Journal); rings reuse its
patterns (op transport, review parking, deterministic physics, per-chat scope)
without touching its cadence or cooling.

## 1. One-line pitch

Characters stop getting *rewritten* and start *growing rings*: small, discrete,
receipt-backed changes ("has learned to trust {{user}} with her past") that
strengthen when reinforced, fade when abandoned, and become permanent when
established — visible as a timeline, cheap for local models, and bounded in the
prompt.

## 2. Why

The current system asks the LLM to rewrite the ENTIRE personality + scenario
every `evolutionInterval` messages and stores the blob:

- **Photocopy drift.** Rewriting the whole text over and over echoes signature
  phrases, amplifies quirks, and silently drops subtle traits. The prompt begs
  the model not to ("REFINE, do not accumulate") — begging means the
  architecture is wrong.
- **Opaque.** No record of *what* changed or *why*; no receipts. Evolution #4
  vs #3 is two walls of text.
- **Blind to the engine.** It re-reads raw transcript + RAG chunks and ignores
  the distilled signals that now exist: Journal cards (emotion-stamped), the
  recap, bond/trust history, salient events.
- **Fragile.** Reproducing a whole personality in valid JSON is the hardest
  LLM call in the app — `evolution_service.dart` carries FOUR layers of salvage
  (code-fence extract, truncated-JSON repair, labeled sections, prose salvage).
- **Expensive.** The injected growth blob restates most of the original, so
  every turn pays for the personality roughly twice; the eval itself budgets up
  to 16K output tokens.
- **Redundant.** The evolved scenario ("[Current Situation]") duplicates the
  Journal's "Where we are" recap — two LLM passes maintaining two competing
  descriptions of the same thing.

## 3. Locked decisions (maintainer, 2026-07-06)

1. **Review-first exists but defaults OFF.** By default the character grows
   autonomously, no user intervention. A `growth_review_first` toggle (mirroring
   `journal_review_first`) parks proposals for approval when the user opts in.
2. **Scenario evolution is retired.** The Journal recap owns "where we are";
   rings own "who the character is becoming." `getEffectiveScenario` returns
   the card scenario unchanged (the recap is already injected by existing
   plumbing). The `evolvedScenario` columns go dormant (kept — additive-only DB
   policy + Character Card Forge safety), and their content is archived, not
   destroyed (§8).
3. **Fast cadence with a slider.** Rings are small, so checks fire often:
   default **every 5 user messages**, slider clamp 2–20, PLUS immediate checks
   on salient events (same deterministic sources as the Journal: |bond/trust|
   ≥ 12, trust repair, Chance Time, quest completion). Rationale for 5 over 3:
   ~10 messages is the smallest window where a pattern can show up twice —
   at 3 the pass mostly returns "no ops" and burns calls; the event kicks
   already catch every big moment instantly regardless of the slider.
4. **Strictly per-chat.** Rings are session-scoped exactly like Journal cards —
   no memory or growth ever crosses chats (standing user requirement). Deleted
   with the chat.
5. **The original card is immutable.** Rings only ever layer on top; Reset
   deletes rings, never card text.

## 4. Architecture

### 4.1 The ring

One ring = one discrete change, with provenance:

| field | meaning |
|---|---|
| `text` | one sentence, `{{char}}`/`{{user}}` macros allowed |
| `category` | `trait` (who they are) / `stance` (how they relate to {{user}}) / `habit` / `skill` / `scar` (lasting mark from a painful event) |
| `strength` | 0.0–1.0; tier derived: **emerging** < 0.35 ≤ **developing** < 0.8 ≤ **established** |
| `pinned` | user-pinned → permanent, never fades, never auto-retired |
| `retired` | past growth — visible in history, never injected |
| `sourceMessageIds` | receipts; reinforcement APPENDS new receipts |

### 4.2 The growth pass (its own small background job)

A separate mini-pass, NOT a rider on the Journal pass — the Journal's cooling
physics is per-pass and tuned to `journalInterval` (default 10); coupling
growth's faster cadence to it would silently speed up card cooling. The growth
pass has its own cursor (`growth_state.cursor`, new table) and its own trigger
in the same post-generation spot as `_maybeRunJournalPass`:

- due when user-messages-since-cursor ≥ `growthInterval` (default 5), OR the
  window holds a salient event (`JournalPhysics.hasSalientEvent` — shared, not
  duplicated), OR the quest-completed kick fires (the existing
  `eventKickPending` source gains a second consumer).
- per diary owner (the Journal's `_diaryOwners` logic is extracted to a shared
  helper used by both passes — consolidation, not duplication).
- prompt shows: original personality (trimmed), current rings as a 1-based
  handle list with tiers, the recap, the owner's HOT Journal cards, and the
  message window with the same salience annotations the Journal prompt uses.
  Grounded in distilled state — no RAG chunk fetch, no summary re-read.
- virgin cursor on a long chat reads only the trailing
  `JournalPhysics.kFirstPassCap` (50) messages, like the Journal.
- guests never grow; a parked review batch blocks further auto passes; cursor
  advances only on success (auto-retry semantics) — all Journal invariants.

### 4.3 Ops + transports (two front doors, one applier)

Ops mirror `journal_ops.dart`, tiny outputs, local-model floor:

- `<ring category="stance" src="#12,#14">has started guarding {{user}}'s sleep</ring>` — add
- `<ring id="3" action="reinforce" src="#18"/>` — strengthen + append receipts
- `<ring id="3" action="revise">reworded text</ring>`
- `<ring id="3" action="retire"/>` — contradicted / outgrown → Past. Retire
  ops targeting a user-pinned ring are dropped at resolution (2026-07-07):
  pinned means permanent, so only the diary UI may retire those; reinforce
  and revise on pinned rings stay allowed.
- Tool-calling variant (`kGrowthTools`) mirrors `kJournalTools`; the
  tools-vs-XML probe memory (`_xmlOnlyBackends`) is LIFTED from
  JournalMaintenance into shared plumbing so both passes learn a backend's
  answer once (consolidation payoff, per one-probe-per-backend-identity).
- Parse is forgiving (attribute regex, unclosed tags dropped, unknown
  categories normalized) — same floor as the Journal.

Resolution at pass time (handles → ring ids while the snapshot is live), then
ONE applier used by both normal and review mode — the `journal_review.dart`
pattern. If the parking/applier duplication with JournalReview turns out
substantial at build time, extract a shared generic parking helper; do not fork
behavior.

### 4.4 Ring physics (deterministic code, no LLM judgment)

Constants in `growth_physics.dart` (pure, mirrors `journal_physics.dart`):

- `kNewRingStrength = 0.30` — a new ring starts *emerging*.
- `kReinforceStep = +0.20` — clamp 1.0. Two reinforcements take an emerging
  ring to developing; three more make it established.
- `kFadePerPass = 0.05` — applied to non-established, non-pinned rings that
  were NOT reinforced this pass. An abandoned emerging ring dies in ~6 passes
  (~30 turns at default cadence); strength 0 → auto-retire to Past.
- **Established (≥ 0.8) never fades** — the trait became part of them
  (flashbulb analogue). Pinned never fades and never auto-retires.
- `kMaxNewRingsPerPass = 2` — the applier drops extra adds (logged). Frequent
  cadence must produce *reinforcement*, not ring floods.
- `kMaxActiveRings = 12` — cap trims the weakest unpinned, non-established
  ring to Past (Journal cap-trim analogue).
- Code constants until proven to need settings (Journal §6 precedent).

### 4.5 Injection (the token payoff)

`getEffectivePersonality` layering is re-owned by the growth leaf:
base (description + personality) + a compact block:

```
[Character Growth — how {{char}} has changed through this story]
- <established ring text>            (plain statement of settled fact)
- Increasingly, <developing ring>    (deterministic tier prefix)
- Lately, <emerging ring>
```

Top `kInjectedRings = 8` by (tier, strength) — except up to
`kReservedFreshSlots = 2` of those slots are reserved for the strongest
non-established rings (`GrowthPhysics.injectionSelection`, added 2026-07-07).
Established rings never fade and strength ties rank the older ring first, so
without the reserve a cast of 8+ permanent rings would crowd new growth out
of the prompt forever — the character would keep growing on record while
visibly freezing in the story. With ≤ 8 active rings (or when the fresh rings
already rank inside the top 8) the selection is identical to a plain top-8
take. Bounded, no echo, a fraction of the old blob cost. Rings never need
embeddings — always-few, always-ranked (no-RAG floor is trivially satisfied).

Known, accepted limit: with more than 8 *established* rings, the weakest
established ones fall out of the prompt (only their strength ordering
decides). Raising the injected count costs tokens every turn; 9+ established
rings is deep-marathon territory, so this is deliberate.

### 4.6 Groups — parity by construction

Same owner loop as the Journal (1:1 = one owner); rings keyed
(sessionId, characterId=stableGroupId) exactly like cards. Per-speaker growth
counts/dances disappear — the pass doesn't need impersonation because the
prompt names the owner explicitly (like the Journal pass).

## 5. Storage (additive only, zero CCF exposure)

Two NEW tables (next schema version; Character Card Forge tables untouched):

- `growth_rings(id, session_id, character_id, text, category, strength,
  pinned, retired, source_message_ids, created_at, last_reinforced_at)`
- `growth_state(session_id PK, cursor)`

`Sessions.evolvedPersonality/evolvedScenario/evolutionCount` +
`groupEvolved*` go **dormant** (kept, like `Personas.learnedFacts`).

## 6. Settings

- `characterEvolutionEnabled` — SAME pref key, rebranded "Character Growth"
  in UI; existing users keep their on/off choice.
- `growth_interval` — NEW key, default **5**, clamp 2–20 (slider in the panel).
  `evolution_interval` retires dormant (its 40-ish values would be wrong for
  rings; a new key avoids a bad inherited default).
- `growth_review_first` — NEW key, default **false** (locked decision #1).

## 7. Deletions (the consolidation payoff)

- `EvolutionService._extractCharacterEvolution` + `_extractBestJsonObject` +
  `_repairTruncatedJson` + `_tryParseLabeledSections` +
  `_salvagePersonalityFromProse` + the rewrite prompt — deleted (~500 lines of
  the most fragile LLM plumbing in the app).
- Scenario evolution end-to-end (locked decision #2).
- Evolution blob "Review & Edit" wells (desktop `evolution_panel.dart` body,
  web `EvolutionReviewModal.tsx`) → replaced by the timeline + (opt-in) review
  flow. "Evolve Now" → "Check growth now" (force pass). Old evolution-runner
  dialog in chat_page simplified away.
- `_maybeRunPeriodicEvals`'s evolution cadence branch → the growth trigger.

## 8. Migration (no data loss, no behavior cliff)

Chats with a non-empty evolved blob: the FIRST growth pass includes the
original + blob and instructs the model to distill the *difference* into 3–6
initial rings (seeded at strength 0.6, developing — they represent accumulated
growth). Until that pass succeeds, injection keeps using the old blob. On
success: both blobs (personality + scenario) are archived verbatim as a single
pinned, retired "Pre-rings growth summary" timeline entry (nothing destroyed),
the session's evolved fields are cleared, and injection switches to rings.

## 9. Build phases (each leaves the app fully working, both surfaces)

1. **Engine + swap.** Tables + store + ops/physics/prompt/pass leaves + tests;
   injection swap; scenario retirement; blob migration; shared probe/diary-owner
   extraction. Panels on BOTH surfaces repoint to a read-only ring list (the
   blob wells would otherwise display stale data).
2. **Timeline UI** (per approved mockup): desktop panel + web (desktop & phone
   layouts) — tiers, strength, receipts with tap-to-jump (reuse
   `message_jump.dart`), pin/edit/retire, slider, check-now, reset.
3. **Review-first mode**: parking + sidebar banner + review dialog with
   checkboxes on both surfaces, default off.

## 10. Invariants

- Strictly per-chat; rings die with the chat. No cross-chat leakage, ever.
- 1:1 ↔ group parity by construction (one owner loop, shared physics).
- Original card immutable; Reset deletes rings only.
- LLM proposes, code disposes: caps, fade, tiers, and receipts are
  deterministic physics — never model judgment.
- Additive storage only; CCF-written tables untouched.
- Review OFF by default: characters grow on their own unless the user opts in.
- The Journal's cadence, cooling, and prompts are untouched by this feature.
