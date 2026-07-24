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

import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

/// Ambitions (living-time-features.md §6) — long-horizon ends the character
/// moves toward, distinct from objectives (means) and fixations (short-lived
/// obsessions). Definitions are identity (FrontPorchExtensions.ambitions on
/// the card); PROGRESS is story state, stored as one journal card per
/// ambition (`metadata.kind = 'ambition'`) — zero schema, per-chat,
/// per-character, deleted with the chat, visible in the diary and the
/// "Our Story" timeline for free.
///
/// Accrual fires only when a quest fully completes (rare): one tiny eval
/// asks whether that completion advanced any ambition. Waypoints (25/50/75)
/// plant milestone cards + the journal salience kick; reaching 100 plants a
/// Growth Ring — arriving at a long-held ambition IS identity change.
class AmbitionService {
  final JournalStore journalStore;
  final GrowthStore growthStore;
  final Future<String?> Function(String prompt) fireEval;
  final int Function() getMaxCards;

  /// Journal/growth salience kick (same signal objective completion sends).
  final VoidCallback? onWaypoint;

  /// Fired when a lazy cache load lands, so UI reading [cachedProgress]
  /// (sidebar ambitions row) rebuilds with real stages instead of sitting on
  /// "just beginning" until some unrelated notify.
  final VoidCallback? onCacheWarmed;

  AmbitionService({
    required this.journalStore,
    required this.growthStore,
    required this.fireEval,
    required this.getMaxCards,
    this.onWaypoint,
    this.onCacheWarmed,
  });

  /// Stage words for prompts + card content — words only, never numbers.
  static String stageWord(int progress) {
    if (progress >= 100) return 'achieved';
    if (progress >= 75) return 'nearly there';
    if (progress >= 50) return 'halfway there';
    if (progress >= 25) return 'gaining ground';
    return 'just beginning';
  }

  static const _advanceAmounts = {'small': 10, 'solid': 20, 'major': 35};

  /// Parse "NONE" or "&lt;index&gt; &lt;small|solid|major&gt;" forgivingly.
  /// Returns (1-based index, amount) or null.
  static (int, int)? parseAdvance(String? raw, int ambitionCount) {
    if (raw == null) return null;
    final text = raw.trim().toUpperCase();
    if (text.isEmpty || text.contains('NONE')) return null;
    final m = RegExp(
      r'(\d+)\s*[:\-—]?\s*(SMALL|SOLID|MAJOR)',
    ).firstMatch(text);
    if (m == null) return null;
    final idx = int.parse(m.group(1)!);
    if (idx < 1 || idx > ambitionCount) return null;
    return (idx, _advanceAmounts[m.group(2)!.toLowerCase()]!);
  }

  /// In-memory progress cache for the SYNC injection builder (same pattern
  /// as the growth injection cache). Keyed 'sessionId|characterId' →
  /// {ambitionText: progress}. Warmed lazily; ticks update it in place.
  final Map<String, Map<String, int>> _progressCache = {};
  final Set<String> _warming = {};

  Map<String, int>? cachedProgress(String sessionId, String characterId) =>
      _progressCache['$sessionId|$characterId'];

  /// Lazy warm for the injection path: returns immediately; the block
  /// renders "just beginning" stages until the read lands (next build has
  /// real values). No session-load surgery needed.
  void ensureCacheWarm(String sessionId, String characterId) {
    final key = '$sessionId|$characterId';
    if (_progressCache.containsKey(key) || _warming.contains(key)) return;
    _warming.add(key);
    _loadProgress(sessionId, characterId).whenComplete(() {
      _warming.remove(key);
      onCacheWarmed?.call();
    });
  }

  Future<Map<String, int>> _loadProgress(
    String sessionId,
    String characterId,
  ) async {
    final map = <String, int>{};
    for (final card in await journalStore.cardsFor(sessionId, characterId)) {
      final meta = _metaOf(card.metadata);
      if (meta['kind'] != 'ambition') continue;
      final text = meta['ambition'];
      final progress = meta['progress'];
      if (text is String && progress is num) {
        map[text] = progress.toInt().clamp(0, 100);
      }
    }
    _progressCache['$sessionId|$characterId'] = map;
    return map;
  }

