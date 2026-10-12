// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form/greeting_seed_chrome.dart';
import 'package:front_porch_ai/ui/widgets/needs_clock_off_note.dart';
import 'package:front_porch_ai/ui/widgets/slider_with_input.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

const kGreetingSeedTimes = [
  'dawn',
  'morning',
  'late_morning',
  'afternoon',
  'evening',
  'night',
];
const kGreetingSeedIntensities = ['mild', 'moderate', 'strong'];

/// Time of day, day number and story start date of an alt opening.
class GreetingSeedTimeSection extends StatelessWidget {
  const GreetingSeedTimeSection({
    super.key,
    required this.seed,
    required this.onChanged,
  });

  final GreetingRealismSeed seed;
  final ValueChanged<GreetingRealismSeed?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = seed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        seedHeader(
          context,
          Icons.schedule,
          'Time & Day',
          AppColors.timeDayAccentOf(context),
        ),
        const SizedBox(height: 12),
        seedCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: seedDropdown(
                      context,
                      label: 'Time of Day',
                      value: s.timeOfDay,
                      items: kGreetingSeedTimes,
                      hint: 'inherit (morning)',
                      onChanged: (v) => onChanged(s.copyWith(timeOfDay: v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: seedLabeledField(
                      context,
                      label: 'Day Number',
                      child: seedBoxedField(
                        context,
                        SyncedTextField(
                          value: s.dayCount?.toString() ?? '',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (v) {
                            final n = int.tryParse(v.trim());
                            if (v.trim().isEmpty || n == 0) {
                              onChanged(s.copyWith(dayCount: null));
                            } else if (n != null && n >= 1) {
                              onChanged(s.copyWith(dayCount: n));
                            }
                          },
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          decoration: seedDeco(context, 'inherit (day 1)'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StoryBeginsRow(
                storyStartDate: s.storyStartDate,
                onStoryStartDateChanged: (v) =>
                    onChanged(s.copyWith(storyStartDate: v)),
                storyStartTime: s.storyStartTime,
                onStoryStartTimeChanged: (v) =>
                    onChanged(s.copyWith(storyStartTime: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bond and trust sliders of an alt opening; a cleared slider inherits.
class GreetingSeedRelationshipSection extends StatelessWidget {
  const GreetingSeedRelationshipSection({
    super.key,
    required this.seed,
    required this.onChanged,
  });

  final GreetingRealismSeed seed;
  final ValueChanged<GreetingRealismSeed?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = seed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        seedHeader(
          context,
          Icons.favorite,
          'Relationship',
          AppColors.relationshipAccentOf(context),
        ),
        const SizedBox(height: 12),
        seedCard(
          context,
          Column(
            children: [
              SliderWithInput(
                label: 'Short-term bond',
                value: (s.shortTermBond ?? 0).toDouble(),
                unset: s.shortTermBond == null,
                min: -300,
                max: 300,
                isInteger: true,
                divisions: 600,
                context: context,
                onChanged: (v) =>
                    onChanged(s.copyWith(shortTermBond: v.round())),
                onCleared: () => onChanged(s.copyWith(shortTermBond: null)),
              ),
              SliderWithInput(
                label: 'Long-term bond',
                value: (s.longTermBond ?? 0).toDouble(),
                unset: s.longTermBond == null,
                min: -300,
                max: 300,
                isInteger: true,
                divisions: 600,
                context: context,
                onChanged: (v) =>
                    onChanged(s.copyWith(longTermBond: v.round())),
                onCleared: () => onChanged(s.copyWith(longTermBond: null)),
              ),
              SliderWithInput(
                label: 'Trust',
                value: (s.trustLevel ?? 0).toDouble(),
                unset: s.trustLevel == null,
                min: -100,
                max: 100,
                isInteger: true,
                divisions: 200,
                context: context,
                onChanged: (v) => onChanged(s.copyWith(trustLevel: v.round())),
                onCleared: () => onChanged(s.copyWith(trustLevel: null)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Starting emotion, its intensity and the starting task of an alt opening.
class GreetingSeedEmotionSection extends StatelessWidget {
  const GreetingSeedEmotionSection({
    super.key,
    required this.seed,
    required this.onChanged,
  });

  final GreetingRealismSeed seed;
  final ValueChanged<GreetingRealismSeed?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = seed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        seedHeader(
          context,
          Icons.mood,
          'Starting Emotion',
          AppColors.emotionAccentOf(context),
        ),
        const SizedBox(height: 12),
        seedCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: seedLabeledField(
                      context,
                      label: 'Emotion',
                      child: seedBoxedField(
                        context,
                        SyncedTextField(
                          value: s.characterEmotion ?? '',
                          onChanged: (v) => onChanged(
                            s.copyWith(
                              characterEmotion: v.trim().isEmpty
                                  ? null
                                  : v.trim(),
                            ),
                          ),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          decoration: seedDeco(
                            context,
                            'e.g. furious, warm, guarded',
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: seedDropdown(
                      context,
                      label: 'Intensity',
                      value: s.emotionIntensity,
                      items: kGreetingSeedIntensities,
                      hint: 'inherit (mild)',
                      onChanged: (v) =>
                          onChanged(s.copyWith(emotionIntensity: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              seedLabeledField(
                context,
                label: 'Starting task',
                child: seedBoxedField(
                  context,
                  SyncedTextField(
                    value: s.currentTask ?? '',
                    onChanged: (v) => onChanged(
                      s.copyWith(
                        currentTask: v.trim().isEmpty ? null : v.trim(),
                      ),
                    ),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    decoration: seedDeco(
                      context,
                      'Optional in-voice objective',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final _needs =
    <
      (
        String,
        int? Function(GreetingRealismSeed),
        GreetingRealismSeed Function(GreetingRealismSeed, int),
        GreetingRealismSeed Function(GreetingRealismSeed),
      )
    >[
      (
        'Hunger',
        (s) => s.needsBaselineHunger,
        (s, v) => s.copyWith(needsBaselineHunger: v),
        (s) => s.copyWith(needsBaselineHunger: null),
      ),
      (
        'Bladder',
        (s) => s.needsBaselineBladder,
        (s, v) => s.copyWith(needsBaselineBladder: v),
        (s) => s.copyWith(needsBaselineBladder: null),
      ),
      (
        'Energy',
        (s) => s.needsBaselineEnergy,
        (s, v) => s.copyWith(needsBaselineEnergy: v),
        (s) => s.copyWith(needsBaselineEnergy: null),
      ),
      (
        'Social',
        (s) => s.needsBaselineSocial,
        (s, v) => s.copyWith(needsBaselineSocial: v),
        (s) => s.copyWith(needsBaselineSocial: null),
      ),
      (
        'Fun',
        (s) => s.needsBaselineFun,
        (s, v) => s.copyWith(needsBaselineFun: v),
        (s) => s.copyWith(needsBaselineFun: null),
      ),
      (
        'Hygiene',
        (s) => s.needsBaselineHygiene,
        (s, v) => s.copyWith(needsBaselineHygiene: v),
        (s) => s.copyWith(needsBaselineHygiene: null),
      ),
      (
        'Comfort',
        (s) => s.needsBaselineComfort,
        (s, v) => s.copyWith(needsBaselineComfort: v),
        (s) => s.copyWith(needsBaselineComfort: null),
      ),
    ];

/// Needs baselines of an alt opening; pace stays on the card.
class GreetingSeedNeedsSection extends StatelessWidget {
  const GreetingSeedNeedsSection({
    super.key,
    required this.seed,
    required this.onChanged,
  });

  final GreetingRealismSeed seed;
  final ValueChanged<GreetingRealismSeed?> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = seed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        seedHeader(
          context,
          Icons.battery_std,
          'Needs Simulation',
          AppColors.verifiedAccentOf(context),
        ),
        // Lines up with the header text (18 icon + 8 gap).
        const NeedsClockOffNote(padding: EdgeInsets.only(left: 26, top: 4)),
        const SizedBox(height: 12),
        seedCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Baselines (0–100, higher = more sated). Blank inherits the '
                'card. Pace stays on the card.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 8),
              for (final need in _needs)
                SliderWithInput(
                  label: need.$1,
                  value: (need.$2(s) ?? 80).toDouble(),
                  unset: need.$2(s) == null,
                  min: 0,
                  max: 100,
                  isInteger: true,
                  divisions: 100,
                  context: context,
                  onChanged: (v) => onChanged(need.$3(s, v.round())),
                  onCleared: () => onChanged(need.$4(s)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
