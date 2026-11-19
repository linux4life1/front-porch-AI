// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Planner fragment. Character writes the plan from personality.
// Live hold is on when the planner flag is on. No habit gate.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';
import 'speaker_resolution.dart';

/// Scene-plan fragment. '' when the planner flag is off or there is no card.
class PlanInjection with SpeakerCardResolver {
  final String? Function() getTodayLine;
  final bool Function() getPlannerEnabled;
  final int Function()? getClockMinutes;
  final int Function()? getWeekday;
  final bool Function()? getHeldAway;
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
    required this.getPlannerEnabled,
    this.getClockMinutes,
    this.getWeekday,
    required this.getActiveCharacter,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    this.getHeldAway,
  });

  String buildPlanInjection() {
    if (!getPlannerEnabled()) return '';
    final card = speakerCard();
    if (card == null) return '';
    if (getClockMinutes != null) {
      final ext = card.frontPorchExtensions;
      // The hold rides with the read (H1): a held member is not at work
      // for this gate even mid-shift, so their plan line still shows.
      final atWork =
          derivePresence(
            occupation: ext?.occupation ?? '',
            hours: ext?.hours ?? '',
            clockMinutes: getClockMinutes!(),
            weekday: getWeekday?.call() ?? DateTime.tuesday,
            workDays: ext?.workDays,
            heldAway: getHeldAway?.call() ?? false,
            inScene: true,
          ) ==
          PresenceWhere.atWork;
      if (atWork) return '';
    }
    final held = getTodayLine()?.trim();
    if (held == null || held.isEmpty) return '';
    return 'Today\'s plan: "$held".';
  }
}