  static Map<String, dynamic> _metaOf(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : const {};
    } catch (_) {
      return const {};
    }
  }

  /// A quest fully completed — ask (one tiny eval) whether it advanced an
  /// ambition, and apply the tick: upsert the progress card, plant waypoint
  /// milestone cards on 25/50/75 crossings, plant a Growth Ring + achieved
  /// card at 100. Silent on any failure (local-model floor).
  Future<void> onQuestAchieved({
    required String sessionId,
    required String characterId,
    required String characterName,
    required String objectiveText,
    required List<String> ambitions,
    int? storyDay,
    String? storyClock,
  }) async {
    if (ambitions.isEmpty) return;
    try {
      final progress = await _loadProgress(sessionId, characterId);
      final open = ambitions
          .where((a) => (progress[a] ?? 0) < 100)
          .toList();
      if (open.isEmpty) return;

      final numbered = [
        for (var i = 0; i < open.length; i++)
          '${i + 1}. ${open[i]} (${stageWord(progress[open[i]] ?? 0)})',
      ].join('\n');
      final raw = await fireEval(
        '$characterName just completed: "$objectiveText"\n\n'
        '$characterName\'s long-term ambitions:\n$numbered\n\n'
        'Did completing that meaningfully advance one of these ambitions? '
        'Judge strictly — most objectives advance nothing.\n'
        'Answer with EXACTLY one line: NONE, or the ambition number followed '
        'by the size of the step (small, solid, or major). Example: "2 solid". '
        'Nothing else.',
      );
      final advance = parseAdvance(raw, open.length);
      if (advance == null) return;

      final (idx, amount) = advance;
      final ambition = open[idx - 1];
      final before = progress[ambition] ?? 0;
      final after = (before + amount).clamp(0, 100);
      await _writeProgress(
        sessionId: sessionId,
        characterId: characterId,
        ambition: ambition,
        progress: after,
        storyDay: storyDay,
        storyClock: storyClock,
      );
      progress[ambition] = after;
      debugPrint(
        '[Ambitions] "$ambition": $before → $after (via "$objectiveText")',
      );

      for (final waypoint in const [25, 50, 75]) {
        if (before < waypoint && after >= waypoint && after < 100) {
          await journalStore.addCard(
            sessionId: sessionId,
            characterId: characterId,
            content:
                'A real step toward my ambition — $ambition. I\'m '
                '${stageWord(after)}.',
            category: 'moment',
            kind: 'milestone',
            emotionLabel: 'hopeful',
            storyDay: storyDay,
            storyClock: storyClock,
            maxCards: getMaxCards(),
          );
          onWaypoint?.call();
          break;
        }
      }
      if (after >= 100 && before < 100) {
        await journalStore.addCard(
          sessionId: sessionId,
          characterId: characterId,
          content: 'I did it. My ambition is real now — $ambition.',
          category: 'moment',
          kind: 'milestone',
          emotionLabel: 'proud',
          storyDay: storyDay,
          storyClock: storyClock,
          maxCards: getMaxCards(),
        );
        // Arriving at a long-held ambition is identity change — exactly what
        // Growth Rings model.
        await growthStore.addRing(
          sessionId: sessionId,
          characterId: characterId,
          content: 'Achieved a long-held ambition: $ambition',
          category: 'scar',
          pinned: true,
        );
        onWaypoint?.call();
      }
    } catch (e) {
      debugPrint('[Ambitions] tick skipped: $e');
    }
  }

  Future<void> _writeProgress({
    required String sessionId,
    required String characterId,
    required String ambition,
    required int progress,
    int? storyDay,
    String? storyClock,
  }) async {
    // One card per ambition: find by metadata identity, update in place, or
    // create on first tick.
    for (final card in await journalStore.cardsFor(sessionId, characterId)) {
      final meta = _metaOf(card.metadata);
      if (meta['kind'] == 'ambition' && meta['ambition'] == ambition) {
        await journalStore.updateCardMetadata(card, {'progress': progress});
        await journalStore.reviseCard(
          card,
          content: 'My ambition: $ambition — ${stageWord(progress)}.',
        );
        return;
      }
    }
    await journalStore.addCard(
      sessionId: sessionId,
      characterId: characterId,
      content: 'My ambition: $ambition — ${stageWord(progress)}.',
      category: 'moment',
      kind: 'ambition',
      storyDay: storyDay,
      storyClock: storyClock,
      maxCards: getMaxCards(),
    );
    // Stamp the identity + progress metadata the reader keys on.
    for (final card in await journalStore.cardsFor(sessionId, characterId)) {
      final meta = _metaOf(card.metadata);
      if (meta['kind'] == 'ambition' && !meta.containsKey('ambition')) {
        await journalStore.updateCardMetadata(card, {
          'ambition': ambition,
          'progress': progress,
        });
        return;
      }
    }
  }
}
