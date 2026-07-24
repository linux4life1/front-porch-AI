# Parallel Eval Dispatch — Design (v1, for review)

Goal: cut the post-turn wait by running independent per-turn LLM calls
concurrently on backends that genuinely serve concurrent requests (oMLX — up
to 8 parallel generations, proven on the maintainer's dashboard: 2 prompts
prefilling while a third request decodes — and remote APIs), while KoboldCpp
stays strictly sequential (single slot; `--multiuser` splits the context
window and is not worth it).

Status: DESIGN ONLY — nothing implemented. Companion facts: the full
pipeline map (every call, gate, read/mutate set, and dependency edge) was
compiled 2026-07-15 and is summarized below; line references are as of
commit 221a657.

## 1. The pipeline today (facts)

Per user turn, in order:

**Pre-generation (blocks the reply):**
1. Objective completion check — now ONE batched call (0e6243f), reasoning off.
2. Realism pre-turn eval, one of three branches:
   - trust-repair call (pre-empts relationship), or
   - one-shot fused call (relationship+emotional+narrative+posture), or
   - 4 staggered evals via `Future.wait` (relationship, emotional,
     physical/time, narrative) — **already concurrent**, offset 50 ms purely
     for KoboldCpp FIFO order.
   - scene-time/posture eval (fired from physical or one-shot; ≤1 call)
   - batched realism verifier (default OFF per card)
   - objective task-gen (only when a fresh objective was just proposed)
3. Main reply generation (the visible stream).

**Post-generation (awaited, after the reply is visible):**
4. Needs-impact eval (+optional verifier, default off) → climax → refractory.

**Post-generation fire-and-forget (already background):**
5. Journal pass, 6. Growth pass, 7. RAG embed, 8. Cast detection,
9. Expression reclassify (lazy).

**Serialization mechanics:** every eval funnels through exactly two entry
points — `LlmEvalEngine.fireLLMEval` (llm_eval_engine.dart:270) and
`fireStructuredEval` → `fireToolEval` (pass_support.dart:138/161). On
KoboldCpp, `fireLLMEval` awaits `waitForIdle()` per call; on
oMLX/remote there is no such gate, so the existing `Future.wait` of the 4
realism evals ALREADY overlaps there today.

**Dependency edges that constrain ordering:**
- trust-repair ⟂ relationship (mutually exclusive branch).
- emotional → journal mood-congruence (journal reads `_characterEmotion`).
- decay → catastrophe arming happens pre-prompt (deterministic, not LLM).
- needs-impact → `is_climax` → nsfw refractory (must apply before next turn).
- narrative/one-shot proposal → task-gen call.
- verifier reads ALL main eval raw outputs (already gather-then-verify).
- ALL eval mutations go through the shared scalar fields; group mode wraps
  them in `_loadGroupRealismIntoScalars` / `_saveScalarsIntoGroupRealism`
  under impersonation — the scalars are a SINGLE shared register bank.

## 2. What parallelism is actually left to win

The 4-eval realism pack already runs concurrently. The remaining sequential
chain on the turn's critical path is:

    objective check → [realism pack] → REPLY → needs-impact

The real wins, in impact order:
- **W1. Overlap the needs-impact eval with nothing** — it's already after the
  reply; its cost is perceived only in the "processing" spinner and the lock
  on the next turn. Guarding + backgrounding it (like journal/growth) removes
  it from the perceived turn entirely.
- **W2. Overlap the objective check with the realism pack** (both
  pre-generation, independent read sets: objectives+messages vs
  scalars+messages; the only conflict is `eventKickPending`, which is a
  set-only flag both may write — commutative).
- **W3. On oMLX/remote, let the fire-and-forget passes (journal/growth)
  genuinely overlap the NEXT turn's calls** instead of queueing ahead of
  them (today they contend for the single Kobold slot; on oMLX they already
  overlap server-side — the app just has no cap, see risk R3).

Non-goals: parallelizing INSIDE the one-shot path (it exists to be one
call); parallel decode of the main reply (nothing to pair it with without
speculative work); Kobold multiuser.

## 3. Design: gather-then-apply with a scene-guarded applier

Three primitives, added at the existing choke points — no call-site rewrite:

