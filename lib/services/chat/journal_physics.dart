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

import 'dart:math';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// The Journal — deterministic emotional physics
/// (docs/design/journal-memory.md §4.4). Pure constants + functions, no LLM
/// judgment and no I/O: heat cooling with flashbulb resistance, the hot/cold
/// threshold, mood-congruent recall scoring, and salient-event detection for
/// event-triggered passes.
///
/// Tunables are code constants (design §6) until proven to need settings.
/// JournalStore applies the cooling/trim, JournalInjection the recall
/// scoring, and ChatService._maybeRunJournalPass the event trigger — all
/// through this one class, so 1:1 and group share the exact same numbers.
class JournalPhysics {
  JournalPhysics._(); // static namespace, never instantiated

  /// Heat a fresh (or just-revised) card carries.
  static const double kMaxHeat = 1.0;

  /// Base heat lost per maintenance pass (a mild card stays hot ~5 passes).
  static const double kBaseDecayPerPass = 0.15;

  /// Flashbulb resistance — the fraction of the base decay each intensity
  /// actually feels. Design: "mild decays at the normal rate, moderate
  /// slower, strong barely at all. Pinned never decays."
  static const double kModerateDecayFactor = 0.5;
  static const double kStrongDecayFactor = 0.15;

  /// Below this heat a card leaves the always-injected hot set. It stays
  /// semantically searchable and can be re-warmed by retrieval.
  static const double kColdThreshold = 0.35;

  /// Heat a cold card returns to when semantic retrieval resurfaces it —
  /// back in the hot set, but below a fresh memory.
  static const double kRewarmHeat = 0.75;

  /// Hot-set ordering bonus for cards whose feeling matches the character's
  /// current emotion family (mood-congruent recall: a sad character reaches
  /// for sad memories first when the token budget forces a choice).
  static const double kMoodBoost = 0.25;

  /// Score bonus added to cosine similarity for mood-congruent cold cards.
  static const double kMoodSimilarityBonus = 0.1;

  /// Minimum cosine similarity for a cold card to resurface.
  static const double kMinColdSimilarity = 0.35;

  /// Max cold cards resurfaced per turn.
  static const int kColdRetrievalLimit = 3;

  /// Engine-stamped deltas at or above these magnitudes count as a
  /// significant event and trigger an immediate maintenance pass.
  static const int kEventBondSwing = 12;
  static const int kEventTrustSwing = 12;

  /// A virgin journal (cursor 0) on an existing long chat only reads this
  /// many trailing messages on its first pass.
  static const int kFirstPassCap = 50;

  /// One card's heat after one maintenance pass of cooling.
  static double cooledHeat(JournalMemoryData card) {
    if (card.pinned) return card.heat;
    final factor = switch (card.emotionIntensity) {
      'strong' => kStrongDecayFactor,
      'moderate' => kModerateDecayFactor,
      _ => 1.0,
    };
    return max(0.0, card.heat - kBaseDecayPerPass * factor);
  }

  /// Whether a card belongs to the always-injected hot set.
  static bool isHot(JournalMemoryData card) =>
      card.pinned || card.heat >= kColdThreshold;

  /// Standard emotion family for a (possibly nuanced) label — 'wistful' and
  /// 'melancholy' both land on 'sadness'. Unknown labels are their own family.
  static String emotionFamily(String? label) {
    final l = (label ?? '').trim().toLowerCase().replaceAll(' ', '_');
    if (l.isEmpty) return '';
    return EmotionLabels.nuancedToStandard[l] ?? l;
  }

  /// Mood-congruent recall: does the card's feeling share an emotion family
  /// with the character's current emotion?
  static bool moodCongruent(String? cardEmotion, String currentEmotion) {
    final current = emotionFamily(currentEmotion);
    if (current.isEmpty) return false;
    final card = emotionFamily(cardEmotion);
    return card.isNotEmpty && card == current;
  }

  /// Hot-set ordering key: heat, plus the mood boost when congruent.
  static double hotSortKey(JournalMemoryData card, String currentEmotion) =>
      card.heat +
      (moodCongruent(card.emotionLabel, currentEmotion) ? kMoodBoost : 0.0);

  /// Whether any message in [window] carries engine-stamped metadata marking
  /// a significant event (big bond/trust swing, trust repair verdict, Chance
  /// Time event). Drives the event-triggered maintenance pass — deterministic
  /// salience, never model judgment (design §4.2).
  static bool hasSalientEvent(List<ChatMessage> window) {
    for (final m in window) {
      final meta = m.activeMetadata;
      if (meta == null) continue;
      final bond = meta['bond_delta'];
      if (bond is int && bond.abs() >= kEventBondSwing) return true;
      final trust = meta['trust_delta'];
      if (trust is int && trust.abs() >= kEventTrustSwing) return true;
      final repair = meta['trust_repair_verdict'];
      if (repair is String && repair.isNotEmpty) return true;
      final chance = meta['chance_time_event'];
      if (chance is String && chance.isNotEmpty) return true;
    }
    return false;
  }
}
