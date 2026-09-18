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
import 'package:flutter/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

part 'realism_form_section.engine.dart';
part 'realism_form_section.porch.dart';
part 'realism_form_section.controls.dart';

/// Shared Realism + Porch Life authoring form.
///
/// The engine master switch only hides bond/emotion/needs/afterglow/verifier
/// — those need the Realism Engine at runtime. Time, Chaos, wardrobe,
/// ambitions and likes are Porch Life and stay editable with the engine off
/// (docs: porch_life_tab / feature independence).
class RealismFormSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final String timeOfDay;
  final ValueChanged<String> onTimeOfDayChanged;
  final int dayCount;
  final ValueChanged<int> onDayCountChanged;

  // Story Calendar authoring (story-calendar.md §3a). Null callbacks hide the
  // block (surfaces that only expose the friendly period+day pickers).
  // storyStartDate: ISO date, null = "the day the chat starts".
  // storyStartTime: "HH:MM" exact opening clock, null = period default.
  final String? storyStartDate;
  final ValueChanged<String?>? onStoryStartDateChanged;
  final String? storyStartTime;
  final ValueChanged<String?>? onStoryStartTimeChanged;
  final int shortTermBond;
  final ValueChanged<int> onShortTermBondChanged;
  final int longTermBond;
  final ValueChanged<int> onLongTermBondChanged;
  final int trustLevel;
  final ValueChanged<int> onTrustLevelChanged;
  final String emotion;
  final ValueChanged<String> onEmotionChanged;
  final String emotionIntensity;
  final ValueChanged<String> onEmotionIntensityChanged;
  final bool nsfwCooldownEnabled;
  final ValueChanged<bool> onNsfwCooldownChanged;
  final bool chaosModeEnabled;
  final ValueChanged<bool> onChaosModeChanged;

  /// Long-term ambitions, edited as chips (approved sketch §4). Optional so
  /// the surfaces that have no ambitions state yet — the group-member card,
  /// for one — keep working untouched; absent means the section is simply not
  /// rendered rather than rendered empty and dead.
  final List<String>? ambitions;
  final ValueChanged<List<String>>? onAmbitionsChanged;

  /// Plan-line sentences. Same optional-pair convention as [ambitions].
  final List<String>? planLines;
  final ValueChanged<List<String>>? onPlanLinesChanged;

  /// Occupation + hours + job brief. Same optional-pair convention as [planLines].
  final String? occupation;
  final ValueChanged<String>? onOccupationChanged;
  final String? occupationBrief;
  final ValueChanged<String>? onOccupationBriefChanged;
  final String? hours;
  final ValueChanged<String>? onHoursChanged;
  final List<int>? workDays;
  final ValueChanged<List<int>>? onWorkDaysChanged;

  final String? birthday;
  final ValueChanged<String>? onBirthdayChanged;
  final DateTime? birthdayAgeAsOf;

  /// Likes & Dislikes, and the 18+ pair — same optional-pair convention as
  /// [ambitions]: pass values + callback or the section is absent, so surfaces
  /// that predate these fields keep compiling and rendering unchanged.
  /// [showIntimate] carries the install's adult-themes switch.
  final List<String>? likes;
  final ValueChanged<List<String>>? onLikesChanged;
  final List<String>? dislikes;
  final ValueChanged<List<String>>? onDislikesChanged;
  final List<String>? intimateInto;
  final ValueChanged<List<String>>? onIntimateIntoChanged;
  final List<String>? intimateNotInto;
  final ValueChanged<List<String>>? onIntimateNotIntoChanged;
  final bool showIntimate;

  /// Starting Pockets & Wardrobe, as chip text (`sundress (rain-soaked)`).
  /// Same optional-pair convention again — the two group-member editors call
  /// this widget with no identity params at all.
  final List<String>? worn;
  final ValueChanged<List<String>>? onWornChanged;
  final List<String>? carrying;
  final ValueChanged<List<String>>? onCarryingChanged;

  // Realism Verification (Director/Verifier) toggle — shown under Optional Features like other optionals.
  // Sliders for max reprocesses + strictness live in the Details dialog (right-click edit); form surfaces the toggle for creator/edit flows.
  final bool realismVerificationEnabled;
  final ValueChanged<bool> onRealismVerificationChanged;
  final bool showVerificationToggle;

  // Optional verif tunables (1-5); rendered as compact sliders after the toggle when showVerificationToggle.
  // Allows 3 controls in group per-member expanders + main forms (dialog also has independent for right-click).
  final int realismVerificationMaxReprocesses;
  final ValueChanged<int>? onRealismVerificationMaxReprocessesChanged;
  final int realismVerificationStrictness;
  final ValueChanged<int>? onRealismVerificationStrictnessChanged;

  // Optional needs form (rendered separately from Optional Features).
  // When provided, the caller is responsible for rendering this widget
  // (e.g. in the character creator). When null, no needs UI is rendered.
  final Widget? needsFormSection;

  // Visibility controls (for group creator where some features are global only)
  final bool showNsfwCooldownToggle;
  final bool showChaosToggle;
  final bool showTimeAndDay;
  final bool showMasterEnabledToggle;

  const RealismFormSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.timeOfDay,
    required this.onTimeOfDayChanged,
    required this.dayCount,
    required this.onDayCountChanged,
    required this.shortTermBond,
    required this.onShortTermBondChanged,
    required this.longTermBond,
    required this.onLongTermBondChanged,
    required this.trustLevel,
    required this.onTrustLevelChanged,
    required this.emotion,
    required this.onEmotionChanged,
    required this.emotionIntensity,
    required this.onEmotionIntensityChanged,
    required this.nsfwCooldownEnabled,
    required this.onNsfwCooldownChanged,
    required this.chaosModeEnabled,
    required this.onChaosModeChanged,
    this.ambitions,
    this.onAmbitionsChanged,
    this.planLines,
    this.onPlanLinesChanged,
    this.occupation,
    this.onOccupationChanged,
    this.occupationBrief,
    this.onOccupationBriefChanged,
    this.hours,
    this.onHoursChanged,
    this.workDays,
    this.onWorkDaysChanged,
    this.birthday,
    this.onBirthdayChanged,
    this.birthdayAgeAsOf,
    this.likes,
    this.onLikesChanged,
    this.dislikes,
    this.onDislikesChanged,
    this.intimateInto,
    this.onIntimateIntoChanged,
    this.intimateNotInto,
    this.onIntimateNotIntoChanged,
    this.showIntimate = false,
    this.worn,
    this.onWornChanged,
    this.carrying,
    this.onCarryingChanged,
    required this.realismVerificationEnabled,
    required this.onRealismVerificationChanged,
    this.showVerificationToggle = true,
    this.realismVerificationMaxReprocesses = 1,
    this.onRealismVerificationMaxReprocessesChanged,
    this.realismVerificationStrictness = 3,
    this.onRealismVerificationStrictnessChanged,
    this.needsFormSection,
    this.showNsfwCooldownToggle = true,
    this.showChaosToggle = true,
    this.showTimeAndDay = true,
    this.showMasterEnabledToggle = true,
    this.storyStartDate,
    this.onStoryStartDateChanged,
    this.storyStartTime,
    this.onStoryStartTimeChanged,
  });

  /// Shared gap above Relationship and Starting Emotion headers.
  static const double sectionHeaderGap = 20;

  /// 20px gap + Relationship header + card. OPEN_SECTION=edit scrolls this
  /// so the gap sits below the Details TabBar instead of clipping under it.
  static const Key relationshipHeaderBlockKey = Key(
    'relationship-header-block',
  );

  static const _timeOptions = [
    'dawn',
    'morning',
    'late_morning',
    'afternoon',
    'evening',
    'night',
  ];

  static const _intensityOptions = ['mild', 'moderate', 'strong'];

  /// Shared (public static for DRY across form + edit dialog manual rows).
  static Widget buildToggleRow({
    required IconData icon,
    required String label,
    String subtitle = '',
    required bool value,
    required ValueChanged<bool> onChanged,
    required BuildContext context,
  }) {
    final onColor = AppColors.verifiedAccentOf(context);
    return Row(
      children: [
        Icon(
          icon,
          color: value ? onColor : AppColors.iconSecondary(context),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: value
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: onColor.withValues(alpha: 0.5),
          activeThumbColor: onColor,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._engineMasterToggle(context),
        ..._porchTime(context, labelStyle),
        ..._engineWhenOn(context, labelStyle),
        ..._porchAfterEngine(context),
      ],
    );
  }
}
