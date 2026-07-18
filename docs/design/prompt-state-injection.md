# Unified Prompt Architecture ("spokes on a wheel") + Words-Only State Injection

**Status:** DRAFT v2 — reconciled with Grok 4.5 hostile review (verdict: approve with changes; all
required changes incorporated below). Awaiting maintainer approval. Nothing implemented yet.
**Scope:** How ALL per-turn features (Realism, Needs, Journal, RAG, recap, objectives, events,
lorebook, idle cues) reach the *generation* prompt — one shared contract instead of bolted-on
blocks. Eval prompts (realism_evals, needs_impact, journal, growth) are untouched — they keep raw
numbers and return JSON, where a number can never break immersion. Simulation math, decay,
storage, chips, and sidebar UI never change: this is purely the model-facing rendering layer.

## 1. Problem

The 2026-07-14 audit (cross-checked with Grok) found the per-turn state bundle is ~700–1200 tokens
with every fact stated 2–3×, an instruction ("use these numbers directly") that *causes* the
reported stat-bleed ("My hunger at 41 causes my stomach to grumble"), three "collate" reminder
paragraphs, contradictory trust blocks, mixed instruction registers (calm vs ALL-CAPS walls),
literal unresolved `{{user}}` reaching the model, an unbudgeted RAG block that trims the character
card when it fires, and stop sequences where four default strings fill the server's four slots so
every name-stop is dropped. Root cause: features were bolted on independently with no shared
contract for register, budget, placement, or precedence.

## 2. Design principles (the wheel)

1. **The app keeps the numbers; the model gets words.** No simulation scalar (needs x/100, bond
   points, trust level, arousal number, tier ints, refractory turn counts, inter-char deltas)
   ever appears in the generation prompt. Every scalar renders through banded natural language —
   the tables that already exist (`needSteppedText`, tier labels, arousal ladder). A number the
   model never sees is a number it can never say. **Invariant (redefined per review): "no
   simulation scalars", not "no digits"** — free-text fields (fixation, spatial stance, names,
   event bodies) may legitimately contain digits and are masked in the invariant test; the test
   digit-scans only app-authored template output and additionally asserts none of `/100`, `(+`,
   `points`, `tier`, `turns remaining` appear.
2. **Each fact exactly once; one register.** One composed state block; one guard sentence; every
   app-authored block (state, events, memories, recap, journal) uses the same calm, third-person,
   bracketed house style. No ALL-CAPS walls anywhere.
3. **Salience gating.** Sated needs, neutral moods, and inactive systems emit nothing (including
   the bond voice note, which only rides tiers with real warmth/hostility to mis-express). Quiet
   turn ≈ 130 tokens (header + time + bond/trust-neutral + guard); busy ≈ 180–250; ceiling ~300
   (an active NSFW refractory phase may add ~50 more — phase prose is capped at 2 sentences).
4. **One past, three roles.** The recap, the Journal, and RAG each open with a one-line role frame
   so the model knows how they relate: recap = "the story so far" (plot spine) · journal = the
   character's private feelings about it (outranks the others on how she *feels*) · RAG =
   "exact earlier lines, already happened — reference only, do not revisit."
5. **One skeleton.** The prompt is assembled as an ordered list of named sections rendered from a
   single source of truth (see §7) — the same list produces the prompt text, the token accounting,
   and the Context Viewer budget map, so they can never drift apart again.
6. **Parity is law.** 1:1 vs group must render through the same ladders and selection logic
   (per-speaker inputs, shared text), and the one-shot eval path is untouched (the block is
   assembled once in `_generateResponse` and shared). This work *fixes* one existing parity hole
   (§5c) rather than adding any.

## 3. The state block (composed by `RealismStateInjection`, same call site/position)

```
[How <Name> is right now:
<line>
...
Express all of this only through <Name>'s behavior, body language, and voice — never quote
meters, scores, percentages, turn counts, or system terms.]
```

### Line inventory (in order, each salience-gated)

