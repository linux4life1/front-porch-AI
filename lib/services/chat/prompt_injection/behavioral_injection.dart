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

import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';

/// Fixation + spatial-stance fragments for the words-only state block
/// (docs/design/prompt-state-injection.md §3). Both are free-text fields (may
/// legitimately contain digits); both are salience-gated to silence.
///
/// GROUP-SAFETY CONTRACT: this leaf reads RelationshipService SCALARS, which
/// are per-speaker-valid at assembly time because `_loadGroupRealismIntoScalars`
/// (chat_service_realism_dance.dart) calls
/// `loadRelationshipScalarsForSpeaker(charId)` — which copies activeFixation,
/// fixationLifespan, AND spatialStance for the upcoming speaker — before any
/// prompt is built. If that dance ever stops covering these fields, this
/// fragment must switch to defensive group-map reads like
/// relationship_injection's tiers.
///
/// The old BLIND TRUST / MISTRUST "Behavioral Anchor" blocks are DELETED:
/// they fired on raw trustLevel thresholds (±100 scale) that map to only
/// moderate tiers, directly contradicting the trust-calibration ladder
/// rendered beside them ("absolute, unconditional trust" at a level the
/// ladder calls "genuinely trusts"). The calibration ladder in
/// relationship_injection.dart is now the single trust voice.
class BehavioralInjection {
  final RelationshipService relationshipService;
  final bool Function() getRealismEnabled;
  final String Function()? getOccupation;
  final String Function()? getHours;
  final String Function()? getOccupationBrief;
  final List<int>? Function()? getWorkDays;
  final int Function()? getClockMinutes;
  final int Function()? getWeekday;
  final bool Function()? getIsGroup;

  BehavioralInjection({
    required this.relationshipService,
    required this.getRealismEnabled,
    this.getOccupation,
    this.getHours,
    this.getOccupationBrief,
    this.getWorkDays,
    this.getClockMinutes,
    this.getWeekday,
    this.getIsGroup,
  });

  /// The background thought — MENTAL state, and it says so itself: "colors
  /// mood and reactions". It belongs beside the mood and emotion lines it
  /// claims to colour.
  String buildFixationInjection() {
    if (!getRealismEnabled()) return '';
    if (relationshipService.activeFixation.isEmpty ||
        relationshipService.fixationLifespan <= 0) {
      return '';
    }
    return 'On the mind lately: "${relationshipService.activeFixation}" — a '
        'background thought that colors mood and reactions; it never '
        'overrides the scene, surfacing openly only if conversation '
        'naturally touches it.';
  }

  /// Where they physically are — SCENE staging, and it says so itself: "ground
  /// actions in this". It belongs with the time and weather lines, because the
  /// model needs to know where everyone is standing before it decides what
  /// happens, not after it has already written the scene.
  String buildPositionInjection() {
    if (!getRealismEnabled()) return '';
    final stance = relationshipService.spatialStance.trim();
    final group = getIsGroup?.call() ?? false;
    final occ = getOccupation?.call() ?? '';
    final hours = getHours?.call() ?? '';
    final brief = getOccupationBrief?.call() ?? '';
    final where = derivePresence(
      occupation: occ,
      hours: hours,
      clockMinutes: getClockMinutes?.call() ?? 0,
      weekday: getWeekday?.call() ?? DateTime.tuesday,
      workDays: getWorkDays?.call(),
      inScene: inSceneForPresence(
        stance: stance,
        withUser: relationshipService.withUser,
      ),
    );
    if (where == PresenceWhere.atWork) {
      return atWorkPromptLine(occupation: occ, occupationBrief: brief);
    }
    if (!group && where == PresenceWhere.away) {
      final here = stance.isEmpty ? '' : ' ($stance)';
      return 'Away from {{user}}$here. Write from there.';
    }
    final identity = where == PresenceWhere.withYou
        ? offShiftWorkIdentityLine(
            occupation: occ,
            occupationBrief: brief,
            hours: hours,
            weekday: getWeekday?.call() ?? DateTime.tuesday,
            workDays: getWorkDays?.call(),
            clockMinutes: getClockMinutes?.call() ?? 0,
          )
        : '';
    if (stance.isEmpty) return identity;
    final position =
        'Position: $stance — ground actions in '
        'this, but moving and changing position is fine as the scene demands.';
    if (identity.isEmpty) return position;
    return '$identity\n$position';
  }

  /// Both mechanics as one fragment — the original shape.
  ///
  /// The composer no longer uses this: the two lines above are unrelated to
  /// each other (one is a thought, one is a floor position) and belong in
  /// different parts of the block, so it emits them separately. Kept because it
  /// is the surface `prompt_injection_test.dart` asserts against, and it
  /// delegates rather than duplicating, so the two paths cannot drift.
  String buildBehavioralMechanicsInjection() => [
    buildFixationInjection(),
    buildPositionInjection(),
  ].where((l) => l.isNotEmpty).join('\n');
}
