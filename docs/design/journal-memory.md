# The Journal — Unified Emotional Memory System

**Status:** Approved design, locked 2026-07-02. **Fully shipped on `Rawhide`** — phase 1 (core) 2026-07-02, phase 2 (emotional physics, `journal_physics.dart`) 2026-07-03, phase 3 (Journal UI: `journal_panel.dart` + `journal_dialog.dart` + `journal_card_editor.dart` + tap-to-jump receipts) 2026-07-03, phase 4 (tool transport + review-first: `journal_review.dart` + `journal_prompt.dart` + `LLMService.generateWithTools`) 2026-07-03.
**Replaces:** `SummaryService` (periodic chat summaries) and `FactExtraction` (auto persona facts) — both deleted.
**Prior art:** LettuceAI's memory system (AGPL-3, heat/pin/decay concepts adapted) + self-authored journal concept.

---

## 1. One-line pitch

Characters keep a set of small, self-authored memories — each stamped with *how it felt* at the moment it happened — that warm and cool with use and render as a diary the user can read, edit, and pin. Memories live strictly inside the chat where they happened.

## 2. Why

The previous stack ran two overlapping background jobs (fact scraping + chat summaries) whose outputs were invisible to the user and blind to emotion. The Journal collapses them into **one maintenance pass** producing two artifacts, and makes memory legible, editable, and emotionally weighted — the thing that differentiates a companion app's memory from a coding assistant's RAG.

## 3. Locked decisions

| Decision | Choice |
|---|---|
| Memory scope | **Per-chat, per-character** (revised 2026-07-02, supersedes the earlier cross-chat choice). **No memory ever leaks between chats.** Every chat is its own sealed world; within a group chat, each member keeps her own diary of that chat. This matches the existing session scoping of summaries and RAG embeddings. |
| Per-chat opt-out | **Not needed.** Isolation is total by design, so the previously planned "standalone story" flag (and its `Sessions.journalStandalone` column) is dropped entirely. |
| Old learned-facts feature | **Ripped out entirely, fresh start.** No migration. `Personas.learnedFacts` DB column stays dormant (no destructive migration); all code/UI/settings for it are deleted. Persona text itself is unaffected. |
| User-facing name | **"The Journal."** The per-chat recap is **"Where we are."** |

## 4. Architecture

### 4.1 The two artifacts

- **Memory cards** (scoped per character *per chat*): atomic first-person memories.
  Each card carries: text, category (`about_user` / `about_us` / `moment` / `promise`), **emotion label + intensity at formation**, optional revised emotion (see "feelings that heal"), heat, access count, pin flag, provenance (source message ids), optional embedding.
- **The recap** (chat-scoped): a short "where we are" paragraph in the character's voice, written from the hot cards + recent events. **Stored in the existing `Sessions.summary` column** so the prompt-injection plumbing, sidebar display, and `EvolutionService`'s summary dependency keep working unchanged.

### 4.2 The maintenance pass (the one background job)

- **Cadence:** interval-based (like the old periodic evals), **plus** an immediate trigger when a significant event fires.
- **Salience is deterministic, not judged:** input messages are pre-annotated with engine-stamped metadata that already exists per message — `bond_delta`, `trust_delta`, `trust_repair_*`, `chance_time_event`, objective completion, climax/catastrophe flags, and `emotion_label`/`realism_state`. The engine highlights the memorable lines; the model just writes them down in character.
- **Edit-in-place, never wipe:** the pass receives current cards (hot set) + current recap and emits *operations* — add / revise / retire / pin — plus a new recap. Retired cards are deleted from the card set only; the raw transcript remains in RAG (nothing is ever truly lost).
- **Emotional imprint is read, not asked:** a new card's emotion/intensity comes from the source messages' recorded `emotion_label` + intensity — the feeling the Realism Engine actually computed at that moment. No new eval, deterministic, works on any model.
- Runs on `LlmEvalEngine` plumbing: reasoning forced off, `<think>`-block stripping as backstop (GLM/Kimi/DeepSeek-safe), retry/cancel included.

### 4.3 Transports (one applier, two front doors)