| Line | Gate | Rendering rules |
|---|---|---|
| Scene time | time tracking active | `It is <timeOfDay> on <Weekday> (day <N> of their story).` |
| Bond & tension (+ trust when tier 0) | always when realism on | One sentence merging the existing bondGuidance + tensionGuidance ladders, words only. **One full ladder for BOTH 1:1 and group** — the group branch's coarse "high positives only, everything else neutral" switch is deleted (pre-existing parity violation: group members currently cannot render hostility). When trust tier == 0, fold the "engages on the merits of the moment, neither assuming the best nor the worst" clause in here. Ends with the voice-preserving note (**named load-bearing** — keep verbatim: warmth surfaces in THEIR fashion, never generic sweetness). |
| Trust | tier != 0 | ONE sentence from the existing Trust Calibration frames, shortened — but the "this governs depth, not temperament; never mute the personality to signal caution" tail is **named load-bearing** and kept. The behavioral BLIND TRUST / MISTRUST anchors are DELETED (contradiction resolved; nothing unique survives). |
| Mood | emotion non-empty AND != 'neutral' (case-insensitive; scalar may be `''` until set) | `Mood: <emotion>, <intensity> — let it subtly color tone and body language.` |
| Needs | effective step <= 4, worst 3 (cap raised 2→3) | Via `getLowNeedsForInjection`, **extended with the `enjoysLowHygieneOverride` parameter and passed the speaker's own flag** (without this the group "enjoys low hygiene" selection re-breaks — review-mandated). Line = the stepped prose only, no key/value. Hygiene inversion keeps its dedicated text AND the odor-only scoping sentence (**named load-bearing** — the mop-bucket regression guard). |
| Body (arousal/refractory) | cooldown active OR arousal outside [-15, +15] (mild bands deliberately silent) | Phases/bands condensed to <= 2 sentences each; the peak-arousal "desire meter, not a climax countdown / may finish naturally under active stimulation" rule is **named load-bearing** and kept; spatial restatement dropped (position has its own line). |
| Fixation | active && lifespan > 0 | `On their mind: "<fixation>" keeps drifting back — a background thought, not an obsession.` (free text; digits allowed) |
| Position | stance non-empty | `Position: <stance> — ground actions in this, but they are free to move.` |
| Private feelings (group) | tracked, non-neutral entries | Attitude words only; numeric deltas removed. |

If nothing is salient, the block is omitted entirely.

### Pronoun policy (review-mandated)

The stepped-text tables currently say "their stomach… they keep thinking" while the block header
names the character — mixed pronouns read as template-paste on small models. All app-authored
fragment prose is rewritten **pronoun-free** ("Stomach painfully hollow and tight — a constant,
distracting ache; restless, short-tempered, thoughts drifting to food."), so one table serves
every character without a gender field. Applies to `needSteppedText`,
`hygieneSteppedTextWhenEnjoysLow`, and the condensed NSFW/trust/tension fragments.

## 4. Composer stays thin (file-size rule)

Fragment prose lives in the leaf builders (they keep their classes, cbs, and group/1:1 branches);
`realism_state_injection.dart` only **gates, orders, and wraps** — it must stay under the 500-line
cap. Deletions: the "Current Metrics" section, `---` fences, both collation paragraphs, the
`_currentEmotion`/`_currentEmotionIntensity` regex self-parsers (composer reads the same
`getCharacterEmotion`/`getEmotionIntensity` cbs), `behavioral_injection.dart`'s trust anchors
(class deleted + unwired if empty), `getSecondaryLowNeedNote` if orphaned, stale "2 lowest" docs.

## 5. Companion fixes in the same phase

**5a. Macros (bug):** `realismBlock`, the needs-catastrophe block, and the continue-mode rule are
never macro-resolved — literal `{{user}}` reaches the model (30+ occurrences). Fix: resolve each
at its assembly call site with the existing `macroCtx` (per-site, NOT one whole-prompt resolve —
that would double-process `{{pick}}`/`{{roll}}` in user-authored content). Continue-mode's rule is
resolved even though its state blocks are stripped.

**5b. Chance Time:** rewritten into the catastrophe register (calm, firm, no ALL-CAPS, never names
the mechanic). **Placement stays post-suffix for now** — the current position is a documented
recency choice ("maximum recency weight"), not an accident; moving it is a measured decision
(manual A/B on a weak local model, Phase 3), not an aesthetic one. (Reversed from draft v1 per
review.)

**5c. Group tension parity (pre-existing bug):** one full tension ladder shared by 1:1 and group
(see §3 table).

**5d. Idle/AFK cue (pre-existing stat-bleed):** `chat_service_idle_autonomous.dart` injects
`hunger is low (41/100)` into a generation-facing cue — same words-only treatment (reuse the
stepped prose, drop the numbers).

**5e. Stop sequences (maintainer-confirmed requirement: more than 4, custom stops must be
honored):** Today the first four *default* stop strings occupy all four server slots, so
user-added custom stops and every name-stop have likely NEVER been sent to the server (the
mid-stream client trim silently hid this — text gets cut client-side, but the server generates on,
wasting tokens and holding the single local slot). Fix, per backend capability:

- **Local KoboldCpp:** send the FULL prioritized list. At implementation, verify the bundled
  KoboldCpp's actual `stop`/`stop_sequence` limit on the OpenAI-compat endpoint (believed 16 —
  must be probed/source-checked, not assumed) and cap there; log a warning if the list still
  overflows.
