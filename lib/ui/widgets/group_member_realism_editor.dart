// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

/// The per-member realism + needs baseline editor — the `RealismFormSection` +
/// `NeedsFormSection` block shared by the group creator and the group editor so
/// both edit a member's realism/needs baseline the same way (one UX standard,
/// one wiring).
///
/// Reads every value from [seed] (a member's realism seed map: `affection`,
/// `trust`, `emotion`, `emotionIntensity`, `verification*`,
/// `needsPace`, `needsOff`, `enjoysLowHygiene`, `needsBaseline*`, …) and
/// reports each edit through [onUpdate] as a `{key: value}` delta that the caller
/// merges back into the seed (and rebuilds). Needs enabled/disabled is group-wide,
/// so it is threaded through [needsEnabled] / [onNeedsEnabledChanged].
class GroupMemberRealismEditor extends StatelessWidget {
  final Map<String, dynamic> seed;
  final bool needsEnabled;
  final ValueChanged<bool> onNeedsEnabledChanged;
  final void Function(Map<String, dynamic> delta) onUpdate;

  const GroupMemberRealismEditor({
    super.key,
    required this.seed,
    required this.needsEnabled,
    required this.onNeedsEnabledChanged,
    required this.onUpdate,
  });

  int _i(String key, int fallback) => (seed[key] as num?)?.toInt() ?? fallback;
  String _s(String key, String fallback) => (seed[key] as String?) ?? fallback;

  @override
  Widget build(BuildContext context) {
    return RealismFormSection(
      enabled: true,
      onEnabledChanged: (_) {}, // controlled by the group master toggle above
      timeOfDay: _s('timeOfDay', 'morning'),
      onTimeOfDayChanged: (v) => onUpdate({'timeOfDay': v}),
      dayCount: _i('dayCount', 1),
      onDayCountChanged: (v) => onUpdate({'dayCount': v}),
      shortTermBond: _i('affection', 35),
      onShortTermBondChanged: (v) => onUpdate({'affection': v}),
      longTermBond: _i('trust', 40),
      onLongTermBondChanged: (v) => onUpdate({'trust': v}),
      trustLevel: _i('trust', 40),
      onTrustLevelChanged: (v) => onUpdate({'trust': v}),
      emotion: _s('emotion', 'neutral'),
      onEmotionChanged: (v) => onUpdate({'emotion': v}),
      emotionIntensity: _s('emotionIntensity', 'mild'),
      onEmotionIntensityChanged: (v) => onUpdate({'emotionIntensity': v}),
      // Group-level concepts (there's a master Chaos toggle at the top of the
      // section) — forced off + hidden to avoid duplicate per-member toggles.
      nsfwCooldownEnabled: false,
      onNsfwCooldownChanged: (_) {},
      chaosModeEnabled: false,
      onChaosModeChanged: (_) {},
      showNsfwCooldownToggle: false,
      showChaosToggle: false,
      showTimeAndDay: false,
      showMasterEnabledToggle: false,
      realismVerificationEnabled:
          (seed['verificationEnabled'] as bool?) ?? false,
      onRealismVerificationChanged: (v) => onUpdate({'verificationEnabled': v}),
      realismVerificationMaxReprocesses:
          (seed['verificationMaxReprocesses'] as int?) ?? 1,
      onRealismVerificationMaxReprocessesChanged: (v) =>
          onUpdate({'verificationMaxReprocesses': v}),
      realismVerificationStrictness:
          (seed['verificationStrictness'] as int?) ?? 3,
      onRealismVerificationStrictnessChanged: (v) =>
          onUpdate({'verificationStrictness': v}),
      showVerificationToggle: true,
      needsFormSection: NeedsFormSection(
        enabled: needsEnabled,
        onEnabledChanged: onNeedsEnabledChanged,
        enjoysLowHygiene: (seed['enjoysLowHygiene'] as bool?) ?? false,
        onEnjoysLowHygieneChanged: (v) => onUpdate({'enjoysLowHygiene': v}),
        needsPace: (seed['needsPace'] as String?) ?? 'normal',
        onNeedsPaceChanged: (v) => onUpdate({'needsPace': v}),
        needsOff: [
          for (final item in (seed['needsOff'] as List?) ?? const [])
            if (item is String) item,
        ],
        onNeedsOffChanged: (v) => onUpdate({'needsOff': v}),
        baselineHunger: _i('needsBaselineHunger', 80),
        onBaselineHungerChanged: (v) => onUpdate({'needsBaselineHunger': v}),
        baselineBladder: _i('needsBaselineBladder', 80),
        onBaselineBladderChanged: (v) => onUpdate({'needsBaselineBladder': v}),
        baselineEnergy: _i('needsBaselineEnergy', 80),
        onBaselineEnergyChanged: (v) => onUpdate({'needsBaselineEnergy': v}),
        baselineSocial: _i('needsBaselineSocial', 80),
        onBaselineSocialChanged: (v) => onUpdate({'needsBaselineSocial': v}),
        baselineFun: _i('needsBaselineFun', 80),
        onBaselineFunChanged: (v) => onUpdate({'needsBaselineFun': v}),
        baselineHygiene: _i('needsBaselineHygiene', 80),
        onBaselineHygieneChanged: (v) => onUpdate({'needsBaselineHygiene': v}),
        baselineComfort: _i('needsBaselineComfort', 80),
        onBaselineComfortChanged: (v) => onUpdate({'needsBaselineComfort': v}),
      ),
    );
  }
}