- **XML-tag transport (default, all models):** the pass emits forgiving tagged text (`<memory action="add" ...>…</memory>`, `<recap>…</recap>`) parsed by regex — same trick the realism evals use to dodge the local-model empty-JSON gotcha.
- **Tool-calling transport (phase 4):** capable models emit real tool calls (`add_memory`, `pin_memory`, …).
- Both produce the same internal operations list executed by one shared applier. No forked logic.
- **Review-first mode (phase 4, optional toggle):** proposed operations are shown to the user before committing.

### 4.4 Emotional physics (deterministic code, no LLM judgment)

- **Flashbulb decay:** intensity controls cooling. `mild` decays at the normal rate, `moderate` slower, `strong` barely at all. Pinned never decays.
- **Mood-congruent recall:** retrieval scoring boosts cards whose emotion matches the character's *current* emotion, matched by emotion family via `EmotionLabels.nuancedToStandard` (sad ↔ melancholy ↔ grief).
- **Heat lifecycle:** new cards start hot (1.0); each pass cools unpinned cards by their intensity-modified decay rate; retrieval into context re-warms a card and bumps `accessCount`/`lastAccessedAt`. Below the cold threshold a card leaves the always-injected hot set but stays semantically searchable. A per-character max-cards cap trims the coldest unpinned cards.
- **Feelings that heal:** the pass may revise a card's emotion as the relationship evolves; the original emotion is preserved on the card ("this used to make me sad — now I'm proud of him").

### 4.5 Pipeline placement

**Read path (every turn):**
system prompt → scenario → recap ("Where we are") → **Journal block: pinned + hot cards with their feelings** → semantically retrieved cold cards & raw-transcript RAG (mood-congruent boost) → recent messages → generate.

The Journal block is a new prompt-injection builder alongside the existing eight in `lib/services/prompt_injection/`. Hot-card injection is token-budgeted and requires **no embeddings** — without the sidecar, the Journal still fully works (recap + hot/pinned cards); only cold-card semantic search needs embeddings.

**Write path (post-generation):** realism evals → needs checks → chips → RAG embedding → **Journal maintenance pass** (slotting where fact-extraction + summary fired, reusing the periodic-evals interval machinery and `Sessions.summaryLastIndex` as the pass cursor).

### 4.6 Groups — parity by construction

Cards are keyed per character: each group member keeps her own diary and her own feelings about the same event. Emotion stamps are already per-speaker in group metadata. One shared recap per chat; the pass runs per character over that character's turns. Same code path in 1:1 and group — parity is structural, not audited-in.

## 5. Storage (additive only)

New Drift table `JournalMemories` (does not touch any table Character Card Forge writes):

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `sessionId` | TEXT | indexed; **the scoping key — cards never cross chats** |
| `characterId` | TEXT | indexed; the diary owner within that chat |
| `sourceMessageIds` | TEXT? | JSON array — tap-to-jump receipts |
| `content` | TEXT | the memory, first person |
| `category` | TEXT | `about_user` / `about_us` / `moment` / `promise` |
| `emotionLabel` | TEXT? | current feeling |
| `emotionIntensity` | TEXT? | mild / moderate / strong |
| `originalEmotionLabel` | TEXT? | set only when the feeling was later revised |
| `heat` | REAL | default 1.0 |
| `accessCount` | INT | default 0 |
| `pinned` | BOOL | default false |
| `embedding` | BLOB? | + `dimensions` INT default 0 (DataBankEntries pattern) |
| `createdAt` / `lastAccessedAt` / `updatedAt` | DATETIME | |
| `metadata` | TEXT? | JSON pouch for future additive needs |

No `Sessions` schema change. Recap reuses `Sessions.summary` + `Sessions.summaryLastIndex` (no change). Deleting a chat cascades to its journal cards (wired into the existing cleanup path in `database_cleanup.dart`).

## 6. Settings

New keys in `MemorySettings` (old `summary_*` and `auto_persona_*` accessors deleted; stale prefs harmless):

- `journal_enabled` — default **true** (flagship feature; works out of the box)
- `journal_interval` — default 10 user messages, clamp 3–50
- `journal_max_cards` — default 200 per character, clamp 50–1000
- `journal_review_first` — default false (phase 4)