**P1. EvalDispatcher (concurrency cap).** A small semaphore owned by
LLMProvider, capability-derived: `kobold → 1` (structural), `omlx → NO cap`
(the oMLX server's own UX owns parallelism — §6 decision), `openRouter → 3`
(politeness cap for cloud rate limits). `fireLLMEval` and `fireToolEval` acquire it. Kobold's existing
`waitForIdle` stays (belt over braces at cap=1). This makes today's implicit
behavior explicit and safe before anything new overlaps.

**P2. Fetch/apply split with a scene token.** Every eval that mutates state
splits into fetch (LLM call, no side effects) and apply (mutations). The
apply step re-validates `(generationEpoch, sessionToken, speakerId)` captured
at fetch-start; stale results are DROPPED with a debug line. The batch
collector for the 4-eval pack (realism_evals `_batchCollectActive`) already
does exactly this shape — extend the same contract to: needs-impact
(fetch/apply are already separate methods), objective check, task-gen.
**This primitive also closes the already-found live bug:** the needs-impact
apply currently has no epoch/session re-check after its await, so switching
chats mid-eval can bleed the old chat's deltas into the new chat
(discovered 2026-07-15 while answering the maintainer's question; fix ships
with P2 or standalone if P2 is deferred).

**P3. Deterministic apply order.** Fetches may complete in any order;
applies execute in a FIXED sequence per turn (the current sequential order:
relationship → emotional → physical/time → narrative → [verifier] →
needs-impact), driven by a per-turn applier that awaits the fetch futures in
that order. Parity holds by construction: 1:1 and group run the same applier;
group wraps it in the same load/save-scalars dance as today.

## 4. Phases

- **Phase 1 — Safety floor (small).** P2 scene-token guards on needs-impact +
  objective apply paths (fixes the live bleed bug); EvalDispatcher at cap=1
  everywhere (pure refactor, zero behavior change — locks current semantics
  under a named primitive). Tests: guard drops stale applies; dispatcher
  serializes.
- **Phase 2 — Pre-gen overlap (medium).** W2: objective check joins the
  realism pack's `Future.wait` behind the dispatcher; cap raised to 3 on
  oMLX/remote. Measure wall time per turn on the maintainer's Mac (his 31B +
  Qwen3.6-40B) before/after.
- **Phase 3 — Post-gen decoupling (medium, parity-sensitive).** W1: move
  needs-impact off the awaited path (chip attaches when the apply lands, like
  journal receipts); requires the P2 guard from Phase 1 plus a "next turn
  waits for pending applies of the same session" latch so a fast follow-up
  message can't race the previous turn's needs apply.
- **Phase 4 — Measurement + tuning.** Live A/B on oMLX (concurrency 1 vs 3),
  decode-throughput sharing measured (expect ~2×, not 3×, at 3-way overlap);
  document the numbers, pick defaults.

## 5. Risks / rules

- **R1. Parity (non-negotiable):** applies are single-threaded and ordered
  (P3); the scalar register bank is never mutated from two evals
  concurrently. Any change audits both the 1:1 and `_groupRealism` paths.
- **R2. Prompt-cache interaction:** concurrent prefills of different eval
  prompts compete for oMLX's cache; the chat prompt's big prefix (fixed
  2026-07-14, d86d590) must stay resident. Cap=3 chosen partly for this;
  Phase 4 measures cache efficiency at each cap.
- **R3. Runaway concurrency:** journal/growth/cast + next-turn evals could
  stack >cap; the dispatcher is GLOBAL per backend, not per-category, so the
  cap is a hard ceiling.
- **R4. KoboldCpp:** cap fixed at 1; `waitForIdle`/`ensureServerIdle` retry
  machinery untouched.
- **R5. Thinking models:** all verdict-style evals keep reasoning OFF (the
  objective check got this 0e6243f; audit the pack for stragglers in
  Phase 1).

## 6. Maintainer decisions (2026-07-15)

1. Late chips: APPROVED — Phase 3 may land needs chips a few seconds after
   the reply.
2. oMLX cap: NONE client-side — oMLX's own UX controls parallelism (user
   sets 1..8 there); if the server is at parallel=1 our evals simply queue
   server-side. "We shouldn't try to override another app's setup." The
   dispatcher therefore caps ONLY kobold (1, structural) and remote cloud
   APIs (small politeness cap for rate limits); oMLX flows uncapped.
3. Objective cadence: STAYS every turn — keeps quests in tune with the story.
   (Instead of cadence, staleness is handled by graceful retirement: a step
   that comes back NO kStaleCheckRetireAfter(=4) consecutive times is treated
   as overtaken by events and the quest advances — shipped same day in
   objective_proposal.dart.)
