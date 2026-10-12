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
import 'package:front_porch_ai/ui/pages/edit_character_page/edit_character_draft.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The character editor's Realism section (engine toggles + seeds). Every
/// edit marks [EditCharacterDraft.realismSettingsModified] so Save writes the
/// extensions even while the engine is off.
class EditCharacterRealismSection extends StatelessWidget {
  final EditCharacterDraft draft;
  final VoidCallback onChanged;

  const EditCharacterRealismSection({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  void _edit(VoidCallback fn) {
    fn();
    draft.realismSettingsModified = true;
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playful disclaimer note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.formMasterAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.formMasterAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('😉', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These settings only affect new conversations with this character — '
                  'your existing chats won\'t be changed. No cheating with the relationship values!',
                  style: TextStyle(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Full editable Realism Engine form
        RealismFormSection(
          enabled: d.realismEnabled,
          onEnabledChanged: (v) => _edit(() => d.realismEnabled = v),
          timeOfDay: d.realismTimeOfDay,
          onTimeOfDayChanged: (v) => _edit(() => d.realismTimeOfDay = v),
          dayCount: d.realismDayCount,
          onDayCountChanged: (v) => _edit(() => d.realismDayCount = v),
          storyStartDate: d.realismStoryStartDate,
          onStoryStartDateChanged: (v) =>
              _edit(() => d.realismStoryStartDate = v),
          storyStartTime: d.realismStoryStartTime,
          onStoryStartTimeChanged: (v) =>
              _edit(() => d.realismStoryStartTime = v),
          shortTermBond: d.realismShortTermBond,
          onShortTermBondChanged: (v) =>
              _edit(() => d.realismShortTermBond = v),
          longTermBond: d.realismLongTermBond,
          onLongTermBondChanged: (v) => _edit(() => d.realismLongTermBond = v),
          trustLevel: d.realismTrustLevel,
          onTrustLevelChanged: (v) => _edit(() => d.realismTrustLevel = v),
          emotion: d.realismEmotion,
          onEmotionChanged: (v) => _edit(() => d.realismEmotion = v),
          emotionIntensity: d.realismEmotionIntensity,
          onEmotionIntensityChanged: (v) =>
              _edit(() => d.realismEmotionIntensity = v),
          nsfwCooldownEnabled: d.realismNsfwCooldown,
          onNsfwCooldownChanged: (v) => _edit(() => d.realismNsfwCooldown = v),
          chaosModeEnabled: d.realismChaosMode,
          onChaosModeChanged: (v) => _edit(() => d.realismChaosMode = v),
          realismVerificationEnabled: d.realismVerificationEnabled,
          onRealismVerificationChanged: (v) =>
              _edit(() => d.realismVerificationEnabled = v),
          realismVerificationMaxReprocesses:
              d.realismVerificationMaxReprocesses,
          onRealismVerificationMaxReprocessesChanged: (v) =>
              _edit(() => d.realismVerificationMaxReprocesses = v),
          realismVerificationStrictness: d.realismVerificationStrictness,
          onRealismVerificationStrictnessChanged: (v) =>
              _edit(() => d.realismVerificationStrictness = v),
          needsFormSection: NeedsFormSection(
            enabled: d.realismNeedsSim,
            onEnabledChanged: (v) => _edit(() => d.realismNeedsSim = v),
            enjoysLowHygiene: d.realismEnjoysLowHygiene,
            onEnjoysLowHygieneChanged: (v) =>
                _edit(() => d.realismEnjoysLowHygiene = v),
            needsPace: d.needsPace,
            onNeedsPaceChanged: (v) => _edit(() => d.needsPace = v),
            needsOff: d.needsOff,
            onNeedsOffChanged: (v) => _edit(() => d.needsOff = v),
            baselineHunger: d.needsBaselineHunger,
            onBaselineHungerChanged: (v) =>
                _edit(() => d.needsBaselineHunger = v),
            baselineBladder: d.needsBaselineBladder,
            onBaselineBladderChanged: (v) =>
                _edit(() => d.needsBaselineBladder = v),
            baselineEnergy: d.needsBaselineEnergy,
            onBaselineEnergyChanged: (v) =>
                _edit(() => d.needsBaselineEnergy = v),
            baselineSocial: d.needsBaselineSocial,
            onBaselineSocialChanged: (v) =>
                _edit(() => d.needsBaselineSocial = v),
            baselineFun: d.needsBaselineFun,
            onBaselineFunChanged: (v) => _edit(() => d.needsBaselineFun = v),
            baselineHygiene: d.needsBaselineHygiene,
            onBaselineHygieneChanged: (v) =>
                _edit(() => d.needsBaselineHygiene = v),
            baselineComfort: d.needsBaselineComfort,
            onBaselineComfortChanged: (v) =>
                _edit(() => d.needsBaselineComfort = v),
          ),
        ),
      ],
    );
  }
}
