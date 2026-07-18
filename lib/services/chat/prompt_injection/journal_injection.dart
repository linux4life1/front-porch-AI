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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import '../journal_physics.dart';
import '../journal_store.dart';

/// The Journal — prompt injection builder (docs/design/journal-memory.md
/// §4.5). Tenth sibling of the prompt_injection builders: renders the
/// upcoming speaker's pinned + hot memory cards (with their felt emotions)
/// into a token-budgeted block injected right after the recap (summaryBlock),
/// which itself follows the transcript + retrieved memories (post-history
/// placement — this block re-sorts with mood every turn, and a changing block
/// BEFORE the history would force a full re-prefill on local backends).
///
/// Phase 2 emotional physics live here on the read side: the hot set is
/// pinned cards plus cards above the cold threshold, ordered by heat with a
/// mood-congruent boost (a sad character reaches for sad memories first when
/// the budget forces a choice); cold cards resurface via semantic search
/// against the recent turn and are re-warmed by the retrieval.
///
/// Requires NO embeddings for the hot/pinned path — the Journal works without
/// the RAG sidecar (design invariant: local-model/no-setup floor); only the
/// cold-card resurfacing needs vectors. Strictly per-chat: loads cards for
/// the current session + speaker only.
///
/// [getCurrentEmotion] reads the same _characterEmotion scalar the sibling
/// EmotionInjection uses — in group non-observer mode the god's
/// load-into-scalars dance has already set it to the upcoming speaker's
/// emotion by assembly time, so mood congruence is per-speaker in groups
/// (1:1 ↔ group parity by the same mechanism).
class JournalInjection {
  final JournalStore store;
  final String? Function() getSessionId;
  final String Function() getCurrentEmotion;

  JournalInjection({
    required this.store,
    required this.getSessionId,
    required this.getCurrentEmotion,
  });

  /// ~600 tokens at the shared chars/4 heuristic (same estimator the
  /// memoriesBlock budget uses).
  static const int kHotSetTokenBudget = 600;

  /// [queryText] is the recent-turn text used to resurface cold cards
  /// semantically (same last-3-messages recipe as RAG retrieval); empty
  /// skips cold retrieval entirely.
  Future<String> buildJournalBlock({
    required String characterId,
    required String characterName,
    required String userName,
    String queryText = '',
  }) async {
    final sessionId = getSessionId();
    if (sessionId == null || characterId.isEmpty) return '';

    final cards = await store.cardsFor(sessionId, characterId);
    if (cards.isEmpty) return '';

    final currentEmotion = getCurrentEmotion();

    // Hot set: pinned first (store order), then warm cards by heat + mood
    // boost, newest first on ties — so when the budget bites, the character
    // keeps the memories that burn hottest and match their current mood.
    final pinned = cards.where((c) => c.pinned).toList();
    final hot =
        cards.where((c) => !c.pinned && JournalPhysics.isHot(c)).toList()
          ..sort((a, b) {
            final byKey = JournalPhysics.hotSortKey(
              b,
              currentEmotion,
            ).compareTo(JournalPhysics.hotSortKey(a, currentEmotion));
            return byKey != 0 ? byKey : b.createdAt.compareTo(a.createdAt);
          });

    final resurfaced = await _retrieveColdCards(
      cards.where((c) => !JournalPhysics.isHot(c)).toList(),
      queryText,
      currentEmotion,
    );

    final lines = <String>[];
    var usedChars = 0;
    const budgetChars = kHotSetTokenBudget * 4;
    for (final card in [...pinned, ...hot, ...resurfaced]) {
      final line = '- (${_label(card, userName)}) ${card.content}';
      if (usedChars + line.length > budgetChars && lines.isNotEmpty) break;
      usedChars += line.length;
      lines.add(line);
    }
    if (lines.isEmpty) return '';

    // Role frame (docs/design/prompt-state-injection.md §6): the journal is
    // the FEELINGS channel — when a card covers the same moment as the recap
    // or a retrieved transcript line, the feelings here are the truer guide.
    // Leading \n: this block renders AFTER the transcript (which has no
    // trailing newline), so like memoriesBlock it carries its own separator;
    // the "not new messages" clause is the anti-echo guard for sitting near
    // the generation point.
    return "\n[$characterName's private journal — personal memories from "
        'this chat, in their own words. Not new messages, and nothing here '
        'needs a reply. These shape how they feel and behave, and when they '
        'cover the same moments as the story recap or the lines above, the '
        'feelings here are the truer guide:\n'
        '${lines.join('\n')}\n]\n';
  }

  /// Cold cards come back when the conversation drifts near them: cosine
  /// similarity against the recent turn (floor first, mood bonus after, so
  /// congruence can rank but never launder an irrelevant card), top few
  /// re-warmed into the hot set with their access recorded (design §4.4).
  Future<List<JournalMemoryData>> _retrieveColdCards(
    List<JournalMemoryData> cold,
    String queryText,
    String currentEmotion,
  ) async {
    final embed = store.embedText;
    if (cold.isEmpty || queryText.trim().isEmpty || embed == null) {
      return const [];
    }
    final withVectors = cold.where((c) => c.embedding != null).toList();
    if (withVectors.isEmpty) return const [];

    final query = await embed(queryText);
    if (query == null || query.isEmpty) return const [];

    final scored = <(JournalMemoryData, double)>[];
    for (final card in withVectors) {
      final vector = MemoryService.bytesToVector(
        card.embedding!,
        card.dimensions,
      );
      if (vector == null) continue;
      final similarity = MemoryService.cosineSimilarity(query, vector);
      if (similarity < JournalPhysics.kMinColdSimilarity) continue;
      final congruent = JournalPhysics.moodCongruent(
        card.emotionLabel,
        currentEmotion,
      );
      scored.add((
        card,
        similarity + (congruent ? JournalPhysics.kMoodSimilarityBonus : 0.0),
      ));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    final picked = scored
        .take(JournalPhysics.kColdRetrievalLimit)
        .map((s) => s.$1)
        .toList();
    for (final card in picked) {
      await store.rewarmCard(card);
    }
    if (picked.isNotEmpty) {
      debugPrint(
        '[Journal] ♨ Resurfaced ${picked.length} cold card(s) '
        '(${scored.length} above similarity floor)',
      );
    }
    return picked;
  }

  /// "(a promise, felt hopeful)" / "(about Sam, once felt sad — now feels
  /// proud)" — category + emotional imprint, including the healed-feeling arc.
  String _label(JournalMemoryData card, String userName) {
    final category = switch (card.category) {
      'about_user' => 'about $userName',
      'about_us' => 'about us',
      'promise' => 'a promise',
      _ => 'a moment',
    };
    final emotion = card.emotionLabel;
    if (emotion == null || emotion.isEmpty) return category;
    if (card.originalEmotionLabel != null &&
        card.originalEmotionLabel != emotion) {
      return '$category, once felt ${card.originalEmotionLabel} — now feels '
          '$emotion';
    }
    final intensity = switch (card.emotionIntensity) {
      'strong' => ' (strongly)',
      'mild' => ' (mildly)',
      _ => '',
    };
    return '$category, felt $emotion$intensity';
  }
}
