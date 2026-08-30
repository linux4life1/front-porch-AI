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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
// memory_service.dart is not exported by the curated services.dart barrel, so
// this one stays a direct import (documented exemption).
import 'package:front_porch_ai/services/memory_service.dart';

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

  /// Current story time (TimeService) — lets stamped cards render WHEN they
  /// happened relative to now (story-calendar §4: "Day 5, Tuesday night —
  /// 9 days ago"). Unstamped cards render exactly as before.
  final int Function() getCurrentStoryDay;
  final DateTime Function() getStoryStartDate;

  /// Verbatim lookup behind a card's receipts (two-tier memory): position →
  /// the live in-memory message, or null when out of range. Wired to
  /// ChatService's message list; positions are the same stable receipt
  /// indices cards already store.
  final ChatMessage? Function(int position)? getMessageAt;

  JournalInjection({
    required this.store,
    required this.getSessionId,
    required this.getCurrentEmotion,
    required this.getCurrentStoryDay,
    required this.getStoryStartDate,
    this.getMessageAt,
  });

  /// ~600 tokens at the shared chars/4 heuristic (same estimator the
  /// memoriesBlock budget uses).
  static const int kHotSetTokenBudget = 600;

  /// [queryText] is the cued query used to resurface cold cards
  /// semantically (same composeRagQuery as RAG retrieval); empty
  /// skips cold retrieval entirely.
  /// [lastWords] is the live beat (same string RAG uses). Expand
  /// gates on this — never on [queryText], which can contain a diary
  /// "I remember when…" that is not an ask.
  Future<
    ({String text, Set<int> expandedPositions, List<String> injectedContents})
  >
  buildJournalBlock({
    required String characterId,
    required String characterName,
    required String userName,
    String queryText = '',
    String lastWords = '',
    int messageCount = 0,
  }) async {
    const empty = (
      text: '',
      expandedPositions: <int>{},
      injectedContents: <String>[],
    );
    final sessionId = getSessionId();
    if (sessionId == null || characterId.isEmpty) return empty;

    final cards = await store.cardsFor(sessionId, characterId);
    if (cards.isEmpty) return empty;

    final currentEmotion = getCurrentEmotion();

    // ONE query embedding per build, shared by cold-card resurfacing and
    // expand-memory scoring (they ask the same "what is the conversation
    // reaching for?" question).
    List<double>? queryVector;
    final embed = store.embedText;
    if (embed != null && queryText.trim().isNotEmpty) {
      queryVector = await embed(queryText);
      if (queryVector != null && queryVector.isEmpty) queryVector = null;
    }

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

    final coldCards = cards.where((c) => !JournalPhysics.isHot(c)).toList();

    // The keyword floor (2026-08-11): a cold ITEM card resurfaces the moment
    // the conversation names its item — plain token intersection, no
    // embeddings, so "where are my keys?" works on every install. Runs
    // before cosine and claims its cards, so the two paths never double-pick.
    final queryTokens = itemNameTokens(queryText);
    final lexical = <JournalMemoryData>[];
    if (queryTokens.isNotEmpty) {
      for (final card in coldCards) {
        if (lexical.length >= JournalPhysics.kColdRetrievalLimit) break;
        if (JournalPhysics.itemCardMentioned(card, queryTokens) ||
            JournalPhysics.episodeCardMentioned(card, queryTokens) ||
            JournalPhysics.birthdayCardMentioned(card, queryTokens)) {
          lexical.add(card);
        }
      }
      for (final card in lexical) {
        if (JournalPhysics.isBirthdayCard(card)) continue;
        await store.rewarmCard(card);
      }
      if (lexical.isNotEmpty) {
        debugPrint(
          '[Journal] 🔑 Resurfaced ${lexical.length} item card(s) by name',
        );
      }
    }

    final resurfaced = await _retrieveColdCards(
      coldCards.where((c) => !lexical.contains(c)).toList(),
      queryVector,
      currentEmotion,
    );

    // Named mention is the stronger signal, so lexical picks rank ahead of
    // cosine ones.
    final injected = [...pinned, ...hot, ...lexical, ...resurfaced];
    final lines = <String>[];
    final injectedContents = <String>[];
    var usedChars = 0;
    const budgetChars = kHotSetTokenBudget * 4;
    for (final card in injected) {
      final line =
          '- (${_label(card, userName)}${_when(card)}) ${card.content}';
      if (usedChars + line.length > budgetChars && lines.isNotEmpty) break;
      usedChars += line.length;
      lines.add(line);
      injectedContents.add(card.content);
    }
    if (lines.isEmpty) return empty;

    // Expand-memory (two-tier memory, living-time-features.md §8): when the
    // conversation clearly reaches for ONE remembered moment ("remember our
    // wedding vows?"), the card supplies the feeling and its receipts supply
    // the exact words. Strictly gated: quote-reach (isReachingForQuote),
    // embeddings, cosine ≥ 0.45, and receipts old enough to be out of the
    // visible transcript. A plain sit-down stays gist — the cued query
    // contains the top hot line, so cosine alone would always expand it.
    final (excerpt, expandedPositions) = isReachingForQuote(lastWords)
        ? _expandBestCard(injected, queryVector, messageCount)
        : ('', <int>{});

    // Role frame (docs/design/prompt-state-injection.md §6): the journal is
    // the FEELINGS channel — when a card covers the same moment as the recap
    // or a retrieved transcript line, the feelings here are the truer guide.
    // Leading \n: this block renders AFTER the transcript (which has no
    // trailing newline), so like memoriesBlock it carries its own separator;
    // the "not new messages" clause is the anti-echo guard for sitting near
    // the generation point.
    //
    // ── SCOPE WIDENED 2026-08-08 ────────────────────────────────────────────
    // The clause used to name the recap and the transcript and stop there,
    // which left the one collision that users actually hit unresolved: the
    // character-state block ('realism', four sections BELOW this one in
    // kStateZoneSectionIds) renders a bond/trust reading off engine scalars
    // that can sit near zero while the cards underneath describe deep
    // connection. Measured against Kimi 2.6, 14 conflict sentences named this
    // pair — "the notes say 'no particular trust or distrust' but the journal
    // entries show intense trust and connection".
    //
    // The primary fix is upstream, in relationship_injection.dart, which no
    // longer asserts absences the cards can falsify. This is the second half:
    // where the two still overlap, ONE of them has to be named the guide, and
    // the Journal is already the block that carries that ruling. So the
    // EXISTING clause is widened rather than a second rule being written — the
    // state zone ships exactly one precedence frame (state_zone_frame.dart)
    // plus this grandfathered one, and §6.1 bans per-block precedence lines by
    // name.
    //
    // Two deliberate properties of the wording:
    //  * It names a KIND ("any other note about where they stand"), not a
    //    block. Role frames may not assume a block exists (§ degradation
    //    floors) — the character-state block is absent whenever the Realism
    //    Engine is off, and the recap is absent on a virgin chat.
    //  * It is relationship-scoped on purpose. It does NOT reach the mood,
    //    needs, position or story-clock lines in that same block: those are
    //    live readings of RIGHT NOW, the cards are remembered moments, and a
    //    memory has no business overruling where someone is standing.
    final impulse = speechImpulse(
      injected: injected,
      lastWords: lastWords,
      seed: Object.hash(lastWords, messageCount),
    );
    final impulseBlock = impulse == null ? '' : '\n$impulse';
    final text =
        "\n[$characterName's private journal — personal memories from "
        'this chat, in their own words. Not new messages, and nothing here '
        'needs a reply. These shape how they feel and behave, and where '
        'anything else covers the same ground — the story recap, the lines '
        'above, or any other note about where $characterName stands with '
        '$userName — the feelings here are the truer guide:\n'
        '${lines.join('\n')}'
        '$excerpt'
        '$impulseBlock\n]\n';
    return (
      text: text,
      expandedPositions: expandedPositions,
      injectedContents: injectedContents,
    );
  }

  /// Top-1 card the query is reaching for, expanded into trimmed verbatim
  /// source lines. Returns ('', {}) whenever any gate fails — the block is
  /// then byte-identical to the pre-expansion format.
  (String, Set<int>) _expandBestCard(
    List<JournalMemoryData> injected,
    List<double>? queryVector,
    int messageCount,
  ) {
    const none = ('', <int>{});
    final lookup = getMessageAt;
    if (queryVector == null || lookup == null || messageCount <= 0) {
      return none;
    }

    JournalMemoryData? best;
    var bestScore = JournalPhysics.kMinExpandSimilarity;
    for (final card in injected) {
      if (card.embedding == null || card.sourceMessageIds == null) continue;
      final vector = MemoryService.bytesToVector(
        card.embedding!,
        card.dimensions,
      );
      if (vector == null) continue;
      final similarity = MemoryService.cosineSimilarity(queryVector, vector);
      if (similarity >= bestScore) {
        bestScore = similarity;
        best = card;
      }
    }
    if (best == null) return none;

    List<int> positions;
    try {
      positions = (jsonDecode(best.sourceMessageIds!) as List)
          .whereType<num>()
          .map((n) => n.toInt())
          .toList();
    } catch (_) {
      return none;
    }
    // Age gate: younger receipts are still in (or near) the transcript.
    positions = positions
        .where((p) => p < messageCount - JournalPhysics.kExpandMinAgeMessages)
        .toList();
    if (positions.isEmpty) return none;

    final quoted = <String>[];
    final used = <int>{};
    var chars = 0;
    for (final p in positions) {
      final msg = lookup(p);
      if (msg == null) continue;
      var text = msg.displayText.trim();
      if (text.isEmpty) continue;
      if (text.length > JournalPhysics.kExpandPerMessageChars) {
        text = '${text.substring(0, JournalPhysics.kExpandPerMessageChars)}…';
      }
      final line = '  «${msg.sender}: $text»';
      if (chars + line.length > JournalPhysics.kExpandTotalChars &&
          quoted.isNotEmpty) {
        break;
      }
      chars += line.length;
      quoted.add(line);
      used.add(p);
    }
    if (quoted.isEmpty) return none;
    debugPrint(
      '[Journal] 🔍 Expanded "${best.content.substring(0, best.content.length.clamp(0, 40))}…" '
      '(${used.length} verbatim line(s), similarity ${bestScore.toStringAsFixed(2)})',
    );
    return (
      '\nOne memory stands out sharply right now — they recall the exact '
          'words from that moment:\n${quoted.join('\n')}',
      used,
    );
  }

  /// Cold cards come back when the conversation drifts near them: cosine
  /// similarity against the recent turn (floor first, mood bonus after, so
  /// congruence can rank but never launder an irrelevant card), top few
  /// re-warmed into the hot set with their access recorded (design §4.4).
  Future<List<JournalMemoryData>> _retrieveColdCards(
    List<JournalMemoryData> cold,
    List<double>? query,
    String currentEmotion,
  ) async {
    if (cold.isEmpty || query == null) return const [];
    final withVectors = cold.where((c) => c.embedding != null).toList();
    if (withVectors.isEmpty) return const [];

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
      'item' => 'belongings',
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

  /// " · Day 5, Tuesday night — 9 days ago" for stamped cards; '' otherwise.
  /// The date re-derives live from storyDay + the anchor, so a calendar
  /// re-anchor retro-dates every memory consistently (story-calendar §4).
  String _when(JournalMemoryData card) {
    final (day, clock) = JournalStore.stampOf(card);
    if (day == null) return '';
    final date = StoryClock.dateOnly(
      getStoryStartDate(),
    ).add(Duration(days: day - 1));
    final weekday = StoryClock.weekdayName(date);
    final period = clock == null
        ? ''
        : ' ${StoryClock.periodForHour(clock.hour).replaceAll('_', ' ')}';
    final delta = getCurrentStoryDay() - day;
    final ago = switch (delta) {
      <= 0 => 'earlier today',
      1 => 'yesterday',
      < 14 => '$delta days ago',
      _ => '${(delta / 7).round()} weeks ago',
    };
    return ' · Day $day, $weekday$period — $ago';
  }
}