- **Remote (OpenRouter etc.):** provider `stop` arrays are commonly hard-capped at 4 — send the
  top 4 by priority; everything beyond rides the existing client-side trim (documented as the
  guaranteed floor, not an accident).
- **Priority order (both paths):** (1) `\nUser:` + `\n<persona name>:` (skipped when
  impersonating), (2) **user-configured custom stops** (explicit user intent outranks generated
  entries), (3) group member names soonest-next-speaker first (never the continue-speaker),
  (4) remaining template-end defaults. Drop from the bottom.

The impersonate path (`chat_service_impersonate.dart`) gets the same prioritized assembly — no
second stop path.

**5f. RAG budget (bug):** after retrieval, real-count the memories block with `_countTokens`; if
it exceeds the memory budget, trim trailing memories first; then re-run the history budget walk
with the remainder. Accepted one-turn lag for second-walk evictions. Fixed + history + memories +
generation reserve <= context, always.

## 6. The wheel's rim — past-channel role frames + degradation floors

One added line each, house register: recap opens "The story so far:", journal keeps its existing
frame plus "these private feelings outrank the raw lines below when they cover the same moment,"
RAG opens "Exact earlier lines from this chat (already happened — reference only, do not
revisit):". No other change to those systems.

**Degradation floors (maintainer-flagged):** RAG is opt-in and default OFF (`ragEnabled ?? false`)
— nothing in the wheel may assume its presence: role frames render only for blocks that exist,
and the §5f budget logic short-circuits cleanly when RAG is off (no reserved slice). The Journal
is default ON (`journalEnabled ?? true` — only an explicit user toggle disables it) and works
without the embedding sidecar (hot/pinned cards need no vectors; only cold-card resurfacing does).
Note: because the recap now rides the journal pass, disabling the Journal also silently loses the
recap — Phase 1 adds a warning to that toggle's label/tooltip ("also disables the 'Where we are'
recap and long-term memory"), desktop + web settings surfaces together (parity).

## 7. The hub — single-source section assembly (Phase 2)

Today the prompt exists as two hand-synced giant string interpolations (`fixedContent` for
counting, `prompt` for sending) plus a hand-built budget map — three copies of the same structure
that must be edited in triplicate (the draft-v1 reviewer caught them already subtly diverging).
Phase 2 replaces them with one ordered list of named sections
(`lib/services/chat/prompt_plan.dart`, < 500 lines: `{id, zone, label, text}`); the renderer
produces (a) the system string, (b) the user string, (c) the token ledger, (d) the Context Viewer
budget map from the same list. Zones: system → preHistory (recap, journal, RAG) → history →
tail (post-history, AN lore, author's notes, objectives, state block, catastrophe, idle cue) →
suffix → postSuffix (chance time, pending A/B). The ledger owns drop priority when the context is
tight (memories → oldest history; fixed sections never silently dropped). `_generateResponse`
keeps its flow — only the string-building and counting collapse into the plan. This is the
"spokes on a wheel" piece: every feature contributes a named spoke; the hub renders them all, and
a new feature CANNOT be bolted on outside the contract.

## 8. Phase 3 — cache work (MEASURED 2026-07-14, shipped)

Measured on the maintainer's own hardware/models via the managed KoboldCpp binary (port 5199,
ctx 8192, --jinja, max_tokens=1 probes, `/api/extra/perf` last_process), simulating the app's
exact request shape over 8 consecutive full-context turns:

