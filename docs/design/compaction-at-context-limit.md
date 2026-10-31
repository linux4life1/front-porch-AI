# Compaction at the context limit — statement of work

Draft 1, 2026-10-23 (supersedes the "prompt budget degradation ladder" drafts, withdrawn the same day). Status at the end. Nothing here is built.

The question is what happens to a long chat when it hits the context limit. The transcript loses its oldest messages, the recap is supposed to hold what fell out, and today there is a gap between the two: the recap is rewritten on a fixed cadence, not when messages leave the window. This scopes closing that gap the way an agent compacts near its own limit: when a send is about to lose messages the recap has not read, rewrite the recap first. 16K is the minimum supported context; nothing here is about small windows, and no block in the prompt shrinks.

## What the engine does today (from the code)

| Finding | Evidence |
| --- | --- |
| The history budget is the context minus the fixed blocks and the reply reserve. The walk keeps the newest messages that fit and drops the rest from the oldest end, in chunks of 8. | `kHistoryTrimChunk`; `_buildChatHistoryWithBudget` |
| The window start is a high-water anchor: once the chat has dropped N messages, later turns do not creep back below N unless the budget grows by a quarter. Local prefix caches stay valid. | `_HistoryAnchor` in `chat_service_history.dart` |
| The recap is a model-written account of the chat up to a cursor (`_summaryLastIndex`), rewritten by the Journal pass. The pass runs every `journalInterval` user messages (default 10) or on a salient event kick. Nothing ties it to messages leaving the window. | `_maybeRunJournalPass` in `chat_service_turn_flow.dart` |
| The pass reads a bounded tail from the cursor, so a cursor left far behind is caught up in bounded steps; the recap owner is whichever character's call comes back first. | `journal_maintenance.dart` window cap and recap-owner comments |
| The recap is dropped only when every message is visible; it stays whenever anything was dropped. | `recapIsRedundant` |
| A send that dropped messages triggers RAG retrieval of dropped windows by a cued query, when RAG is on and the engine is operational. Otherwise a warning is logged and nothing is retrieved. | `chat_service_generation_rag.dart` |
| Objectives, Journal cards, Growth rings and the world are not in the transcript. Trimming and compaction cannot evict them; the goal check reads the full in-memory message list, not the trimmed window. | `objectives` table; `doors/objectives/objective_completion_check.dart` |
| Continue budgets as the send before it did and drops nothing new. | `_stripContinuePlanSections` runs after the count |

**The gap.** Between two passes, up to the interval's worth of exchanges can fall out of the window before the recap has read them. With RAG off they are gone until the next pass; with RAG on they come back only as retrieved windows, by query, not as story.

## What changes and what stays

One new reason for the recap to be rewritten: a send whose walk dropped messages at or past the recap cursor. The rewrite covers the window from the cursor to the drop point, so the next send carries those messages in compressed form.

Stays: the interval and the event kick; the pass's prompt, its owner rule, its bounded window and its cooling; the trim chunk and the anchor; RAG's retrieval on drop; every block in the prompt at its current size; the recap redundancy gate.

## 1. The trigger

After the reply, where `_maybeRunJournalPass` already runs: if this send's walk reported `droppedMessages` and `basePosition + droppedMessages > _summaryLastIndex`, a recap rewrite is due regardless of the interval count. It runs on the same non-blocking path as today's pass, never competing with the main call, and is guarded by the same re-entrancy and session checks.

## 2. Recap only, not the whole pass

The maintenance pass also reviews and cools Journal cards, and Growth deliberately keeps its own cursor because the Journal's "per-pass cooling is tuned to journalInterval" (`growth_service.dart`, `chat_service_wiring_memory.dart`). Running the whole pass on every drop would change card cooling on every long chat. So the trigger asks for a recap rewrite only: the same window and prompt, with card operations held, or a recap-only prompt if the pass cannot be split. Whether `runMaintenancePass` can run in a recap-only mode is the first thing to establish in the implementing conversation; the cursor still advances, so the next interval pass reads from the new cursor and does the card work over the same window it would have anyway.

## 3. Rate

A long chat at the limit drops a chunk every few turns. One rewrite per drop event is the ceiling; the pass's own guard against overlapping passes and the cursor (a drop that lands behind the cursor queues nothing) keep it there. A Continue never queues one.

## Open questions for the maintainer

1. When RAG is on and operational, is the recap rewrite still wanted on every drop, or only when RAG is off? (Recommended: always. Retrieval brings back windows by query; the recap is the story.)
2. Should the rewrite also fire when a send is *about* to drop past the cursor on the next turn, so the recap is ready before the loss rather than one turn after? (Recommended: no for v1. The one-turn lag is the current gap minus nine exchanges; predicting the next walk adds a second budget pass.)

## Tests

Guards proven red then green, appended to the Journal maintenance tests: a send that drops past the recap cursor queues a recap rewrite and one that drops behind it does not; the rewrite touches no card and no Growth ring; Continue never queues one; two drops in a row queue one rewrite while the first is running. One journey on a real `ChatService` against the loopback backend: a chat long enough to drop at 16K, asserting the recap carries the lines that fell out on the send after the drop.

## Desktop and web

No UI change. The recap is already shown in the sidebar and the web app's Journal panel.

## Status

- 2026-10-23: the degradation-ladder drafts proposed shrinking prompt blocks on small contexts. The maintainer ruled the world block, the recap and the objectives out of any ladder, and the trace found a reader behind every remaining rung (RAG dedup for the Journal cap, the four non-realism fragments for a realism cut, regen determinism for sticky state). The maintainer then said small contexts were never the question and 16K is the minimum supported; the question is the context limit. This draft replaces the ladder with the one mechanism that addresses it. Awaiting the maintainer's word on the open questions.
