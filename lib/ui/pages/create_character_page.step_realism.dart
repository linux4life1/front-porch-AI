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
//
// Manual creator: the Realism step (engine toggles + seed values).
// Extracted verbatim from create_character_page.dart (god-file campaign,
// Tranche A); `part of` the same library, so privates and the mandatory
// step-indicator wizard flow are unchanged.

part of 'create_character_page.dart';

extension _CreateCharacterRealismStep on _CreateCharacterPageState {
  Widget _buildRealismStep() {
    return Center(
      key: const ValueKey('realism'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Porch Life',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Wardrobe, likes, the story clock and Chaos work with or without '
                'the Realism Engine. Turn the engine on only if you want bond, '
                'trust, mood and Needs to seed the first chat.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              RealismFormSection(
                enabled: _realismEnabled,
                onEnabledChanged: (v) =>
                    rebuildState(() => _realismEnabled = v),
                timeOfDay: _realismTimeOfDay,
                onTimeOfDayChanged: (v) =>
                    rebuildState(() => _realismTimeOfDay = v),
                dayCount: _realismDayCount,
                onDayCountChanged: (v) =>
                    rebuildState(() => _realismDayCount = v),
                storyStartDate: _realismStoryStartDate,
                onStoryStartDateChanged: (v) =>
                    rebuildState(() => _realismStoryStartDate = v),
                storyStartTime: _realismStoryStartTime,
                onStoryStartTimeChanged: (v) =>
                    rebuildState(() => _realismStoryStartTime = v),
                shortTermBond: _realismShortTermBond,
                onShortTermBondChanged: (v) =>
                    rebuildState(() => _realismShortTermBond = v),
                longTermBond: _realismLongTermBond,
                onLongTermBondChanged: (v) =>
                    rebuildState(() => _realismLongTermBond = v),
                trustLevel: _realismTrustLevel,
                onTrustLevelChanged: (v) =>
                    rebuildState(() => _realismTrustLevel = v),
                emotion: _realismEmotion,
                onEmotionChanged: (v) =>
                    rebuildState(() => _realismEmotion = v),
                emotionIntensity: _realismEmotionIntensity,
                onEmotionIntensityChanged: (v) =>
                    rebuildState(() => _realismEmotionIntensity = v),
                nsfwCooldownEnabled: _realismNsfwCooldown,
                onNsfwCooldownChanged: (v) =>
                    rebuildState(() => _realismNsfwCooldown = v),
                chaosModeEnabled: _realismChaosMode,
                onChaosModeChanged: (v) =>
                    rebuildState(() => _realismChaosMode = v),
                ambitions: _realismAmbitions,
                onAmbitionsChanged: (v) =>
                    rebuildState(() => _realismAmbitions = v),
                planLines: _realismPlanLines,
                onPlanLinesChanged: (v) =>
                    rebuildState(() => _realismPlanLines = v),
                occupation: _realismOccupation,
                onOccupationChanged: (v) =>
                    rebuildState(() => _realismOccupation = v),
                hours: _realismHours,
                onHoursChanged: (v) =>
                    rebuildState(() => _realismHours = v),
                likes: _realismLikes,
                onLikesChanged: (v) => rebuildState(() => _realismLikes = v),
                dislikes: _realismDislikes,
                onDislikesChanged: (v) =>
                    rebuildState(() => _realismDislikes = v),
                intimateInto: _realismIntimateInto,
                onIntimateIntoChanged: (v) =>
                    rebuildState(() => _realismIntimateInto = v),
                intimateNotInto: _realismIntimateNotInto,
                onIntimateNotIntoChanged: (v) =>
                    rebuildState(() => _realismIntimateNotInto = v),
                showIntimate: adultThemesEnabledOf(context),
                worn: _realismWorn,
                onWornChanged: (v) => rebuildState(() => _realismWorn = v),
                carrying: _realismCarrying,
                onCarryingChanged: (v) =>
                    rebuildState(() => _realismCarrying = v),
                realismVerificationEnabled: _realismVerificationEnabled,
                onRealismVerificationChanged: (v) =>
                    rebuildState(() => _realismVerificationEnabled = v),
                realismVerificationMaxReprocesses:
                    _realismVerificationMaxReprocesses,
                onRealismVerificationMaxReprocessesChanged: (v) =>
                    rebuildState(() => _realismVerificationMaxReprocesses = v),
                realismVerificationStrictness: _realismVerificationStrictness,
                onRealismVerificationStrictnessChanged: (v) =>
                    rebuildState(() => _realismVerificationStrictness = v),
                needsFormSection: NeedsFormSection(
                  enabled: _realismNeedsSim,
                  onEnabledChanged: (v) =>
                      rebuildState(() => _realismNeedsSim = v),
                  enjoysLowHygiene: _realismEnjoysLowHygiene,
                  onEnjoysLowHygieneChanged: (v) =>
                      rebuildState(() => _realismEnjoysLowHygiene = v),
                  needsSimStrength: 1, // default, not editable in creator
                  baselineHunger: _needsBaselineHunger,
                  onBaselineHungerChanged: (v) =>
                      rebuildState(() => _needsBaselineHunger = v),
                  baselineBladder: _needsBaselineBladder,
                  onBaselineBladderChanged: (v) =>
                      rebuildState(() => _needsBaselineBladder = v),
                  baselineEnergy: _needsBaselineEnergy,
                  onBaselineEnergyChanged: (v) =>
                      rebuildState(() => _needsBaselineEnergy = v),
                  baselineSocial: _needsBaselineSocial,
                  onBaselineSocialChanged: (v) =>
                      rebuildState(() => _needsBaselineSocial = v),
                  baselineFun: _needsBaselineFun,
                  onBaselineFunChanged: (v) =>
                      rebuildState(() => _needsBaselineFun = v),
                  baselineHygiene: _needsBaselineHygiene,
                  onBaselineHygieneChanged: (v) =>
                      rebuildState(() => _needsBaselineHygiene = v),
                  baselineComfort: _needsBaselineComfort,
                  onBaselineComfortChanged: (v) =>
                      rebuildState(() => _needsBaselineComfort = v),
                  decayHunger: _needsDecayHunger,
                  onDecayHungerChanged: (v) =>
                      rebuildState(() => _needsDecayHunger = v),
                  decayBladder: _needsDecayBladder,
                  onDecayBladderChanged: (v) =>
                      rebuildState(() => _needsDecayBladder = v),
                  decayEnergy: _needsDecayEnergy,
                  onDecayEnergyChanged: (v) =>
                      rebuildState(() => _needsDecayEnergy = v),
                  decaySocial: _needsDecaySocial,
                  onDecaySocialChanged: (v) =>
                      rebuildState(() => _needsDecaySocial = v),
                  decayFun: _needsDecayFun,
                  onDecayFunChanged: (v) =>
                      rebuildState(() => _needsDecayFun = v),
                  decayHygiene: _needsDecayHygiene,
                  onDecayHygieneChanged: (v) =>
                      rebuildState(() => _needsDecayHygiene = v),
                  decayComfort: _needsDecayComfort,
                  onDecayComfortChanged: (v) =>
                      rebuildState(() => _needsDecayComfort = v),
                ),
              ),

              _buildNavButtons(currentStep: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 5: REVIEW & CREATE
  // ═══════════════════════════════════════════════════════════════
}
