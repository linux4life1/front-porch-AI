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
import 'package:front_porch_ai/services/chat/group_lite.dart';
import 'package:front_porch_ai/services/chat/relationship_tiers.dart';

/// How one group member feels about another, on the bond scale (±300).
typedef GroupFeeling = ({
  String memberId,
  String name,
  int score,
  int tier,
  String tierName,

  /// The next-tier target the bar fills toward (the denominator the bond
  /// bars show), not the +/-300 ceiling.
  int target,
  double progress,
});

/// The Group Dynamics read: one member's feelings toward each other full
/// member. The data is the hidden `relationships` map the char-to-char judge
/// and the keyword floor keep (`cast_feelings_judge.dart`); the sidebars show
/// it read-only, on desktop and the PWA alike.
class GroupDynamics {
  const GroupDynamics({required this.tracked, required this.feelings});

  /// Nothing to show for this member (a lite guest, or no group).
  static const none = GroupDynamics(tracked: true, feelings: []);

  /// False when the group is outside 2 to 4 full members: feelings between
  /// characters are not tracked then, and the sidebar says so rather than
  /// listing neutral rows nothing moves.
  final bool tracked;

  /// Toward each other full member, in roster order.
  final List<GroupFeeling> feelings;

  /// Build the read for [focused] from the roster and [relationships] (the
  /// member's `relationships` map, keyed by [idOf] of the other member). A
  /// member the map does not hold yet reads neutral, as the seeding does.
  static GroupDynamics of({
    required CharacterCard focused,
    required List<CharacterCard> roster,
    required Map<String, dynamic>? relationships,
    required String Function(CharacterCard) idOf,
  }) {
    if (focused.isLite) return none;
    if (!shouldTrackInterCharacterAmong(roster)) {
      return const GroupDynamics(tracked: false, feelings: []);
    }
    final selfId = idOf(focused);
    final out = <GroupFeeling>[];
    for (final other in fullGroupCharacters(roster)) {
      final id = idOf(other);
      if (id == selfId) continue;
      final raw = relationships?[id];
      final score = raw is num ? raw.round().clamp(-300, 300) : 0;
      final tier = RelationshipTiers.bondTierFor(score);
      out.add((
        memberId: id,
        name: other.name,
        score: score,
        tier: tier,
        tierName: RelationshipTiers.bondTierLabel(tier),
        target: RelationshipTiers.bondScaleTarget(score.abs()),
        progress: RelationshipTiers.bondScalePercent(score),
      ));
    }
    return GroupDynamics(tracked: true, feelings: out);
  }
}
