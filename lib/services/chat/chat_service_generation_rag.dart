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

part of '../chat_service.dart';

/// Phase 3 of `_generateResponse` (see chat_service_generation.dart): RAG
/// memory retrieval + the joint memory/history budget trim. Extracted
/// verbatim (mechanical `x` → `t.x` carrier rename only — see `_GenTurn`)
/// from the single ~1.9k-line `_generateResponse` method during the
/// god-file split (docs/design/god-file-elimination.md). Zero behaviour
/// change. Also carries `_getMemorySourceIds` — relocated verbatim from
/// `chat_service.dart` (its only caller lives in this phase) to offset the
/// new part directives against the god-file line-count ratchet.
extension ChatServiceGenerationRag on ChatService {
  Future<void> _retrieveGenerationMemories(_GenTurn t) async {
    // ── RAG Memory Retrieval ──
    // When messages are dropped from context, search for relevant past memories
    // Skip retrieval for brand new chats to prevent old memories from interfering
    final effectiveRagEnabled = _activeGroup != null
        ? groupRagEnabled
        : _storageService.memorySettings.ragEnabled;

    if (_isNewChat) {
      debugPrint('[RAG:Chat] Skipping memory retrieval - new chat in progress');
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
        // Cued query: emotion + fixation + top hot journal line + last
        // words (photo markers ride lastWords via promptText). Recomposed
        // here so Continue's plan-phase pop is visible. Not last-3 alone.
        t.ragQuery = composeRagQuery(
          emotion: _characterEmotion,
          fixation: _relationshipService.activeFixation,
          hotJournalLine: t.ragHotJournalLine,
          lastWords: lastWordsFromMessages(_messages),
        );
        final queryMessages = t.ragQuery;
        final reaching = isReachingForQuote(
          lastSpokenLineFromMessages(_messages),
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
        final sourceIds = await _getMemorySourceIds(guest: t.guestSpeaker);
        debugPrint('[RAG:Chat] Memory source IDs: $sourceIds');

        // Session isolation: the speaker/group bucket AND (in groups) every
        // member stableGroupId (added for Data Bank / priorities) must be
        // session-scoped — otherwise 1:1 conversation embeddings bleed into
        // the group (second-look P2.16). Explicit memorySources for ids that
        // are NOT already group members stay unscoped for opt-in cross-session
        // recall. A memorySource that IS a group member is already in the
        // scoped set (members win / dedupe); that is deliberate anti-bleed,
        // not a free cross-session path for someone sitting in the cast.
        // Data Bank is a separate path and never consults this set.
        final sessionScoped = <String>{
          if (sourceIds.isNotEmpty) sourceIds.first,
          if (t.guestSpeaker == null && _activeGroup != null)
            for (final c in _groupCharacters) _getCharacterIdFromCard(c),
        }..remove('');

        // Retrieval limit: groups use the per-session group setting; 1:1
        // uses the user's "Memories per turn" slider (memory panel + web).
        // The slider was previously DEAD here — 1:1 silently rode the group
        // default (8) and turning it down did nothing. 0 = "All" on both.
        final retrievalLimit = _activeGroup != null
            ? groupRetrievalCount
            : _storageService.memorySettings.ragRetrievalCount;

        final List<RetrievedMemory> rawMemories;
        if (skipCueLess) {
          debugPrint('[RAG:Chat] Skipping memory retrieval — cue-less beat');
          rawMemories = const [];
        } else {
          rawMemories = await _memoryService!.retrieve(
            queryText: queryMessages,
            sourceCharacterIds: sourceIds,
            currentSessionId: _currentSessionId ?? '',
            inContextStart: _history.basePosition + t.droppedMessages,
            limit: retrievalLimit == 0 ? 9999 : retrievalLimit,
            characterPriorities: currentGroupRAGPriorities,
            sessionScopedCharacterIds: sessionScoped,
          );
        }
        // Two-tier memory dedupe: the journal expanded these exact lines
        // above — never pay for them twice.
        final afterExpand = RetrievedMemory.excludingPositions(
          rawMemories,
          t.expandedJournalPositions,
          currentSessionId: _currentSessionId ?? '',
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
          // Journal gist can still inject. No last-1 search, no receipt.
        } else if (rawMemories.isEmpty && !_memoryService!.isOperational) {
          t.ragReceipt = buildRagReceipt(
            found: 0,
            journalDeduped: 0,
            budgetTrimmed: 0,
            injected: const [],
            days: const {},
            currentSessionId: _currentSessionId ?? '',
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
          final contextSize = _storageService.backendSettings.contextSize;
          final budgetFraction = _activeGroup != null
              ? (groupMemoryBudgetPercent / 100.0)
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
          final sessionForStamps = _currentSessionId ?? '';
          final days = <RetrievedMemory, int?>{
            for (final m in memories)
              m: m.sessionId == sessionForStamps
                  ? storyDayAt(_messages, m.positionStart, m.positionEnd)
                  : null,
          };
          String lineFor(RetrievedMemory m) => formatRagLine(
            m.content,
            day: days[m],
            otherChat: m.sessionId != sessionForStamps,
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
            int memTokens = await _countTokens(t.memoriesBlock);
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
                  : await _countTokens(t.memoriesBlock);
            }
            if (memTokens > 0) {
              // Re-walk history with the remainder (strictly positive here;
              // _buildChatHistoryWithBudget treats <= 0 as UNLIMITED) so
              // fixed + history + memories + reserve <= context.
              final rebudget = await _buildChatHistoryWithBudget(
                t.historyBudget - memTokens,
                depthLore: t.loreDepth,
              );
              t.history = rebudget.history;
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
            currentSessionId: _currentSessionId ?? '',
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
          currentSessionId: _currentSessionId ?? '',
          status: kRagReceiptError,
        );
      }
    } else if ((t.droppedMessages > 0 || _history.basePosition > 0) &&
        _storageService.memorySettings.ragEnabled) {
      debugPrint(
        '[RAG:Chat] ⚠ ${t.droppedMessages} messages dropped but RAG not operational (service=${_memoryService != null}, operational=${_memoryService?.isOperational ?? false})',
      );
      t.ragReceipt = buildRagReceipt(
        found: 0,
        journalDeduped: 0,
        budgetTrimmed: 0,
        injected: const [],
        days: const {},
        currentSessionId: _currentSessionId ?? '',
        status: kRagReceiptNotOperational,
      );
    }
  }

  /// Get the list of character IDs to search for RAG memory retrieval.
  /// Reads the current character's `memorySources` from the DB and includes
  /// those characters' embedding IDs alongside the current character.
  /// Resolve the RAG source character ids for retrieval.
  ///
  /// Normally keyed on the active character (or the group bucket). When a
  /// [guest] is supplied (Scene Guests Phase 4), retrieval is keyed on the
  /// guest's OWN id instead — the same id the guest embeds under via
  /// [_maybeEmbedMessages] — plus that guest's cross-character memory sources.
  /// This keeps the guest's episodic memory isolated from the host's: the
  /// host's memories are never injected on a guest turn, and vice versa.
  Future<List<String>> _getMemorySourceIds({CharacterCard? guest}) async {
    final currentId = guest != null
        ? _getCharacterIdFromCard(guest)
        : _getCharacterId();
    final sourceIds = <String>[currentId]; // always include self

    // Group conversation embeds under group_<id>, but Data Bank rows and the
    // per-member RAG priority sliders key by each member's stableGroupId
    // (audit P2.16). Without those ids, member Data Bank and priority
    // multipliers never match a candidate. Conversation RAG stays on the
    // group bucket; members only add Data Bank / any per-member embeddings.
    if (guest == null && _activeGroup != null) {
      for (final c in _groupCharacters) {
        final mid = _getCharacterIdFromCard(c);
        if (mid.isNotEmpty && !sourceIds.contains(mid)) sourceIds.add(mid);
      }
    }

    // Look up cross-character sources from DB (for the guest, or the active char)
    final sourceCard = guest ?? _activeCharacter;
    if (sourceCard != null && sourceCard.dbId != null) {
      try {
        final dbChar = await _db.getCharacterById(sourceCard.dbId!);
        final ms = dbChar.memorySources;
        if (ms.isNotEmpty && ms != '[]') {
          final decoded = List<String>.from(
            (jsonDecode(ms) as List).map((e) => e.toString()),
          );
          for (final id in decoded) {
            if (!sourceIds.contains(id)) sourceIds.add(id);
          }
          if (decoded.isNotEmpty) {
            debugPrint('[RAG:Chat] Cross-character sources: $decoded');
          }
        }
      } catch (e) {
        debugPrint('[RAG:Chat] Failed to read memorySources: $e');
      }
    }

    return sourceIds;
  }
}