**8a. Chunked history trimming (SHIPPED — `kHistoryTrimChunk = 8` in chat_service_history.dart).**
Dropping one oldest message per turn shifted the prompt prefix every turn. Quantizing the drop
point up to a chunk boundary keeps the prefix byte-stable for up to 8 turns. Results (mean warm
prompt-process per turn): Gemma-4-31B Q8 (SWA — ContextShift impossible): **2.42s → 0.44s
(5.5×)**; wall per non-eviction turn **~14s → ~0.9s**. mini-magnum-12B Q6 (shift-capable):
0.05s → 0.02s (2.5× — ContextShift already absorbed most of the scroll there). Stateless
(boundary derived from the drop index), so regen/swipe/reload land on the same boundary.

**8b. RAG placement (SHIPPED — memories section moved AFTER the transcript).** Retrieval changes
the block every turn; before the history it rewrote the prompt's MIDDLE each turn — a full
transcript re-prefill on every model class (a middle edit defeats ContextShift too). Measured on
Gemma-4-31B with chunked trimming active in both arms: **2.62s → 0.40s mean prompt-process
(6.5×), ~15s → ~1.2s wall on typical turns**. Echo risk is carried by the Phase-1 framing
("already happened — reference only, do not revisit"); the block gained a leading newline since
history carries no trailing one. Thanks to §7 this was a section reorder in the plan.

**8c. Chance Time placement A/B (NOT moved — still post-suffix).** Its metric is response
*quality* (does a weak model react to the event more reliably before vs after the name cue), not
prefill timing — it fires rarely so cache impact is nil. Protocol when a human judge is
available: same chat, same event, 10 regens per placement on a ≤13B model; score "reacted in
first paragraph / mentioned mechanics / ignored". Until then the documented recency choice
stands.

## 8.5 Still out of scope (needs separate approval)

Remote multi-turn role mapping; journal/RAG dedup smarts; journal hot-set order stabilization
(its reordering breaks the prefix only when mood shifts between passes — much rarer than
retrieval).

## 9. Verification

1. `flutter analyze` + `dart fix --dry-run`; dead-code greps for every deleted member.
2. Tests: rewritten `prompt_injection_test.dart`; scalar-invariant test (free text masked); group
   hostile-tension parity test; group enjoys-low-hygiene *selection* test; stop-priority test
   (6-member group + persona + defaults under cap 4); macro smoke test (composed block contains no
   `{{user}}`/`{{char}}`); RAG budget test (fixed+history+memories+reserve <= context); idle cue
   words-only test.
3. Manual (`flutter run -d macos`): Context Viewer inspection on 1:1, group, NSFW-cooldown,
   low-needs, and quiet turns; confirm chips/sidebar unchanged (no state math touched).
4. WebUI parity: none required (web rides the same ChatService assembly).
5. `docs/Rawhide.md` bullet + `.claude/changelog.md` entries at ship time.

## 10. Example — what the model sees

Busy 1:1 turn (evening; hungry + tired; fixation; growing trust; sitting together):

```
[How Alice is right now:
It is evening on Wednesday (day 3 of their story).
Alice feels a deepening, stable connection to Ben and sees a real future with him; right now she
is warm and openly affectionate. Express this through her own personality and voice — warmth from
a harsh, guarded, or dominant character surfaces in THEIR fashion (grudging, teasing, subtle acts
of care), never as generic sweetness that erases who they are.
She genuinely trusts Ben — the social mask is down, and she speaks more candidly than she would
with most people. Trust governs how much depth she risks, not her temperament: never mute her
natural personality to signal caution.
Mood: happy, moderate — let it subtly color tone and body language.
Hunger: stomach painfully hollow and tight — a constant, distracting ache; restless,
short-tempered, thoughts keep drifting to food.
Energy: a deep weariness — movements a little slower, less animated than usual, clearly running
low.
On her mind: "the promise Ben made last night" keeps drifting back — a background thought, not an
obsession.
Position: sitting beside Ben on the porch steps — ground actions in this, but they are free to
move.
Express all of this only through Alice's behavior, body language, and voice — never quote meters,
scores, percentages, turn counts, or system terms.]
```

(~180 tokens; today's equivalent is ~900 with every value duplicated 2–3×.)

Quiet turn (everything sated/neutral, trust tier 0):

```
[How Alice is right now:
It is midday on Monday (day 1 of their story).
Alice's bond with Ben is developing normally; she has no particular trust or distrust of him yet —
she engages on the merits of the moment, neither assuming the best nor the worst.
Express all of this only through Alice's behavior, body language, and voice — never quote meters,
scores, percentages, turn counts, or system terms.]
```

(~55 tokens.)
