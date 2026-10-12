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

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show BirthdayMath;
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'create_character_draft.dart';
import 'creator_form_fields.dart';
import 'creator_wizard_chrome.dart';

/// Step 4: Porch Life — wardrobe, likes, story clock, Chaos, and the
/// Realism Engine / Needs seeds.
class CreatorRealismStep extends StatelessWidget {
  const CreatorRealismStep({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onGoToStep,
  });

  final CreateCharacterDraft draft;
  final VoidCallback onChanged;
  final ValueChanged<int> onGoToStep;

  /// Applies one field write, then rebuilds the page.
  void _set(VoidCallback write) {
    write();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return CreatorStepFrame(
      children: [
        const CreatorStepTitle('Porch Life'),
        const SizedBox(height: 8),
        const CreatorStepLead(
          'Wardrobe, likes, the story clock and Chaos work with or without '
          'the Realism Engine. Turn the engine on only if you want bond, '
          'trust, mood and Needs to seed the first chat.',
        ),
        const SizedBox(height: 32),

        RealismFormSection(
          enabled: d.realismEnabled,
          onEnabledChanged: (v) => _set(() => d.realismEnabled = v),
          timeOfDay: d.realismTimeOfDay,
          onTimeOfDayChanged: (v) => _set(() => d.realismTimeOfDay = v),
          dayCount: d.realismDayCount,
          onDayCountChanged: (v) => _set(() => d.realismDayCount = v),
          storyStartDate: d.realismStoryStartDate,
          onStoryStartDateChanged: (v) =>
              _set(() => d.realismStoryStartDate = v),
          storyStartTime: d.realismStoryStartTime,
          onStoryStartTimeChanged: (v) =>
              _set(() => d.realismStoryStartTime = v),
          shortTermBond: d.realismShortTermBond,
          onShortTermBondChanged: (v) => _set(() => d.realismShortTermBond = v),
          longTermBond: d.realismLongTermBond,
          onLongTermBondChanged: (v) => _set(() => d.realismLongTermBond = v),
          trustLevel: d.realismTrustLevel,
          onTrustLevelChanged: (v) => _set(() => d.realismTrustLevel = v),
          emotion: d.realismEmotion,
          onEmotionChanged: (v) => _set(() => d.realismEmotion = v),
          emotionIntensity: d.realismEmotionIntensity,
          onEmotionIntensityChanged: (v) =>
              _set(() => d.realismEmotionIntensity = v),
          nsfwCooldownEnabled: d.realismNsfwCooldown,
          onNsfwCooldownChanged: (v) => _set(() => d.realismNsfwCooldown = v),
          chaosModeEnabled: d.realismChaosMode,
          onChaosModeChanged: (v) => _set(() => d.realismChaosMode = v),
          pocketsEnabled: d.realismPocketsEnabled,
          onPocketsEnabledChanged: (v) =>
              _set(() => d.realismPocketsEnabled = v),
          ambitions: d.realismAmbitions,
          onAmbitionsChanged: (v) => _set(() => d.realismAmbitions = v),
          planLines: d.realismPlanLines,
          onPlanLinesChanged: (v) => _set(() => d.realismPlanLines = v),
          occupation: d.realismOccupation,
          onOccupationChanged: (v) => _set(() => d.realismOccupation = v),
          occupationBrief: d.realismOccupationBrief,
          onOccupationBriefChanged: (v) =>
              _set(() => d.realismOccupationBrief = v),
          hours: d.realismHours,
          onHoursChanged: (v) => _set(() => d.realismHours = v),
          workDays: d.realismWorkDays,
          onWorkDaysChanged: (v) => _set(() => d.realismWorkDays = v),
          birthday: d.realismBirthday,
          onBirthdayChanged: (v) => _set(() => d.realismBirthday = v),
          birthdayAgeAsOf: BirthdayMath.ageAsOfStory(d.realismStoryStartDate),
          likes: d.realismLikes,
          onLikesChanged: (v) => _set(() => d.realismLikes = v),
          dislikes: d.realismDislikes,
          onDislikesChanged: (v) => _set(() => d.realismDislikes = v),
          intimateInto: d.realismIntimateInto,
          onIntimateIntoChanged: (v) => _set(() => d.realismIntimateInto = v),
          intimateNotInto: d.realismIntimateNotInto,
          onIntimateNotIntoChanged: (v) =>
              _set(() => d.realismIntimateNotInto = v),
          showIntimate: adultThemesEnabledOf(context),
          worn: d.realismWorn,
          onWornChanged: (v) => _set(() => d.realismWorn = v),
          carrying: d.realismCarrying,
          onCarryingChanged: (v) => _set(() => d.realismCarrying = v),
          realismVerificationEnabled: d.realismVerificationEnabled,
          onRealismVerificationChanged: (v) =>
              _set(() => d.realismVerificationEnabled = v),
          realismVerificationMaxReprocesses:
              d.realismVerificationMaxReprocesses,
          onRealismVerificationMaxReprocessesChanged: (v) =>
              _set(() => d.realismVerificationMaxReprocesses = v),
          realismVerificationStrictness: d.realismVerificationStrictness,
          onRealismVerificationStrictnessChanged: (v) =>
              _set(() => d.realismVerificationStrictness = v),
          needsFormSection: NeedsFormSection(
            enabled: d.realismNeedsSim,
            onEnabledChanged: (v) => _set(() => d.realismNeedsSim = v),
            enjoysLowHygiene: d.realismEnjoysLowHygiene,
            onEnjoysLowHygieneChanged: (v) =>
                _set(() => d.realismEnjoysLowHygiene = v),
            needsPace: d.needsPace,
            onNeedsPaceChanged: (v) => _set(() => d.needsPace = v),
            needsOff: d.needsOff,
            onNeedsOffChanged: (v) => _set(() => d.needsOff = v),
            baselineHunger: d.needsBaselineHunger,
            onBaselineHungerChanged: (v) =>
                _set(() => d.needsBaselineHunger = v),
            baselineBladder: d.needsBaselineBladder,
            onBaselineBladderChanged: (v) =>
                _set(() => d.needsBaselineBladder = v),
            baselineEnergy: d.needsBaselineEnergy,
            onBaselineEnergyChanged: (v) =>
                _set(() => d.needsBaselineEnergy = v),
            baselineSocial: d.needsBaselineSocial,
            onBaselineSocialChanged: (v) =>
                _set(() => d.needsBaselineSocial = v),
            baselineFun: d.needsBaselineFun,
            onBaselineFunChanged: (v) => _set(() => d.needsBaselineFun = v),
            baselineHygiene: d.needsBaselineHygiene,
            onBaselineHygieneChanged: (v) =>
                _set(() => d.needsBaselineHygiene = v),
            baselineComfort: d.needsBaselineComfort,
            onBaselineComfortChanged: (v) =>
                _set(() => d.needsBaselineComfort = v),
          ),
        ),

        CreatorNavButtons(
          currentStep: 4,
          nameController: draft.nameController,
          onGoToStep: onGoToStep,
        ),
      ],
    );
  }
}
