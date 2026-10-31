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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';

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

  /// Recovery profile (recovery overhaul PR 2). Optional pair — the two
  /// group-member editors pass neither, which is also the ruling made
  /// visible: a member follows their own card, so an override control there
  /// would lie. `sex` is read-only feed for the "resolves to" line.
  final RecoveryProfile? recovery;
  final ValueChanged<RecoveryProfile>? onRecoveryChanged;
  final String sex;

  /// Creation flows only: suggests a preset from the authored intimacy
  /// notes, confirmed by the author, never applied silently.
  final bool showChargenSuggestion;

  /// The card's Afterglow switch: how new chats with this character start.
  /// Character editors only; group editors pass no setter.
  final bool afterglowEnabled;
  final ValueChanged<bool>? onAfterglowChanged;

  /// Starting Pockets & Wardrobe, as chip text (`sundress (rain-soaked)`).
  /// Same optional-pair convention again — the two group-member editors call
  /// this widget with no identity params at all.
  final List<String>? worn;
  final ValueChanged<List<String>>? onWornChanged;
  final List<String>? carrying;
  final ValueChanged<List<String>>? onCarryingChanged;

  /// Per-character Pockets & Wardrobe. Forwarded onto the Wearing / Carrying
  /// panel (IdentityChipLists). Optional pair — group-member editors that
  /// do not author this flag keep compiling unchanged. A lone pair without
  /// worn/carrying does not render (no orphan Details section).
  final bool? pocketsEnabled;
  final ValueChanged<bool>? onPocketsEnabledChanged;

  /// Shown right above the Wearing / Carrying panel. The AI creator's
  /// outfit hint after a new first message; null everywhere else.
  final Widget? wardrobeNotice;

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
    this.recovery,
    this.onRecoveryChanged,
    this.sex = '',
    this.showChargenSuggestion = false,
    this.afterglowEnabled = true,
    this.onAfterglowChanged,
    this.worn,
    this.onWornChanged,
    this.carrying,
    this.onCarryingChanged,
    this.pocketsEnabled,
    this.onPocketsEnabledChanged,
    this.wardrobeNotice,
    required this.realismVerificationEnabled,
    required this.onRealismVerificationChanged,
    this.showVerificationToggle = true,
    this.realismVerificationMaxReprocesses = 1,
    this.onRealismVerificationMaxReprocessesChanged,
    this.realismVerificationStrictness = 3,
    this.onRealismVerificationStrictnessChanged,
    this.needsFormSection,
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

  /// Shared (public static for DRY across form + edit dialog manual rows).
  static Widget buildToggleRow({
    required IconData icon,
    required String label,
    String subtitle = '',
    required bool value,
    required ValueChanged<bool> onChanged,
    required BuildContext context,
  }) => buildRealismToggleRow(
    icon: icon,
    label: label,
    subtitle: subtitle,
    value: value,
    onChanged: onChanged,
    context: context,
  );

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: context.creatorPalette?.prose ?? AppColors.textSecondary(context),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Master Toggle (can be hidden in group creator where the group-level toggle controls it) ──
        if (showMasterEnabledToggle)
          RealismMasterToggle(
            enabled: enabled,
            onEnabledChanged: onEnabledChanged,
          ),
        // Time / Chaos / identity chips are Porch Life — they run without
        // the engine. Do not hide them behind [enabled].
        const SizedBox(height: 20),
        if (showTimeAndDay) ...[
          RealismSectionHeader(
            Icons.schedule,
            'Time & Day',
            context.creatorPalette?.amber ?? AppColors.timeDayAccent,
          ),
          const SizedBox(height: 12),
          RealismTimeDayCard(
            timeOfDay: timeOfDay,
            onTimeOfDayChanged: onTimeOfDayChanged,
            dayCount: dayCount,
            onDayCountChanged: onDayCountChanged,
            labelStyle: labelStyle,
          ),
          if (onStoryStartDateChanged != null) ...[
            const SizedBox(height: 8),
            StoryBeginsRow(
              storyStartDate: storyStartDate,
              onStoryStartDateChanged: onStoryStartDateChanged!,
              storyStartTime: storyStartTime,
              onStoryStartTimeChanged: onStoryStartTimeChanged,
            ),
          ],
        ],
        if (enabled) ...[
          // Needs Simulation (rendered separately when provided by caller).
          // ignore: use_null_aware_elements — '?' doesn't work in children lists
          if (needsFormSection != null) needsFormSection!,

          // Relationship Section — one [sectionHeaderGap] above the header.
          Column(
            key: relationshipHeaderBlockKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: sectionHeaderGap),
              RealismSectionHeader(
                Icons.favorite,
                'Relationship',
                context.creatorPalette?.amber ?? AppColors.relationshipAccent,
              ),
              const SizedBox(height: 12),
              RealismRelationshipCard(
                shortTermBond: shortTermBond,
                onShortTermBondChanged: onShortTermBondChanged,
                longTermBond: longTermBond,
                onLongTermBondChanged: onLongTermBondChanged,
                trustLevel: trustLevel,
                onTrustLevelChanged: onTrustLevelChanged,
              ),
            ],
          ),
          const SizedBox(height: sectionHeaderGap),
          RealismSectionHeader(
            Icons.mood,
            'Starting Emotion',
            context.creatorPalette?.amber ?? AppColors.emotionAccent,
          ),
          const SizedBox(height: 12),
          RealismEmotionCard(
            emotion: emotion,
            onEmotionChanged: onEmotionChanged,
            emotionIntensity: emotionIntensity,
            onEmotionIntensityChanged: onEmotionIntensityChanged,
            labelStyle: labelStyle,
          ),
          const SizedBox(height: 20),
          RealismSectionHeader(
            Icons.tune,
            'Optional Features',
            context.creatorPalette?.amber ??
                AppColors.optionalAccentOf(context),
          ),
          const SizedBox(height: 12),
          RealismOptionalFeaturesCard(
            chaosModeEnabled: chaosModeEnabled,
            onChaosModeChanged: onChaosModeChanged,
            realismVerificationEnabled: realismVerificationEnabled,
            onRealismVerificationChanged: onRealismVerificationChanged,
            realismVerificationMaxReprocesses:
                realismVerificationMaxReprocesses,
            onRealismVerificationMaxReprocessesChanged:
                onRealismVerificationMaxReprocessesChanged,
            realismVerificationStrictness: realismVerificationStrictness,
            onRealismVerificationStrictnessChanged:
                onRealismVerificationStrictnessChanged,
            showChaosToggle: showChaosToggle,
            showVerificationToggle: showVerificationToggle,
            recovery: recovery,
            onRecoveryChanged: onRecoveryChanged,
            sex: sex,
            intimateInto: intimateInto ?? const [],
            intimateNotInto: intimateNotInto ?? const [],
            showChargenSuggestion: showChargenSuggestion,
            afterglowEnabled: afterglowEnabled,
            onAfterglowChanged: onAfterglowChanged,
          ),
        ],
        if (showChaosToggle && !enabled) ...[
          const SizedBox(height: 20),
          RealismSectionHeader(
            Icons.tune,
            'Optional Features',
            context.creatorPalette?.amber ??
                AppColors.optionalAccentOf(context),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.creatorPalette?.card ?? AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    context.creatorPalette?.line ?? AppColors.borderOf(context),
              ),
            ),
            child: buildRealismToggleRow(
              icon: Icons.casino,
              label: 'Chaos Mode (Chance Time)',
              subtitle: 'Random narrative events during roleplay',
              value: chaosModeEnabled,
              onChanged: onChaosModeChanged,
              context: context,
            ),
          ),
        ],

        // Identity / wardrobe — Porch Life, not the engine.
        // Per-character Pockets enable rides IdentityChipLists (top of the
        // Wearing / Carrying card). Do not re-add an orphan section here.
        IdentityChipLists(
          ambitions: ambitions,
          onAmbitionsChanged: onAmbitionsChanged,
          planLines: planLines,
          onPlanLinesChanged: onPlanLinesChanged,
          occupation: occupation,
          onOccupationChanged: onOccupationChanged,
          occupationBrief: occupationBrief,
          onOccupationBriefChanged: onOccupationBriefChanged,
          hours: hours,
          onHoursChanged: onHoursChanged,
          workDays: workDays,
          onWorkDaysChanged: onWorkDaysChanged,
          birthday: birthday,
          onBirthdayChanged: onBirthdayChanged,
          birthdayAgeAsOf: birthdayAgeAsOf,
          likes: likes,
          onLikesChanged: onLikesChanged,
          dislikes: dislikes,
          onDislikesChanged: onDislikesChanged,
          intimateInto: intimateInto,
          onIntimateIntoChanged: onIntimateIntoChanged,
          intimateNotInto: intimateNotInto,
          onIntimateNotIntoChanged: onIntimateNotIntoChanged,
          showIntimate: showIntimate,
          worn: worn,
          onWornChanged: onWornChanged,
          carrying: carrying,
          onCarryingChanged: onCarryingChanged,
          pocketsEnabled: pocketsEnabled,
          onPocketsEnabledChanged: onPocketsEnabledChanged,
          wardrobeNotice: wardrobeNotice,
        ),
      ],
    );
  }
}
