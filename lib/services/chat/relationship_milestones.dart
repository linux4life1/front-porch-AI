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

import 'package:front_porch_ai/services/chat/journal_store.dart';

/// Living Time §7 v1.5 / v1.5.1 — bond, long-term bond, and trust *tier*
/// crossings become durable "Our Story" journal cards
/// (`metadata.kind = 'milestone'`).
///
/// Pure text + one plant helper. Crossing *detection* stays in
/// [RelationshipService] so load/seed/regen-revert paths never invent story
/// beats. Message chips (per-turn deltas) are unchanged — these cards are
/// the long-horizon diary, not a chip replacement.
class TierCrossing {
  /// `'bond'` | `'long_term'` | `'trust'`.
  final String axis;
  final int oldTier;
  final int newTier;
  final String oldLabel;
  final String newLabel;

  const TierCrossing({
    required this.axis,
    required this.oldTier,
    required this.newTier,
    required this.oldLabel,
    required this.newLabel,
  });

  bool get rose => newTier > oldTier;
}

/// Static helpers for relationship threshold milestone cards.
class RelationshipMilestones {
  RelationshipMilestones._();

  /// Diary / timeline line for a tier crossing. Labels-only (no raw scores).
  static String textFor(TierCrossing c) {
    final rose = c.rose;
    if (c.axis == 'trust') {
      if (c.oldLabel == c.newLabel) {
        return rose
            ? 'Trust edged upward (${c.newLabel}).'
            : 'Trust edged downward (${c.newLabel}).';
      }
      return rose
          ? 'Trust rose to ${c.newLabel} (was ${c.oldLabel}).'
          : 'Trust fell to ${c.newLabel} (was ${c.oldLabel}).';
    }
    if (c.axis == 'long_term') {
      // Rarer, stickier climate — wording marks "deep" vs short-term weather.
      if (c.oldLabel == c.newLabel) {
        return rose
            ? 'The long bond edged deeper (${c.newLabel}).'
            : 'The long bond edged thinner (${c.newLabel}).';
      }
      return rose
          ? 'Something deeper settled — the long bond feels ${c.newLabel} '
              '(was ${c.oldLabel}).'
          : 'Something deeper cracked — the long bond feels ${c.newLabel} '
              '(was ${c.oldLabel}).';
    }
    // short-term bond (default)
    if (c.oldLabel == c.newLabel) {
      return rose
          ? 'Bond edged upward (${c.newLabel}).'
          : 'Bond edged downward (${c.newLabel}).';
    }
    return rose
        ? 'Bond deepened to ${c.newLabel} (was ${c.oldLabel}).'
        : 'Bond cooled to ${c.newLabel} (was ${c.oldLabel}).';
  }

  /// Emotion stamp for the card (feeds diary chips + timeline).
  static String emotionFor(TierCrossing c) {
    if (c.axis == 'trust') {
      return c.rose ? 'relieved' : 'wary';
    }
    if (c.axis == 'long_term') {
      return c.rose ? 'devoted' : 'wistful';
    }
    return c.rose ? 'warm' : 'hurt';
  }

  /// Plant one milestone card. Failures are logged, never thrown to callers
  /// (eval paths must not break because the diary write hiccuped).
  static Future<void> plant({
    required JournalStore store,
    required String sessionId,
    required String characterId,
    required TierCrossing crossing,
    List<int> sourcePositions = const [],
    int? storyDay,
    String? storyClock,
    required int maxCards,
  }) async {
    try {
      await store.addCard(
        sessionId: sessionId,
        characterId: characterId,
        content: textFor(crossing),
        category: 'moment',
        kind: 'milestone',
        emotionLabel: emotionFor(crossing),
        emotionIntensity: 'moderate',
        sourcePositions: sourcePositions,
        storyDay: storyDay,
        storyClock: storyClock,
        maxCards: maxCards,
      );
    } catch (e) {
      debugPrint('[Realism:Milestone] plant failed: $e');
    }
  }
}
