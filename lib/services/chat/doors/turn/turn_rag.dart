// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Absolute ceiling on the RAG memories block, applied on top of the
/// percentage budget (1:1's 10% / the group's configurable %). The block is
/// verbatim old transcript injected AFTER the history; past ~2,500 tokens
/// models start replaying it as if it were the current scene, so the cap
/// keeps large-context setups (10% of 32k = 3,200) under that line too.
const int kRagMemoryBudgetCapTokens = 1200;

/// Phase 3 of `_generateResponse`: RAG memory retrieval, the joint
/// memory/history budget trim and the turn's retrieval receipt. The body
/// is the one the generation part held (`x` → `t.x` carrier names, see
/// [GenTurn]); zero behaviour change.
class TurnRag {
  TurnRag(this._a, this._d);

  final PromptAssembler _a;
  final PromptDeps _d;

  ChatSessionState get _session => _d.session;
  StorageService get _storageService => _d.services.storage;
  MemoryService? get _memoryService => _d.services.memory();
  SessionStore get _sessions => _d.doors.sessions();
  RealismGraph get _g => _d.doors.graph();
  PromptHistory get _transcript => _a.history;
  SessionHistoryWindow get _history => _sessions.history;
  GroupMemberSettings get _members => _d.doors.entry().members;
  GroupChat? get _activeGroup => _session.activeGroup;
  bool get _isNewChat => _sessions.isNewChat;
  bool get _clockRunning => _d.doors.controls().clockRunning;
  String get _characterEmotion => _g.registers.emotion;
  RelationshipService get _relationshipService => _g.relationship;
  TimeService get _timeService => _g.time;
  Future<void> _awaitHistoryHydrated() =>
      _sessions.window.awaitHistoryHydrated();