Tunable constants (code, not settings, until proven needed): hot-set token budget (~600), base decay per pass, intensity decay multipliers, cold threshold, mood-congruence boost.

## 7. Deletions (the consolidation payoff)

- `lib/services/chat/summary_service.dart` — recap generation absorbed into the pass.
- `lib/services/chat/fact_extraction.dart` — including the 13-regex garbage gate (engine-annotated salience replaces guessing).
- Learned-facts surface in `UserPersonaService` (add/dedup/relevance/cleanup), `_buildUserPersonaBlock`'s facts injection, facts UI in `user_persona_dialog.dart` / `user_persona_page.dart`, `auto_persona_*` + `summary_*` settings and their settings-UI rows.
- Dead code: `MemoryService.storeNeedsEventMemory` / `retrieveSalientNeedsEvents` (never called; superseded).
- The sidebar Summary section is repointed at the recap ("Where we are") in phase 1 and folded into the Journal UI in phase 3.

## 8. Build phases (each leaves the app fully working)

1. **Core (shipped):** `JournalMemories` table + regen; journal store + maintenance pass (XML transport); recap into existing slot; Journal injection block; chat-deletion cascade; all §7 deletions; settings swap.
2. **Physics (shipped):** heat/decay/pin, flashbulb resistance, mood-congruent retrieval boost, event-triggered passes (bond/trust swing ≥ 12, trust repair, Chance Time, objective completion), max-cards trim by lowest heat, embedding of cards + cold-card semantic retrieval, first-pass cap (trailing 50 messages on a virgin journal). All constants + pure math in `journal_physics.dart`.
3. **The Journal UI (shipped):** sidebar peek (`journal_panel.dart`, per-member in groups via the focused participant) + full diary dialog (`journal_dialog.dart`) — read grouped by category, edit, pin, retire (with confirm), "plant a memory" (`journal_card_editor.dart`), emotion chips (existing emoji map via the physics family mapping), faded-state marker; recap editor shipped in phase 1 (SummarySection). *Receipts:* a "where this came from" viewer quoting the cited lines; tapping a line closes the journal and scrolls the chat to that message (`message_jump.dart` — bubbles keyed with `GlobalObjectKey`, proportional first hop + viewport paging until the target builds, `ensureVisible` centering, brief highlight tint). No scroll package needed.
4. **Polish (shipped):** tool-calling transport + review-first mode.
   - *Tools:* `LLMService.generateWithTools` (default null = unsupported). `OpenRouterService` implements it non-streaming over the shared payload builder; KoboldCpp + PseudoRemote implement it via the shared `postOpenAiChatWithTools` (openai_chat_stream.dart) — local tool calling enabled per user decision 2026-07-03 (Qwen3-class models handle it well; recent KoboldCpp supports OpenAI tools). `kJournalTools` schemas + `parseJournalToolCalls` in journal_ops normalize to the same `JournalOp` list (one applier, two front doors, §4.3). The pass probes tools once per backend+model identity per run (`_runExchange`; the local model path rides the identity so swapping GGUFs re-probes), salvages XML tags out of a text-only reply, and remembers XML-only models — at most one extra round trip each. The §9 local floor holds: a non-tool-calling GGUF costs one probe, then journals over XML exactly as before.
   - *Review-first:* `journal_review_first` setting (default false; toggle in the recap section's gear). The pass resolves ops into id-addressed proposals (`journal_review.dart`) and parks them instead of applying; the sidebar shows a review banner → checkbox dialog → Apply commits the accepted set through the SAME applier normal mode uses, Discard settles the window without writing. A parked batch blocks further automatic passes (force regen re-proposes), is strictly session-guarded, and is lost harmlessly on restart (the cursor never moved). Desktop-only surface; the web UI intentionally has no toggle for it.

## 9. Invariants

- **1:1 ↔ group parity** for all observable Journal behavior (CLAUDE.md rule).
- **No data loss:** retiring/trimming cards never touches the raw transcript embeddings; DB changes are additive-only.
- **Local-model floor:** every pathway must work on a non-tool-calling small GGUF (XML transport, prose recap, no reasoning required).
- **Files < 500 lines**, no growth of `chat_service.dart` — new logic lives in `chat/` leaves + a prompt-injection builder.
