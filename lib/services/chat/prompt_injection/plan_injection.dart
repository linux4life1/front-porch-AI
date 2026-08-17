// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Planner fragment. Parked: live injection stays off until time +
// objectives + journal exist. Character writes the plan from personality.

import 'package:front_porch_ai/models/models.dart';
import 'speaker_resolution.dart';

/// Scene-plan fragment. '' when the speaker wings it or there is no card.
class PlanInjection with SpeakerCardResolver {
  final String? Function() getTodayLine;
  @override
  final CharacterCard? Function() getActiveCharacter;
  @override
  final bool Function() getIsGroupNonObserverMode;
  @override
  final String Function() getCurrentSpeakerIdForRealism;
  @override
  final List<CharacterCard> Function() getGroupCharacters;
  @override
  final String Function(CharacterCard) getCharacterIdFromCard;

  PlanInjection({
    required this.getTodayLine,
    required this.getActiveCharacter,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
  });

  String buildPlanInjection() {
    // Parked. Live write stays off until time + objectives + journal exist.
    // Do not gate on planHabit. Joe killed Plans / Wings it.
    return '';
  }
}