  Future<void> retrieve(GenTurn t) async {
    // ── RAG Memory Retrieval ──
    // When messages are dropped from context, search for relevant past memories
    // Skip retrieval for brand new chats to prevent old memories from interfering
    final effectiveRagEnabled =
        _storageService.memorySettings.ragEnabled &&
        (_activeGroup == null || _members.groupRagEnabled);

    if (_isNewChat) {
      debugPrint('[RAG:Chat] Skipping memory retrieval - new chat in progress');
    } else if (t.mode == GenerationMode.continue_) {
      // Continue extends the same beat. Zeroing droppedMessages used to
      // skip retrieval; tail-open ORs basePosition, so that skip was a
      // no-op on a long chat. Mode itself is the skip.
      debugPrint('[RAG:Chat] Skipping memory retrieval — Continue');
    } else if (t.guestSpeaker != null) {
      // Guest turns answer THIS beat. Guest RAG resurfaces dropped Magus
      // Q&As; a reasoning model treats those as the live question
      // (Discord 2026-08-15: reasoning+RAG = old line; RAG off = latest).
      debugPrint('[RAG:Chat] Skipping memory retrieval — Scene Guest turn');
    } else if ((t.droppedMessages > 0 || _history.basePosition > 0) &&
        _memoryService != null &&
        effectiveRagEnabled) {
      debugPrint(
        '[RAG:Chat] ── Prompt assembly: ${t.droppedMessages} in-window '
        'dropped, base=${_history.basePosition}, triggering retrieval ──',
      );
      try {
        await _awaitHistoryHydrated();
        // Cued query: emotion + fixation + top hot journal line + last
        // words (photo markers ride lastWords via promptText). Recomposed
        // here so Continue's plan-phase pop is visible. Not last-3 alone.
        t.ragQuery = composeRagQuery(
          emotion: _characterEmotion,
          fixation: _relationshipService.activeFixation,
          hotJournalLine: t.ragHotJournalLine,
          lastWords: lastWordsFromMessages(_session.messages),
        );
        final queryMessages = t.ragQuery;
        final reaching = isReachingForQuote(
          lastSpokenLineFromMessages(_session.messages),
        );
        final skipCueLess = !shouldRetrieveRag(
          hasCues: ragHasCues(
            emotion: _characterEmotion,
            fixation: _relationshipService.activeFixation,
            hotJournalLine: t.ragHotJournalLine,
          ),
          reachingForQuote: reaching,
        );

        // Scene Guests Phase 4: a guest turn retrieves the GUEST's own
        // episodic memories (keyed on the guest id), not the host's. The
        // injection format/budget below is shared — only the source id swaps.
        final packed = await _a.ragSources.sourceIds(
          guest: t.guestSpeaker,
          speaker: t.speakingCharacter,
        );
        final sourceIds = packed.sourceIds;
        debugPrint('[RAG:Chat] Memory source IDs: $sourceIds');

        // Session isolation: the speaker/group bucket AND (in groups) every
        // member's LIBRARY identity (originStableId — Data Bank / 1:1
        // embeddings key by portrait basename, never the member UUID).
        // Explicit memorySources for ids that are NOT already group members
        // stay unscoped for opt-in cross-session recall. A memorySource that
        // IS a group member is already in the scoped set (members win /
        // dedupe); that is deliberate anti-bleed. Data Bank never consults
        // this set.
        final sessionScoped = packed.sessionScoped;

        // Retrieval limit: groups use the per-session group setting; 1:1
        // uses the user's "Memories per turn" slider (memory panel + web).
        // The slider was previously DEAD here — 1:1 silently rode the group
        // default (8) and turning it down did nothing. 0 = "All" on both.
        final retrievalLimit = _activeGroup != null
            ? _members.groupRetrievalCount
            : _storageService.memorySettings.ragRetrievalCount;

        final List<RetrievedMemory> rawMemories;
        if (skipCueLess) {
          debugPrint('[RAG:Chat] Skipping memory retrieval — cue-less beat');
          rawMemories = const [];
        } else {
          // In a group, this chat's windows are readable only under the
          // speaker's own key and the old pool; a linked source's windows
          // from THIS chat may be scenes the speaker missed. The wide fetch
          // and filter happen only when such a source is linked at all.
          final readable = packed.readableThisChat;
          final filter =
              readable.isNotEmpty &&
              sourceIds.any((id) => !readable.contains(id));
          final thisChat = _session.currentSessionId ?? '';
          final asked = await _memoryService!.retrieve(
            queryText: queryMessages,
            sourceCharacterIds: sourceIds,
            currentSessionId: thisChat,
            inContextStart: _history.basePosition + t.droppedMessages,
            limit: retrievalLimit == 0 || filter ? 9999 : retrievalLimit,
            characterPriorities: _a.ragSources.prioritiesByMemoryKey(),
            sessionScopedCharacterIds: sessionScoped,
          );
          rawMemories = !filter
              ? asked
              : [
                  for (final m in asked)
                    if (m.sessionId != thisChat ||
                        readable.contains(m.characterId))
                      m,
                ].take(retrievalLimit == 0 ? 9999 : retrievalLimit).toList();
        }
        // Two-tier memory dedupe: the journal expanded these exact lines
        // above — never pay for them twice.
        final afterExpand = RetrievedMemory.excludingPositions(
          rawMemories,
          t.expandedJournalPositions,
          currentSessionId: _session.currentSessionId ?? '',
        );
        // Journal gist already covers this beat — drop extra RAG windows.
        // Facts that left history and have no card still pass (remember).
        final uncovered = dropCoveredRagWindows(
          afterExpand,
          t.journalCoverLines,
        );
        final memories = capRagWindows(uncovered, reachingForQuote: reaching);
        if (memories.length < rawMemories.length) {
          debugPrint(
            '[RAG:Chat] Dropped ${rawMemories.length - memories.length} '
            'retrieval(s) already expanded or covered by the journal',
          );
        }

        // retrieve() awaits checkAvailability first. Only then is
        // isOperational honest — gating on the flag *before* retrieve
        // skipped a cold engine and stamped a fake empty search.
        if (skipCueLess) {
          t.ragReceipt = buildRagReceipt(
            found: 0,
            journalDeduped: 0,
            budgetTrimmed: 0,
            injected: const [],
            days: const {},
            currentSessionId: _session.currentSessionId ?? '',
            status: kRagReceiptSkippedNoCues,
          );
        } else if (_memoryService!.lastRetrieveError != null) {
          t.ragReceipt = buildRagReceipt(
            found: 0,
            journalDeduped: 0,
            budgetTrimmed: 0,
            injected: const [],
            days: const {},
            currentSessionId: _session.currentSessionId ?? '',
            status: kRagReceiptError,
          );
        } else if (rawMemories.isEmpty && !_memoryService!.isOperational) {
          t.ragReceipt = buildRagReceipt(
            found: 0,
            journalDeduped: 0,
            budgetTrimmed: 0,
            injected: const [],
            days: const {},
            currentSessionId: _session.currentSessionId ?? '',
            status: kRagReceiptNotOperational,
          );
        } else if (memories.isNotEmpty) {
          // Cap memory injection to the group's (or global) memory budget % of context.
          // The summary carries the weight of context compression; RAG only
          // supplements with specific details the summary missed. Too much
          // RAG (2500+ tokens) overwhelms the model and causes it to
          // reference stale events as if they're current ("going back in
          // time") — so the percentage is ALSO capped absolutely: 10% of a
          // 32k context is 3,200 tokens, past the documented failure line.
          final contextSize = _storageService.backendSettings.promptContext(
            _storageService.backendSettings.contextSize,
          );
          final budgetFraction = _activeGroup != null
              ? (_members.groupMemoryBudgetPercent / 100.0)
              : 0.10;
          final memoryBudget = math.min(
            (contextSize * budgetFraction).round(),
            kRagMemoryBudgetCapTokens,
          );
          // Day stamps + display order (rag_injection.dart): each line gets
          // its story day so a verbatim Day-2 line can't masquerade as the
          // scene's present and contradict the recap's chronology. PACKING
          // stays in relevance order (retrieve() returns score-descending —
          // chronology must never decide which memories fit the budget);
          // the survivors are then SHOWN oldest → newest.
          final sessionForStamps = _session.currentSessionId ?? '';
          final days = <RetrievedMemory, int?>{
            for (final m in memories)
              m: m.sessionId == sessionForStamps
                  ? storyDayAt(
                      _session.messages,
                      m.positionStart,
                      m.positionEnd,
                      basePosition: _history.basePosition,
                    )
                  : null,
          };
          final today = _clockRunning ? _timeService.dayCount : null;
          String lineFor(RetrievedMemory m) => formatRagLine(
            m.content,
            day: days[m],
            otherChat: m.sessionId != sessionForStamps,
            today: today,
          );
          final included = <RetrievedMemory>[];
          int usedTokens = 0;
          for (final m in memories) {
            final memTokens = (lineFor(m).length / 4).ceil();
            if (usedTokens + memTokens > memoryBudget && included.isNotEmpty) {
              debugPrint(
                '[RAG:Chat] ⚠ Trimmed ${memories.length - included.length} memories to fit budget ($memoryBudget tokens)',
              );
              break;
            }
            usedTokens += memTokens;
            included.add(m);
          }
          if (included.isNotEmpty) {
            // Role frame: RAG is a remembered-from-earlier fact that left
            // history, or (quote-reach only) the words they asked for.
            // Journal gist outranks it on feelings, the recap on plot.
            // Leading '\n' because this now follows the history transcript,
            // whose last line carries no trailing newline.
            String buildBlock(List<RetrievedMemory> mems) =>
                buildRagMemoriesBlock(
                  memories: mems,
                  currentSessionId: sessionForStamps,
                  days: days,
                  reachingForQuote: reaching,
                  today: today,
                );
            t.memoriesBlock = buildBlock(included);

            // Budget accounting fix (spec §5f): memories were previously
            // injected WITHOUT being counted — history had already filled
            // its budget, so every RAG turn overshot the context and the
            // server trimmed the prompt head (the character card). Real-
            // count the block, trim trailing memories if the chars/4
            // estimates undershot the cap, then re-walk history with the
            // remainder so fixed + history + memories + reserve <= context.
            // Trim can go all the way to EMPTY: a single retrieved memory
            // larger than the whole memory budget must drop the block
            // entirely rather than ship over budget (review finding — the
            // packing loop above always admits the first memory).
            // JOINT cap (review finding): memories must fit the memory
            // budget AND leave a strictly positive history remainder —
            // memories are paid for out of the SAME space history uses, so
            // a block that survives only by starving history re-opens the
            // overshoot this fix exists to close. Trim goes all the way to
            // EMPTY (a lone oversize memory is dropped, never shipped over
            // budget). historyBudget <= 0 means the fixed sections already
            // fill the context — no room for memories at all.
            int memTokens = await _transcript.countTokens(t.memoriesBlock);
            while (memTokens > 0 &&
                (memTokens > memoryBudget ||
                    t.historyBudget - memTokens <= 0)) {
              // removeLast drops the LEAST RELEVANT survivor — `included` is
              // still in retrieve()'s score order; only the rendered block
              // is chronological.
              included.removeLast();
              t.memoriesBlock = included.isEmpty ? '' : buildBlock(included);
              memTokens = t.memoriesBlock.isEmpty
                  ? 0
                  : await _transcript.countTokens(t.memoriesBlock);
            }
            if (memTokens > 0) {
              // Re-walk history with the remainder (strictly positive here;
              // buildChatHistoryWithBudget treats <= 0 as UNLIMITED) so
              // fixed + history + memories + reserve <= context.
              final rebudget = await _transcript.buildChatHistoryWithBudget(
                t.historyBudget - memTokens,
                depthLore: t.loreDepth,
                splitLatestTurn: true,
              );
              t.history = rebudget.history;
              t.latestTurn = rebudget.latestTurn;
              // Keep the retrieval's inContextStart lag (spec: messages
              // evicted by this second walk become retrievable next turn);
              // the budget map below reports the final dropped count.
              t.droppedMessages = rebudget.droppedCount;
              debugPrint(
                '[RAG:Chat] ✅ Injecting ${included.length}/${memories.length} memories ($memTokens tokens real, budget: $memoryBudget)',
              );
            } else {
              debugPrint(
                '[RAG:Chat] ⚠ Dropped all ${memories.length} memories — no '
                'room inside the context budget this turn',
              );
            }
          }
          // The receipt: what this turn's retrieval found, dropped, and
          // actually injected (display order) — stamped onto the generated
          // message in the stream phase, rendered by the sidebar Memory
          // panel + the web facade. Built AFTER the trim loops so it reports
          // what shipped, not what was hoped for.
          t.ragReceipt = buildRagReceipt(
            found: rawMemories.length,
            journalDeduped: rawMemories.length - uncovered.length,
            budgetTrimmed: uncovered.length - included.length,
            injected: chronologicalRagOrder(included, sessionForStamps),
            days: days,
            currentSessionId: sessionForStamps,
          );
        } else {
          debugPrint('[RAG:Chat] No relevant memories found for this turn');
          t.ragReceipt = buildRagReceipt(
            found: rawMemories.length,
            journalDeduped: rawMemories.length - memories.length,
            budgetTrimmed: 0,
            injected: const [],
            days: const {},
            currentSessionId: _session.currentSessionId ?? '',
          );
        }
      } catch (e) {
        debugPrint('[RAG:Chat] ✗ RAG retrieval failed: $e');
        // Honest receipt (audit P2.17): lookup was attempted; do not leave
        // null ("no lookup needed") after a failed attempt with dropped context.
        t.ragReceipt = buildRagReceipt(
          found: 0,
          journalDeduped: 0,
          budgetTrimmed: 0,
          injected: const [],
          days: const {},
          currentSessionId: _session.currentSessionId ?? '',
          status: kRagReceiptError,
        );
      }
    } else if ((t.droppedMessages > 0 || _history.basePosition > 0) &&
        effectiveRagEnabled) {
      debugPrint(
        '[RAG:Chat] ⚠ ${t.droppedMessages} messages dropped but RAG not operational (service=${_memoryService != null}, operational=${_memoryService?.isOperational ?? false})',
      );
      t.ragReceipt = buildRagReceipt(
        found: 0,
        journalDeduped: 0,
        budgetTrimmed: 0,
        injected: const [],
        days: const {},
        currentSessionId: _session.currentSessionId ?? '',
        status: kRagReceiptNotOperational,
      );
    }
  }
}
