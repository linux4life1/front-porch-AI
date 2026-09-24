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

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/services.dart';

/// Realism-READ leaf for [ChatFacade] (web server). Pure reads of existing
/// [ChatService] getters — no simulation changes — so it never affects
/// Realism/Needs behavior.
///
/// The host [snapshot] (1:1) and the group-member branch of [participantRealism]
/// are intentionally co-located here: they are the 1:1-vs-group parity pair, and
/// keeping them in one file makes it obvious that a member's stats must read
/// IDENTICALLY to the host (same tiers/bars, same needs gating).
class ChatRealismRead {
  ChatRealismRead(this._chat);

  final ChatService _chat;

  /// Realism for a single cast participant (focus-scoped sidebar). Host →
  /// full snapshot; group member → per-member scores via the group getters;
  /// lite guest → realism disabled. Returns null if the id isn't in the cast.
  Map<String, dynamic>? participantRealism(String participantId) {
    for (final p in _chat.cast) {
      if (p.id != participantId) continue;
      if (!p.realismEnabled) return {'realismEnabled': false};
      if (p.isHost) return {'realismEnabled': true, ...snapshot()};
      final card = p.card;
      final rel = _chat.relationshipService;
      final emotion = _chat.getEmotionForGroupCharacter(card) ?? '';
      final intensity = _chat.getEmotionIntensityForGroupCharacter(card) ?? '';
      final bondScore = _chat.getAffectionForGroupCharacter(card);
      final trustLevel = _chat.getTrustForGroupCharacter(card);
      final arousalLevel = _chat.getArousalForGroupCharacter(card);
      // Per-member tier names + bar percents via the shared relationship/nsfw
      // scale helpers, so a group member's stats read IDENTICALLY to the 1:1 host
      // (no blank tiers / empty bars).
      //
      // Long-term WAS hard-coded to 0 here under a comment claiming it "isn't
      // tracked per member". It is: the per-speaker load/save pair moves
      // longTermScore through the group blob every turn and it grows on its own
      // cadence. Web therefore showed every member as Neutral/0 forever while
      // desktop showed a real number.
      final longTermScore = _chat.getLongTermForGroupCharacter(card);
      return {
        'realismEnabled': true,
        'bond': {
          'score': bondScore,
          'tier': rel.bondTierNameForScore(bondScore),
          'percent': rel.bondPercentForScore(bondScore),
        },
        'longTerm': {
          'score': longTermScore,
          'tier': rel.longTermTierNameForScore(longTermScore),
          'percent': rel.bondPercentForScore(longTermScore),
        },
        'trust': {
          'level': trustLevel,
          'tier': rel.trustTierNameForLevel(trustLevel),
          'percent': rel.trustPercentForLevel(trustLevel),
        },
        'emotion': emotion,
        'emotionIntensity': intensity,
        'mood': intensity.isNotEmpty ? '$emotion ($intensity)' : emotion,
        'arousal': {
          'level': arousalLevel,
          'tier': _chat.nsfwService.arousalTierNameForLevel(arousalLevel),
        },
        'fixation': _chat.getFixationForGroupCharacter(card) ?? '',
        // Gate needs on the SAME flag the host path uses (see snapshot()):
        // getNeedsForGroupCharacter always returns a full vector while group
        // realism is active, so without this a member would still show needs
        // bars after Needs is toggled off — 1:1↔group display parity.
        'needsEnabled': _chat.needsSimEnabled,
        'needs': _chat.needsSimEnabled
            ? visibleNeeds(
                _chat.getNeedsForGroupCharacter(card),
                card.frontPorchExtensions?.needsOff ?? const [],
              )
            : const <String, int>{},
      };
    }
    return null;
  }

  /// Current Realism Engine state for the web sidebar — mirrors the desktop
  /// realism section (bond/long-term/trust + tiers/progress, mood/emotion,
  /// arousal, fixation, and the 7 Sims-style needs). Pure reads of existing
  /// service getters; no simulation changes, so 1:1/group parity is unaffected.
  Map<String, dynamic> snapshot() {
    final rel = _chat.relationshipService;
    final nsfw = _chat.nsfwService;
    return {
      // Whether the engine is actually running. Disabling realism deliberately
      // PRESERVES the last numbers rather than zeroing them, so without this
      // flag the web panel had no way to tell a live score from a frozen one —
      // it rendered the full dashboard forever while desktop replaced it with
      // "Realism Mode is off". Additive and nullable-safe for older clients.
      'realismEnabled': _chat.realismEnabled,
      'bond': {
        'score': rel.affectionScore,
        'tier': rel.shortTermTierName,
        'percent': rel.shortTermProgressPercent,
      },
      'longTerm': {
        'score': rel.longTermScore,
        'tier': rel.longTermTierName,
        'percent': rel.longTermProgressPercent,
      },
      'trust': {
        'level': rel.trustLevel,
        'tier': rel.trustTierName,
        'percent': rel.trustProgressPercent,
      },
      'emotion': _chat.characterEmotion,
      'emotionIntensity': _chat.emotionIntensity,
      'mood': _chat.moodLabel,
      'arousal': {'level': nsfw.arousalLevel, 'tier': nsfw.arousalTierName},
      'fixation': rel.activeFixation,
      'needsEnabled': _chat.needsSimEnabled,
      'needs': _chat.needsSimEnabled
          ? visibleNeeds(
              _chat.needsSimulation.vector,
              _chat.activeCharacter?.frontPorchExtensions?.needsOff ?? const [],
            )
          : <String, int>{},
    };
  }
}
