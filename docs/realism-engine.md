# Realism Engine

The Realism Engine is Front Porch AI's system for tracking character relationships, emotions, and story progression across conversations.

---

## Table of Contents

1. [Overview](#overview)
2. [Enabling & Disabling](#enabling--disabling)
3. [Bond Tracking](#bond-tracking)
4. [Trust System](#trust-system)
5. [Emotion States](#emotion-states)
6. [Arousal System](#arousal-system)
7. [Passage of Time](#passage-of-time)
8. [Chaos Mode (Chance Time)](#chaos-mode-chance-time)
9. [Character Evolution](#character-evolution)
10. [Fixation Engine](#fixation-engine)
11. [NSFW Cooldown](#nsfw-cooldown)
12. [One-Shot Eval Mode](#one-shot-eval-mode)
13. [Performance Considerations](#performance-considerations)
14. [Troubleshooting](#troubleshooting)

---

## Overview

The Realism Engine is Front Porch AI's signature feature for making AI characters feel like living, evolving people rather than scripted responders. Without it, conversations are stateless: every message is evaluated in isolation, relationships never deepen or fracture, emotions reset instantly, and the passage of time is ignored. Characters can say "I love you" one turn and treat you like a stranger the next.

**How it works (technical overview):**

After the AI generates a response (or immediately after a greeting), the Realism Engine runs a series of lightweight LLM "evaluation" calls (distinct from the main chat generation). These evals analyze the recent conversation history and update a rich internal state model stored per-chat session in the SQLite database (`sessions` table in `lib/database/database.dart`).

The core evaluation logic lives in `lib/services/chat_service.dart` (methods such as `_evaluateRelationshipCall`, `_evaluateEmotionalStateCall`, `_evaluatePhysicalStateCall`, `_evaluateNarrativeCall`, `_evaluateOneShotCall`, `_checkClimaxInResponse`, and `_applyMoodDecay`). A companion `lib/services/expression_classifier.dart` (via `LLMExpressionClassifier` and `ONNXExpressionClassifier`) helps map the nuanced emotions produced by the eval LLM into the 30 standard expression labels used for sprite/expression image matching.

Key tracked dimensions (all persisted and injected back into future prompts):

- **Bond** (short-term tension `-300`…`+300` and long-term bond `-300`…`+300`)
- **Trust** (`-100`…`+100`)
- **Emotion** (nuanced word + mild/moderate/strong intensity)
- **Arousal** (`-100`…`+100`) + NSFW refractory cooldown
- **Time of day** + day count (deterministic, advances every 6 turns unless the LLM vetoes)
- **Fixations** (intrusive persistent thoughts, 3-turn lifespan)
- **Spatial stance** (current physical posture/location)
- **Chaos pressure** (for Chance Time events)
- **Primary objectives** (quest-like goals)

These values are turned into rich OOC prompt injections (`_getRelationshipInjection`, `_getEmotionInjection`, `_getBehavioralMechanicsInjection`, `_getTimeInjection`, `_getTrustBehaviorInjection`, `_getNsfwCooldownInjection`) so the *next* generation respects the character's current emotional reality. The main character personality always takes precedence — realism only colors how that personality expresses itself.

**What you experience:**

- Characters remember how they *feel* about you. A single act of kindness can warm them for dozens of turns; a betrayal can poison the relationship for a long time.
- Emotions have **inertia** — they linger after intense moments instead of snapping back to neutral.
- The world has a sense of time and place. Lighting, atmosphere, and the character's physical position evolve naturally.
- Relationships feel earned. Short-term mood fluctuates quickly; long-term bond grows (or erodes) slowly from sustained patterns.
- Mature scenes have realistic pacing thanks to the arousal + cooldown system.
- Unpredictable drama via Chaos Mode ("Chance Time").

**It's completely optional.** The master toggle defaults to **off**. You can enable it globally, per-character (as a default for new chats), or manage it on a per-chat basis. When disabled, none of the extra LLM eval calls happen and chats behave like a traditional character AI.

---

## Enabling & Disabling

The Realism Engine can be controlled at three levels:

### 1. Global Default (Settings)

Go to **Settings → Realism Mode** (or search for "Realism" in the settings page).

- **Enable Realism Mode** (teal switch) — master toggle. When on, new chats inherit the sub-toggles below.
- **NSFW Cooldown** — tracks physical arousal and enforces a refractory period after intimate climaxes (highly recommended for mature RP).
- **Automatic Passage of Time** — lets in-universe time advance (dawn → morning → afternoon → evening → night) as you chat. Also enables spatial awareness even if the master time clock is off.

These defaults are stored in `StorageService` (`lib/services/storage_service.dart`) and applied to every new session unless overridden by a character card.

### 2. Per-Character Default (Character Editor / Creator)

When creating or editing a character (Manual Creator, AI Creator, or Edit Character page):

- Step 4 is the **Realism Engine** panel (powered by the shared `RealismFormSection` widget in `lib/ui/widgets/realism_form_section.dart`).
- Toggle "Enable Realism Engine" for this character.
- Set **initial state** for a new conversation:
  - Time of day and day count
  - Short-term bond and long-term bond (`-300` to `+300`)
  - Trust level (`-100` to `+100`)
  - Starting emotion + intensity
  - Whether NSFW Cooldown and/or Chaos Mode start enabled
  - An optional initial "Current Task" (Primary Objective)

These values are saved inside the character's `extensions.front_porch.realism_engine` JSON (see `FrontPorchExtensions` in `lib/models/character_card.dart`). They only seed **brand-new** conversations — existing chats keep their own persisted session state.

### 3. Per-Chat / In-Session Controls

- Once a chat is running, the current realism state lives in the `sessions` row in the database and survives app restarts and swipes/regenerations.
- The master realism flag for the active session can be flipped at runtime via `ChatService.setRealismEnabled()` (exposed in UI through the global setting or chat-specific menus).
- **One-Shot Eval (Experimental)** toggle appears in the chat settings drawer (and is also available in Settings). It fuses multiple realism evals into a single LLM call for much faster processing at the cost of slightly lower accuracy on small models.
- Chaos Mode and other sub-features can be toggled per-session via `setChaosModeEnabled`, `setNsfwCooldownEnabled`, and `setPassageOfTimeEnabled`.

**Tip:** Turning realism *on* mid-chat triggers a retroactive baseline eval (`_runRetroactiveBaselineEval`) against visible history so the engine catches up instantly.

---

## Bond Tracking

Bond is the heart of the relationship system and comes in two layers that evolve on very different timescales.

### Short-Term Bond (Tension)

- **Range:** `-300` (vitriolic hatred) to `+300` (utter devotion)
- **Tier names** (21 tiers, calculated in `_calculateTier`): Devoted / Enamored / Intimate / Close / Amiable / Friendly / Warm / Receptive / Neutral … all the way down to Vitriolic / Contempt / Disdain / Hostile / Adversarial / Broken Trust.
- Changes rapidly from the relationship eval (`_evaluateRelationshipCall` or the fused one-shot). The LLM is instructed to give small deltas (`±1`–`±5`) for normal interaction and only large deltas (`±10`–`±50`) for truly meaningful moments.
- **Inertia & decay:** Every 10 turns the short-term score drifts 1 point toward zero (`_applyMoodDecay`). This prevents relationships from being permanently stuck at extremes.
- **Effect on generation:** The `_getRelationshipInjection()` block tells the model exactly how open, warm, sarcastic, cold, or hostile the character currently feels. The character's core personality is never overridden — a naturally tsundere character at +200 bond will still be tsundere, just warmer and more vulnerable than usual.

### Long-Term Bond

- Same numeric range (`-300`…`+300`) and tier names (Soulmate / Life Partner / Deeply Attached … Fractured / Deep Resentment … Vitriolic).
- Grows (or shrinks) much more slowly via `_evalLongTermGrowth`, which is called periodically. Sustained high short-term tiers (≥7) cause +2 or +3 long-term points every few turns; sustained negative tiers erode it.
- Once earned, long-term bond is extremely sticky. A character with high long-term bond will retain underlying affection even during a short-term fight.
- Used in prompt guidance to describe "unbreakable commitment" or "deep-seated resentment that even positive short-term mood can't fully erase."

Both scores are shown in the message metadata chips (pink heart for bond deltas) when they change, and the current tier names appear in the relationship OOC note injected into every prompt.

---

## Trust System

Trust (`-100`…`+100`) is deliberately distinct from bond:

- **Bond** = "How does this character *feel* about me emotionally right now?"
- **Trust** = "How safe and reliable does this character judge me to be?"

Trust deltas come from the same relationship eval but are much more conservative (the LLM prompt heavily penalizes large swings except for extraordinary acts). Only the *user's* behavior moves trust — the character's own actions never do.

**Tier names** (via `trustTierName`):
- Positive: Blind Trust, Implicit Trust, Deeply Trusting, Confident Trust, Trusting, Leaning Positive, Cautious, Neutral…
- Negative: Guarded, Skeptical, Wary, Suspicious, Distrustful, Paranoid, Broken Trust, etc.

**Behavioral impact** (`_getTrustBehaviorInjection`):
- ≤ `-50`: Deeply distrustful/paranoid — questions every motive, evasive, assumes the worst.
- `-20` to `-5`: Skeptical/Guarded/Cautious — surface-level talk, tests intentions.
- `0`: Truly neutral (personality wins).
- `+30`–`+50`: Deep trust — mask is down, shares real feelings, vulnerability that is authentic to *this* character's personality.
- `+60`+: Rare "you are the only person I would ever tell this to" level.

**Trust Repair Window:** Any single-turn trust drop of `-20` or worse arms a special `_pendingTrustRepair` flag. On the *very next* user message the engine runs a dedicated trust-repair eval (`_runTrustRepairEval`) that scores how convincingly the user addressed the breach (0–60 recovery points). The character then reacts accordingly — a heartfelt, personality-appropriate apology can recover a lot; a glib "sorry" usually gets rejected.

Trust state is saved per session and restored on swipes/regens.

---

## Emotion States

Every turn (when realism is active) the engine runs an emotion evaluation (`_evaluateEmotionalStateCall` or fused in one-shot) that produces:

- A **nuanced emotion word** (never generic "happy" — the prompt demands "wistful", "flustered", "prickly", "smoldering", "guarded", "starstruck", etc., filtered through the character's personality)
- An **intensity** (`mild` / `moderate` / `strong`)

**Emotion inertia** is explicitly encouraged in the prompt: minor exchanges cause only small drift; after fights, confessions, or intimate moments the emotion is allowed (and instructed) to linger for several turns.

The current emotion is injected via `_getEmotionInjection()` so the model colors tone, body language, and word choice appropriately.

**Expression images / sprites:** When the Expression feature is also enabled, the Realism Engine's nuanced emotion is mapped to one of the 30 standard go-emotions labels (`lib/utils/emotion_labels.dart`) using `EmotionLabels.nuancedToStandard`. If the word isn't in the map, `LLMExpressionClassifier` (in `expression_classifier.dart`) triggers a quick reclassification call to pick the closest standard label. This drives the correct animated portrait.

Emotions are persisted in the session row (`characterEmotion`, `emotionIntensity`) and survive across messages, swipes, and app restarts.

---

## Arousal System

When **NSFW Cooldown** is enabled (a Realism sub-toggle), the engine tracks a separate physical arousal dimension (`-100`…`+100`).

- Arousal deltas are requested in the relationship/emotion/one-shot evals (with bold guidance: intimate moments should produce `+10` to `+25`).
- The value is **not** "progress toward orgasm" — it is current *desire and physical response*. The prompt explicitly tells the model: "High arousal = intensely turned on, NOT that they are about to climax."

**Arousal tier names** (via `arousalTierName`, 21 tiers from -10 to +10):
Completely Unaroused, Physically Neutral, Mildly Flustered … Heavily Aroused, Overwhelmed with Desire, Peak of Physical Arousal.

These descriptions (phrased for the specific tier) are injected into the prompt via `_getNsfwCooldownInjection()` so the model knows exactly how the character's body is reacting and how they would (or would not) escalate.

**Refractory Cooldown (the "NSFW Cooldown" feature):**

After the AI finishes a response, `_checkClimaxInResponse` runs a post-generation LLM call that scans the text for an organic climax. If one is detected:

1. The LLM is asked how many turns of refractory period this particular character would realistically need (personality-aware, 1–8 turns).
2. Arousal is slammed to `-3`.
3. `_cooldownTurnsRemaining` and `_cooldownTurnsTotal` are set.
4. Every subsequent turn the counter decrements (`_applyMoodDecay`).

While the counter > 0, the prompt injection describes the current recovery *phase* in vivid, non-mechanical language (oversensitive, blissfully wrecked, needing non-sexual closeness, etc.). The character will naturally reject or deflect further sexual escalation until recovered.

Climax state is stored in message metadata so swipes/regenerations can correctly restore or revert the cooldown.

When NSFW Cooldown is disabled, arousal tracking is still available for flavor but no refractory is enforced.

---

## Passage of Time

When **Automatic Passage of Time** is enabled:

- A simple deterministic clock runs: every AI turn increments `_turnsSinceLastTimeAdvance`.
- After **6 turns** (configurable constant `_turnsPerTimePeriod = 6`), the engine considers advancing the time of day.
- The LLM gets a "hold_time" + "new_day" + "posture" eval in `_evaluatePhysicalStateCall`. It can only **veto** the advance if the scene is visibly mid-action (fighting, actively doing something important). It cannot skip periods.
- At night → dawn it increments the day counter.
- Explicit "we slept / woke up / new day started" lines in the conversation can force a day rollover.
- The current time + narrative weekday (computed from session start day-of-week + elapsed days) is injected via `_getTimeInjection()` so the model describes appropriate lighting, atmosphere, fatigue, etc.

**When Passage of Time is disabled** but realism is still on, the physical-state eval still runs on a lighter cadence to keep **spatial awareness** (`_spatialStance`) updated — the character remembers "I'm sitting on the windowsill" or "we're standing in the rain" and the model is told to keep actions grounded.

Time state (`timeOfDay`, `dayCount`, `passageOfTimeEnabled`) is persisted per session.

---

## Chaos Mode (Chance Time)

Chaos Mode (also called "Chance Time") is an optional drama engine that injects unpredictable narrative events.

**How it works:**

- Every user turn, `checkAndTickChaosPressure()` runs (only in 1:1 chats).
- Pressure starts at 0 and grows by **5** each turn (capped at 100).
- Effective trigger chance = `5% + current pressure`.
- When it fires, `sendMessage` pauses, a `Completer` is created, and the UI shows the Chance Time wheel overlay (`_chanceTimePendingTrigger`).
- The wheel calls `spinWheelEvents()` which samples 8 events from two pools:
  - `_chanceTimeEventPool` (~120 wholesome/fortune/mishap/drama events)
  - `_chanceTimeNsfwPool` (only if the 🌶️ "Include NSFW events" toggle is on)
- User spins, lands on one, and calls `applyChanceTimeResult(event, charName)`.
- The chosen event is stored as `_pendingChaosInjection` and injected at the very end of the next prompt (`_getChanceTimeInjection`) with strong instructions: the character **must** react to it in their first paragraph.
- The injection is cleared after use but the "delivered" flag ensures it survives one regen/swipe cycle.

Pressure resets to 0 after an event fires. You can also manually trigger the wheel from the UI when the mode is active.

Events are written so they feel like natural story beats ("{{char}} just received an extremely personal delivery in front of other people", "A stranger just paid for {{char}}'s meal…", etc.). The model is forbidden from mentioning "Chance Time" or game mechanics.

Chaos state (`chaosModeEnabled`, `chaosNsfwEnabled`, `chaosPressure`) is saved per session.

---

## Character Evolution

Character Evolution is a *periodic* companion system (not per-turn) that lets characters grow and change over long conversations. It is controlled separately in Settings ("Character Evolution") but is frequently used together with the Realism Engine.

- Every N user messages (default 10, same interval as auto-persona fact extraction) the engine runs `_runPeriodicEvalsInSequence`.
- Step 2: `_triggerCharacterEvolution` sends a background LLM call that proposes personality and/or scenario updates based on everything that has happened.
- The evolved text is stored per-character (or per-character-in-group) in the session and merged into future system prompts.
- Evolution count is tracked and shown in the character summary.
- Changes are **permanent for that chat** (they live in the `evolvedPersonality` / `evolvedScenario` columns and the group maps).

You can enable/disable it independently of Realism. When both are on, the evolving personality interacts beautifully with the emotional state tracking.

---

## Fixation Engine

The Fixation Engine gives characters *lingering obsessions* — thoughts that won't leave them alone.

- During the narrative / one-shot eval (`_evaluateNarrativeCall` or `_evaluateOneShotCall`), the LLM can propose a `"fixation_topic"` — something emotionally charged that the character keeps returning to (a hope, worry, memory, ambition, regret…).
- If the topic is new and non-"none", it becomes `_activeFixation` and `_fixationLifespan` is set to **3**.
- Every subsequent turn the lifespan decrements. When it hits 0 the fixation is cleared.
- While active, `_getBehavioralMechanicsInjection` adds a gentle OOC note: the character has this intrusive thought; it may color their mood or surface if the conversation naturally touches the topic. It never overrides their current focus.

Fixations make characters feel like they have an inner life that continues between scenes. They are especially powerful when combined with long-running story arcs or Chaos events.

---

## NSFW Cooldown

Covered in detail in the Arousal System section above. In short:

- When enabled, arousal is tracked and a personality-aware refractory period (1–8 turns) is enforced after the LLM detects a natural climax in the AI's response.
- During cooldown the prompt tells the model exactly how physically spent and oversensitive the character is, preventing unrealistic immediate re-escalation.
- The system is deliberately "show, don't tell" — the model never sees the words "cooldown" or "turns" in dialogue.

This is one of the most praised features for mature roleplay because it gives sex scenes realistic emotional and physical aftermath instead of endless escalation.

---

## One-Shot Eval Mode

By default the Realism Engine performs up to four separate LLM evaluation calls after each turn (relationship, emotional state, physical/time, narrative). On slower local backends (especially KoboldCPP) this can add noticeable latency.

**One-Shot Eval** (Settings → Realism or the toggle in the chat drawer) is an experimental optimization:

- When enabled, `ChatService` calls `_evaluateOneShotCall` instead.
- A single, carefully crafted prompt asks the model to return *all* the fields at once: relationship_delta, trust_delta, emotion, intensity, arousal_delta, posture, proposed_objective, fixation_topic, and reason.
- This cuts the number of pre-generation blocking inferences roughly in half.

**Trade-offs:**
- Slightly lower accuracy on very small models (< 8B) that struggle with long combined instructions.
- Still produces excellent results on 12B+ models.
- GBNF grammars are intentionally disabled for all realism evals (including one-shot) because many KoboldCPP setups return empty strings when a grammar cannot be satisfied — the engine falls back to regex parsing of the raw text, which is robust.

Most users leave it off for maximum fidelity and only enable it when they need maximum speed.

---

## Performance Considerations

The Realism Engine is deliberately lightweight compared to the main chat generation, but it does add work:

- **Extra LLM calls**: Normally 2–4 short eval inferences per user turn (plus an occasional post-generation climax check). Each eval prompt is kept short (last 3–6 messages only) and the model is told to output *only* a tiny JSON object.
- **Token overhead**: The various OOC injection blocks (`relationship`, `emotion`, `time`, `trust`, `arousal`, `fixation`, `spatial`) typically add a few hundred tokens at most. They are included in the context budget calculation so they never push your history out of the window.
- **Local backend impact**: KoboldCPP is single-threaded, so realism evals are run sequentially (with cancellation support). On a fast GPU this is usually < 1–2 seconds per eval. On CPU or very slow setups the "Reading the room…" overlay can stay up for several seconds.
- **One-Shot Eval**: Halves the number of calls. Recommended when you value responsiveness over perfect granularity.
- **Disabling for speed**: Turn the master Realism toggle off in Settings (or per-chat) when you just want fast, lightweight chatting. No evals run at all.
- **Known KoboldCPP gotcha**: GBNF-constrained JSON output was tried extensively but frequently produced empty responses on many models. All realism evals now use unconstrained generation + robust regex extraction, which has proven far more reliable across the ecosystem.

The engine is heavily optimized: evals only run when realism is enabled, only for 1:1 chats (group chats skip most of it), and cancellation is supported at every stage so you can interrupt a slow eval and regenerate.

---

## Troubleshooting

### "Realism evaluation interrupted" or empty responses

- The most common cause on KoboldCPP is the (now-disabled) GBNF grammar. The current code intentionally omits the grammar parameter for all realism calls.
- If you still see frequent empty evals, try a different model or slightly increase the eval max tokens (rarely needed).
- Use the **Cancel** button that appears in the processing overlay — it cleanly aborts the current eval stream.

### Bond / Trust / Emotion not changing

- Make sure the master Realism toggle is actually on for that chat.
- Very small or heavily quantized models sometimes ignore the eval instructions. Larger or better-instruction-tuned models produce more reliable deltas.
- Normal conversation is *supposed* to produce mostly 0 or tiny deltas. Only meaningful moments should move the needle.

### Time not advancing

- Check that "Automatic Passage of Time" is enabled both globally and for the session.
- The LLM can legitimately hold time if the scene is mid-action (the eval explicitly asks for `"hold_time": true` in that case).
- After ~6 turns the advance attempt will be retried.

### Fixation or arousal state feels stuck

- Fixations naturally expire after 3 turns.
- Arousal/cooldown state is restored correctly on swipes because it is stored in message metadata. If something looks wrong, regenerate or swipe the last message.

### How to completely reset realism state for a chat

1. Start a new chat with the same character (the initial state from the card will be used).
2. Or manually edit the session row in the database (advanced users).
3. Regenerating the greeting or using "New Chat from this point" will usually give you a clean slate while preserving history.

### Performance is terrible / evals take forever

- Enable **One-Shot Eval**.
- Use a faster backend (OpenRouter / OpenAI / Groq / local with good GPU).
- Disable realism entirely for that chat.
- Make sure you are not running multiple heavy local processes at once (KoboldCPP + embed server + TTS, etc.).

### Realism state disappeared after an app update or migration

The engine has gone through several schema versions (REv2, REv3). The code contains explicit migration paths (`_migrateShortTermScore`, legacy session loading, etc.). If you see obviously wrong numbers, start a fresh chat with the character — the V2.5 card extensions will give you a clean modern baseline.

---

**The Realism Engine is what makes Front Porch AI special.** It turns "talking to an AI" into "living with a character who has a real relationship with you that grows, breaks, heals, and changes over time." Take the time to leave it on for a few long sessions — the difference is night and day.

---

