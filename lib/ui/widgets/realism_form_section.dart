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

  static const _timeOptions = [
    'dawn',
    'morning',
    'late_morning',
    'afternoon',
    'evening',
    'night',
  ];

  static const _intensityOptions = ['mild', 'moderate', 'strong'];

  String _formatTimeLabel(String value) {
    return value
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _shortTermTierName(int score) {
    if (score >= 80) return 'Devoted';
    if (score >= 50) return 'Affectionate';
    if (score >= 20) return 'Warm';
    if (score >= 5) return 'Friendly';
    if (score >= -4) return 'Neutral';
    if (score >= -19) return 'Cool';
    if (score >= -49) return 'Distant';
    if (score >= -79) return 'Hostile';
    return 'Despised';
  }

  String _longTermTierName(int score) {
    if (score >= 80) return 'Soulbound';
    if (score >= 50) return 'Deep Bond';
    if (score >= 20) return 'Close';
    if (score >= 5) return 'Familiar';
    if (score >= -4) return 'Acquaintance';
    if (score >= -19) return 'Uneasy';
    if (score >= -49) return 'Estranged';
    if (score >= -79) return 'Broken';
    return 'Nemesis';
  }

  String _trustLevelName(int level) {
    if (level >= 80) return 'Absolute Trust';
    if (level >= 50) return 'Deep Trust';
    if (level >= 20) return 'Trusting';
    if (level >= 5) return 'Cautious Trust';
    if (level >= -4) return 'Neutral';
    if (level >= -19) return 'Wary';
    if (level >= -49) return 'Suspicious';
    if (level >= -79) return 'Paranoid';
    return 'Absolute Distrust';
  }

  Color _bondColor(int score) {
    if (score >= 20) return AppColors.bondHigh;
    if (score >= 0) return AppColors.bondMid;
    if (score >= -19) return AppColors.bondLow;
    return AppColors.bondNeg;
  }

  Color _trustColor(int level) {
    if (level >= 20) return AppColors.trustHigh;
    if (level >= 0) return AppColors.bondMid;
    if (level >= -19) return AppColors.bondLow;
    return AppColors.bondNeg;
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
        // ── Master Toggle (can be hidden in group creator where the group-level toggle controls it) ──
        if (showMasterEnabledToggle)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: enabled
                    ? AppColors.formMasterAccent.withValues(alpha: 0.4)
                    : AppColors.borderOf(context),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: enabled
                        ? AppColors.formMasterAccent.withValues(alpha: 0.2)
                        : AppColors.surfaceContainerOf(
                            context,
                          ).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.psychology,
                    color: enabled
                        ? AppColors.formMasterAccent
                        : AppColors.iconSecondary(context),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enable Realism Engine',
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? 'Character will start with pre-configured state'
                            : 'Wardrobe, likes, time and Chaos still apply. '
                              'Bond, mood and Needs stay off.',
                        style: TextStyle(
                          color: enabled
                              ? AppColors.formMasterAccent
                              : AppColors.textTertiary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onEnabledChanged,
                  activeTrackColor: AppColors.formMasterAccent.withValues(
                    alpha: 0.5,
                  ),
                  activeThumbColor: AppColors.formMasterAccent,
                ),
              ],
            ),
          ),

        // Time / Chaos / identity chips are Porch Life — they run without
        // the engine. Do not hide them behind [enabled].
        const SizedBox(height: 20),

        if (showTimeAndDay) ...[
            // Time & Day Section
            _sectionHeader(
              Icons.schedule,
              'Time & Day',
              AppColors.timeDayAccent,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Row(
                children: [
                  // Time of Day dropdown
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Time of Day', style: labelStyle),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                          child: DropdownButton<String>(
                            value: timeOfDay,
                            isExpanded: true,
                            dropdownColor: AppColors.surfaceContainerOf(
                              context,
                            ),
                            underline: const SizedBox(),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                            ),
                            items: _timeOptions
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(_formatTimeLabel(t)),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) onTimeOfDayChanged(v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Day Number
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Day Number', style: labelStyle),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.borderOf(context),
                            ),
                          ),
                          // SyncedTextField, not a TextField with an inline
                          // controller: every caller rebuilds this section on
                          // each keystroke, and a controller built in build()
                          // loses the caret (and any IME composition) every
                          // frame.
                          child: SyncedTextField(
                            value: dayCount.toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                            ),
                            onChanged: (v) {
                              final n = int.tryParse(v);
                              if (n != null && n >= 1) onDayCountChanged(n);
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
        ], // end showTimeAndDay

        if (enabled) ...[
          const SizedBox(height: 20),

          // Needs Simulation (rendered separately when provided by caller).
          // ignore: use_null_aware_elements — '?' doesn't work in children lists
          if (needsFormSection != null) needsFormSection!,

          // Relationship Section
          _sectionHeader(
            Icons.favorite,
            'Relationship',
            AppColors.relationshipAccent,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              children: [
                // Short-Term Bond
                _sliderRow(
                  label: 'Short-Term Bond',
                  value: shortTermBond,
                  min: -300,
                  max: 300,
                  tierName: _shortTermTierName(shortTermBond),
                  color: _bondColor(shortTermBond),
                  onChanged: (v) => onShortTermBondChanged(v.round()),
                  context: context,
                ),
                const SizedBox(height: 16),
                // Long-Term Bond
                _sliderRow(
                  label: 'Long-Term Bond',
                  value: longTermBond,
                  min: -300,
                  max: 300,
                  tierName: _longTermTierName(longTermBond),
                  color: _bondColor(longTermBond),
                  onChanged: (v) => onLongTermBondChanged(v.round()),
                  context: context,
                ),
                const SizedBox(height: 16),
                // Trust Level
                _sliderRow(
                  label: 'Trust Level',
                  value: trustLevel,
                  min: -100,
                  max: 100,
                  tierName: _trustLevelName(trustLevel),
                  color: _trustColor(trustLevel),
                  onChanged: (v) => onTrustLevelChanged(v.round()),
                  context: context,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Emotion Section
          _sectionHeader(
            Icons.mood,
            'Starting Emotion',
            AppColors.emotionAccent,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Row(
              children: [
                // Emotion text field
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Emotion', style: labelStyle),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        // See the Day Number field: the controller must be
                        // owned, or mid-word edits jump to the end of the text.
                        child: SyncedTextField(
                          value: emotion,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          onChanged: onEmotionChanged,
                          decoration: InputDecoration(
                            hintText: 'e.g. curious, guarded, amused',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary(
                                context,
                              ).withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Intensity selector
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Intensity', style: labelStyle),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerOf(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                        ),
                        child: DropdownButton<String>(
                          value: emotionIntensity,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerOf(context),
                          underline: const SizedBox(),
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          items: _intensityOptions
                              .map(
                                (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    i[0].toUpperCase() + i.substring(1),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) onEmotionIntensityChanged(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Optional Toggles
          _sectionHeader(
            Icons.tune,
            'Optional Features',
            AppColors.optionalAccent,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              children: [
                if (showNsfwCooldownToggle) ...[
                  buildToggleRow(
                    icon: Icons.thermostat,
                    label: 'Afterglow (intimacy pacing)',
                    subtitle: 'Realistic arousal/refractory mechanics',
                    value: nsfwCooldownEnabled,
                    onChanged: onNsfwCooldownChanged,
                    context: context,
                  ),
                  if (showChaosToggle)
                    Divider(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                      height: 24,
                    ),
                ],
                if (showChaosToggle) ...[
                  buildToggleRow(
                    icon: Icons.casino,
                    label: 'Chaos Mode (Chance Time)',
                    subtitle: 'Random narrative events during roleplay',
                    value: chaosModeEnabled,
                    onChanged: onChaosModeChanged,
                    context: context,
                  ),
                ],

                // Realism Verification toggle (last optional; independent of needs).
                // Uses same _toggleRow + card styling. Sliders for passes/strictness are in Details dialog per spec.
                if (showVerificationToggle) ...[
                  if (showChaosToggle || showNsfwCooldownToggle)
                    Divider(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                      height: 24,
                    ),
                  buildToggleRow(
                    icon: Icons.verified_user,
                    label: 'Realism Verification (Director/Verifier)',
                    subtitle:
                        'Optional director thread validates realism deltas + needs JSON; supplies corrections + reason or re-feeds for reprocessing (extra eval cost; strong models recommended)',
                    value: realismVerificationEnabled,
                    onChanged: onRealismVerificationChanged,
                    context: context,
                  ),
                  // Compact sliders for the 2 tunables (shown in forms including group per-member when toggle visible).
                  // 1-5 range; onChanged provided by caller (pages, group seed); defaults safe if not.
                  const SizedBox(height: 8),
                  Text(
                    'Max reprocess passes: $realismVerificationMaxReprocesses',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11,
                    ),
                  ),
                  Slider(
                    value: realismVerificationMaxReprocesses.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$realismVerificationMaxReprocesses',
                    onChanged: (d) => onRealismVerificationMaxReprocessesChanged
                        ?.call(d.round()),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Strictness (1=lenient … 5=strict): $realismVerificationStrictness',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11,
                    ),
                  ),
                  Slider(
                    value: realismVerificationStrictness.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$realismVerificationStrictness',
                    onChanged: (d) =>
                        onRealismVerificationStrictnessChanged?.call(d.round()),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (showChaosToggle && !enabled) ...[
          const SizedBox(height: 20),
          _sectionHeader(
            Icons.tune,
            'Optional Features',
            AppColors.optionalAccent,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: buildToggleRow(
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
        IdentityChipLists(
          ambitions: ambitions,
          onAmbitionsChanged: onAmbitionsChanged,
          planLines: planLines,
          onPlanLinesChanged: onPlanLinesChanged,
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
        ),
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required String tierName,
    required Color color,
    required ValueChanged<double> onChanged,
    required BuildContext context,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$tierName ($value)',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: AppColors.borderOf(
              context,
            ).withValues(alpha: 0.3),
            thumbColor: color,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// Shared (public static for DRY across form + edit dialog manual rows).
  /// AppColors exclusive in new authority/Optional/verif surfaces per re-grep (verifiedAccentOf for on-state + resolve/helpers; withValues(alpha) only on resolved AppColors values; no raw color literals (Colors or hex) in authority/Optional/verif *executable* code; comments filtered from hygiene greps).
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
}
