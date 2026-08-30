// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/chat/birthday.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Step 4: seed the Realism Engine's initial state for the generated character.
/// Restored from the god file's `_buildRealismStep` — the full form is now wired
/// to CreatorState instead of the dummy hardcoded values the refactor shipped.
class RealismStep extends StatelessWidget {
  final CreatorState state;

  const RealismStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    // Generation-error fallback: if the LLM produced nothing, offer a retry
    // back to the config step (the wizard advanced here regardless).
    if (state.generatedCard == null) {
      return Center(
        key: const ValueKey('realism-error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.resolve(
                context,
                Colors.redAccent,
                Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Generation failed. The LLM did not produce valid output.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                state.generationPreview = '';
                state.currentStep = 2;
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formMasterAccent,
                foregroundColor: AppColors.onChaosAccent,
              ),
            ),
          ],
        ),
      );
    }

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
                enabled: state.realismStepEnabled,
                onEnabledChanged: (v) {
                  state.realismStepEnabled = v;
                  state.notify();
                },
                timeOfDay: state.realismTimeOfDay,
                onTimeOfDayChanged: (v) {
                  state.realismTimeOfDay = v;
                  state.notify();
                },
                dayCount: state.realismDayCount,
                onDayCountChanged: (v) {
                  state.realismDayCount = v;
                  state.notify();
                },
                storyStartDate: state.realismStoryStartDate,
                onStoryStartDateChanged: (v) {
                  state.realismStoryStartDate = v;
                  state.notify();
                },
                storyStartTime: state.realismStoryStartTime,
                onStoryStartTimeChanged: (v) {
                  state.realismStoryStartTime = v;
                  state.notify();
                },
                shortTermBond: state.realismShortTermBond,
                onShortTermBondChanged: (v) {
                  state.realismShortTermBond = v;
                  state.notify();
                },
                longTermBond: state.realismLongTermBond,
                onLongTermBondChanged: (v) {
                  state.realismLongTermBond = v;
                  state.notify();
                },
                trustLevel: state.realismTrustLevel,
                onTrustLevelChanged: (v) {
                  state.realismTrustLevel = v;
                  state.notify();
                },
                emotion: state.realismEmotion,
                onEmotionChanged: (v) {
                  state.realismEmotion = v;
                  state.notify();
                },
                emotionIntensity: state.realismEmotionIntensity,
                onEmotionIntensityChanged: (v) {
                  state.realismEmotionIntensity = v;
                  state.notify();
                },
                nsfwCooldownEnabled: state.realismNsfwCooldown,
                onNsfwCooldownChanged: (v) {
                  state.realismNsfwCooldown = v;
                  state.notify();
                },
                chaosModeEnabled: state.realismChaosMode,
                onChaosModeChanged: (v) {
                  state.realismChaosMode = v;
                  state.notify();
                },
                ambitions: state.realismAmbitions,
                onAmbitionsChanged: (v) {
                  state.realismAmbitions = v;
                  state.notify();
                },
                planLines: state.realismPlanLines,
                onPlanLinesChanged: (v) {
                  state.realismPlanLines = v;
                  state.notify();
                },
                occupation: state.realismOccupation,
                onOccupationChanged: (v) {
                  state.realismOccupation = v;
                  state.notify();
                },
                occupationBrief: state.realismOccupationBrief,
                onOccupationBriefChanged: (v) {
                  state.realismOccupationBrief = v;
                  state.notify();
                },
                hours: state.realismHours,
                onHoursChanged: (v) {
                  state.realismHours = v;
                  state.notify();
                },
                workDays: state.realismWorkDays,
                onWorkDaysChanged: (v) {
                  state.realismWorkDays = v;
                  state.notify();
                },
                birthday: state.realismBirthday,
                onBirthdayChanged: (v) {
                  state.realismBirthday = v;
                  state.notify();
                },
                birthdayAgeAsOf: BirthdayMath.ageAsOfStory(
                  state.realismStoryStartDate,
                ),
                likes: state.realismLikes,
                onLikesChanged: (v) {
                  state.realismLikes = v;
                  state.notify();
                },
                dislikes: state.realismDislikes,
                onDislikesChanged: (v) {
                  state.realismDislikes = v;
                  state.notify();
                },
                intimateInto: state.realismIntimateInto,
                onIntimateIntoChanged: (v) {
                  state.realismIntimateInto = v;
                  state.notify();
                },
                intimateNotInto: state.realismIntimateNotInto,
                onIntimateNotIntoChanged: (v) {
                  state.realismIntimateNotInto = v;
                  state.notify();
                },
                showIntimate: adultThemesEnabledOf(context),
                worn: state.realismWorn,
                onWornChanged: (v) {
                  state.realismWorn = v;
                  state.notify();
                },
                carrying: state.realismCarrying,
                onCarryingChanged: (v) {
                  state.realismCarrying = v;
                  state.notify();
                },
                realismVerificationEnabled: state.realismVerificationEnabled,
                onRealismVerificationChanged: (v) {
                  state.realismVerificationEnabled = v;
                  state.saveState();
                  state.notify();
                },
                realismVerificationMaxReprocesses:
                    state.realismVerificationMaxReprocesses,
                onRealismVerificationMaxReprocessesChanged: (v) {
                  state.realismVerificationMaxReprocesses = v;
                  state.saveState();
                  state.notify();
                },
                realismVerificationStrictness:
                    state.realismVerificationStrictness,
                onRealismVerificationStrictnessChanged: (v) {
                  state.realismVerificationStrictness = v;
                  state.saveState();
                  state.notify();
                },
                // Full needs editor (enable, enjoys-low-hygiene, custom 0-100
                // baselines + per-tick decay rates) — same widget the character
                // editor uses, so AI-created characters can ship custom needs
                // tuning. Strength stays at the default (not exposed here).
                needsFormSection: NeedsFormSection(
                  enabled: state.realismNeedsSim,
                  onEnabledChanged: (v) {
                    state.realismNeedsSim = v;
                    state.notify();
                  },
                  enjoysLowHygiene: state.realismEnjoysLowHygiene,
                  onEnjoysLowHygieneChanged: (v) {
                    state.realismEnjoysLowHygiene = v;
                    state.notify();
                  },
                  needsSimStrength: 1,
                  baselineHunger: state.needsBaselineHunger,
                  onBaselineHungerChanged: (v) {
                    state.needsBaselineHunger = v;
                    state.notify();
                  },
                  baselineBladder: state.needsBaselineBladder,
                  onBaselineBladderChanged: (v) {
                    state.needsBaselineBladder = v;
                    state.notify();
                  },
                  baselineEnergy: state.needsBaselineEnergy,
                  onBaselineEnergyChanged: (v) {
                    state.needsBaselineEnergy = v;
                    state.notify();
                  },
                  baselineSocial: state.needsBaselineSocial,
                  onBaselineSocialChanged: (v) {
                    state.needsBaselineSocial = v;
                    state.notify();
                  },
                  baselineFun: state.needsBaselineFun,
                  onBaselineFunChanged: (v) {
                    state.needsBaselineFun = v;
                    state.notify();
                  },
                  baselineHygiene: state.needsBaselineHygiene,
                  onBaselineHygieneChanged: (v) {
                    state.needsBaselineHygiene = v;
                    state.notify();
                  },
                  baselineComfort: state.needsBaselineComfort,
                  onBaselineComfortChanged: (v) {
                    state.needsBaselineComfort = v;
                    state.notify();
                  },
                  decayHunger: state.needsDecayHunger,
                  onDecayHungerChanged: (v) {
                    state.needsDecayHunger = v;
                    state.notify();
                  },
                  decayBladder: state.needsDecayBladder,
                  onDecayBladderChanged: (v) {
                    state.needsDecayBladder = v;
                    state.notify();
                  },
                  decayEnergy: state.needsDecayEnergy,
                  onDecayEnergyChanged: (v) {
                    state.needsDecayEnergy = v;
                    state.notify();
                  },
                  decaySocial: state.needsDecaySocial,
                  onDecaySocialChanged: (v) {
                    state.needsDecaySocial = v;
                    state.notify();
                  },
                  decayFun: state.needsDecayFun,
                  onDecayFunChanged: (v) {
                    state.needsDecayFun = v;
                    state.notify();
                  },
                  decayHygiene: state.needsDecayHygiene,
                  onDecayHygieneChanged: (v) {
                    state.needsDecayHygiene = v;
                    state.notify();
                  },
                  decayComfort: state.needsDecayComfort,
                  onDecayComfortChanged: (v) {
                    state.needsDecayComfort = v;
                    state.notify();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
