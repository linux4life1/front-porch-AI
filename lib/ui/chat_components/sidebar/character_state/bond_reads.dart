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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show NsfwService, RelationshipService, RelationshipTiers;
import 'package:front_porch_ai/services/services.dart';

/// One bond bar's numbers: the score, its tier and word, and how far the
/// bar fills toward the next tier.
typedef BondRead = ({
  int score,
  int tier,
  String tierName,
  int target,
  double progress,
});

/// What [BondBars] draws, read for one character: the 1:1 host from the
/// chat's live relationship and arousal scalars, or a group member from
/// their own entry. A group's live scalars hold whoever spoke last, so a
/// member is never read from them.
class BondReads {
  const BondReads({
    required this.shortTerm,
    required this.longTerm,
    required this.trust,
    required this.lustOn,
    required this.lustLevel,
    required this.lustTier,
    required this.lustTierName,
    required this.refractoryChip,
    required this.refractorySoft,
  });

  final BondRead shortTerm;
  final BondRead longTerm;
  final BondRead trust;

  /// The Lust bar shows: Afterglow runs for this character.
  final bool lustOn;
  final int lustLevel;
  final int lustTier;
  final String lustTierName;

  /// Empty while no recovery runs.
  final String refractoryChip;
  final bool refractorySoft;

  factory BondReads.host(ChatService chat) {
    final rel = chat.relationshipService;
    final nsfw = chat.nsfwService;
    return BondReads(
      shortTerm: (
        score: rel.affectionScore,
        tier: rel.relationshipTier,
        tierName: rel.shortTermTierName,
        target: rel.shortTermProgressTarget,
        progress: rel.shortTermProgressPercent,
      ),
      longTerm: (
        score: rel.longTermScore,
        tier: rel.longTermTier,
        tierName: rel.longTermTierName,
        target: rel.longTermProgressTarget,
        progress: rel.longTermProgressPercent,
      ),
      trust: (
        score: rel.trustLevel,
        tier: rel.trustTier,
        tierName: rel.trustTierName,
        target: rel.trustProgressTarget,
        progress: rel.trustProgressPercent,
      ),
      lustOn: nsfw.nsfwCooldownEnabled,
      lustLevel: nsfw.arousalLevel.clamp(-100, 100),
      lustTier: nsfw.arousalTier,
      lustTierName: nsfw.arousalTierName,
      refractoryChip: nsfw.refractoryMinutesRemaining > 0
          ? nsfw.refractoryWords.chip
          : '',
      refractorySoft: nsfw.refractory.soft,
    );
  }

  factory BondReads.member(ChatService chat, CharacterCard member) {
    final affection = chat.getAffectionForGroupCharacter(member);
    final longTerm = chat.getLongTermForGroupCharacter(member);
    final trust = chat.getTrustForGroupCharacter(member);
    final arousal = chat.getArousalForGroupCharacter(member).clamp(-100, 100);
    final lustOn = chat.afterglowRunsFor(member);
    final refractory = lustOn
        ? chat.getRefractoryForGroupCharacter(member)
        : (chip: '', soft: false, minutes: 0);
    final shortTier = RelationshipService.bondTierFor(affection);
    final longTier = RelationshipService.bondTierFor(longTerm);
    final trustTier = RelationshipService.bondTierFor(trust);
    return BondReads(
      shortTerm: (
        score: affection,
        tier: shortTier,
        tierName: RelationshipService.bondTierLabel(shortTier),
        target: RelationshipTiers.bondScaleTarget(affection.abs()),
        progress: RelationshipService.bondScalePercent(affection),
      ),
      longTerm: (
        score: longTerm,
        tier: longTier,
        tierName: RelationshipService.longTermTierLabel(longTier),
        target: RelationshipTiers.bondScaleTarget(longTerm.abs()),
        progress: RelationshipService.bondScalePercent(longTerm),
      ),
      trust: (
        score: trust,
        tier: trustTier,
        tierName: RelationshipService.trustTierLabel(trustTier),
        target: RelationshipTiers.trustScaleTarget(trust.abs()),
        progress: RelationshipService.trustScalePercent(trust),
      ),
      lustOn: lustOn,
      lustLevel: arousal,
      lustTier: NsfwService.arousalTierForLevel(arousal),
      lustTierName: chat.nsfwService.arousalTierNameForLevel(arousal),
      refractoryChip: refractory.chip,
      refractorySoft: refractory.soft,
    );
  }
}
