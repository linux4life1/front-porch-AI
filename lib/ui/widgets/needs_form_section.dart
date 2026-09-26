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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

/// Standalone Needs Simulation configuration form.
///
/// Extracted from RealismFormSection to keep that widget under the 500 LOC cap.
/// Used by the character creator/editor to configure per-need baselines.
class NeedsFormSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool enjoysLowHygiene;
  final ValueChanged<bool> onEnjoysLowHygieneChanged;
  final String needsPace;
  final ValueChanged<String>? onNeedsPaceChanged;
  final List<String> needsOff;
  final ValueChanged<List<String>>? onNeedsOffChanged;

  // Per-need baselines (0-100).
  final int baselineHunger;
  final ValueChanged<int> onBaselineHungerChanged;
  final int baselineBladder;
  final ValueChanged<int> onBaselineBladderChanged;
  final int baselineEnergy;
  final ValueChanged<int> onBaselineEnergyChanged;
  final int baselineSocial;
  final ValueChanged<int> onBaselineSocialChanged;
  final int baselineFun;
  final ValueChanged<int> onBaselineFunChanged;
  final int baselineHygiene;
  final ValueChanged<int> onBaselineHygieneChanged;
  final int baselineComfort;
  final ValueChanged<int> onBaselineComfortChanged;

  const NeedsFormSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.enjoysLowHygiene,
    required this.onEnjoysLowHygieneChanged,
    this.needsPace = 'normal',
    this.onNeedsPaceChanged,
    this.needsOff = const [],
    this.onNeedsOffChanged,
    required this.baselineHunger,
    required this.onBaselineHungerChanged,
    required this.baselineBladder,
    required this.onBaselineBladderChanged,
    required this.baselineEnergy,
    required this.onBaselineEnergyChanged,
    required this.baselineSocial,
    required this.onBaselineSocialChanged,
    required this.baselineFun,
    required this.onBaselineFunChanged,
    required this.baselineHygiene,
    required this.onBaselineHygieneChanged,
    required this.baselineComfort,
    required this.onBaselineComfortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──
        const SizedBox(height: 24),
        Text(
          'Needs Simulation',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),

        // ── Card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Master toggle
              RealismFormSection.buildToggleRow(
                icon: Icons.battery_std,
                label: 'Needs Simulation',
                subtitle:
                    'Hunger etc. (higher = more sated/less urgent; 100=full, 0=critical) — influences prompts & behavior when low',
                value: enabled,
                onChanged: onEnabledChanged,
                context: context,
              ),

              // ── Gated content (only when Needs Simulation is ON) ──
              if (enabled) ...[
                const SizedBox(height: 16),

                // Per-need baseline sliders
                _needsSlider(
                  label: 'Hunger',
                  needKey: 'hunger',
                  value: baselineHunger,
                  onChanged: onBaselineHungerChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Bladder',
                  needKey: 'bladder',
                  value: baselineBladder,
                  onChanged: onBaselineBladderChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Energy',
                  needKey: 'energy',
                  value: baselineEnergy,
                  onChanged: onBaselineEnergyChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Social',
                  needKey: 'social',
                  value: baselineSocial,
                  onChanged: onBaselineSocialChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Fun',
                  needKey: 'fun',
                  value: baselineFun,
                  onChanged: onBaselineFunChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Hygiene',
                  needKey: 'hygiene',
                  value: baselineHygiene,
                  onChanged: onBaselineHygieneChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Comfort',
                  needKey: 'comfort',
                  value: baselineComfort,
                  onChanged: onBaselineComfortChanged,
                  context: context,
                ),

                const SizedBox(height: 16),
                Divider(
                  color: AppColors.borderOf(context).withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),

                // Enjoys low hygiene
                RealismFormSection.buildToggleRow(
                  icon: Icons.water_drop_outlined,
                  label: 'Enjoys low hygiene',
                  subtitle:
                      'Character prefers being sweaty, musky, or filthy (inverts hygiene behavior)',
                  value: enjoysLowHygiene,
                  onChanged: onEnjoysLowHygieneChanged,
                  context: context,
                ),

                const SizedBox(height: 16),
                Divider(
                  color: AppColors.borderOf(context).withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),

                Text(
                  'Pace',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'How fast needs drop as time passes. A meal or a bath stays the same.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'sloth', label: Text('Sloth')),
                    ButtonSegment(value: 'normal', label: Text('Normal')),
                    ButtonSegment(value: 'fast', label: Text('Fast')),
                  ],
                  selected: {needsPace},
                  onSelectionChanged: onNeedsPaceChanged == null
                      ? null
                      : (next) => onNeedsPaceChanged!(next.first),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _needsSlider({
    required String label,
    required String needKey,
    required int value,
    required ValueChanged<int> onChanged,
    required BuildContext context,
  }) {
    final alive = !needsOff.contains(needKey);
    final mainSlider = Column(
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
            Text(
              '$value / 100',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            Switch(
              value: alive,
              onChanged: onNeedsOffChanged == null
                  ? null
                  : (next) {
                      final off = [...needsOff];
                      if (next) {
                        off.remove(needKey);
                      } else if (!off.contains(needKey)) {
                        off.add(needKey);
                      }
                      onNeedsOffChanged!(off);
                    },
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.emotionAccent,
            inactiveTrackColor: AppColors.borderOf(
              context,
            ).withValues(alpha: 0.3),
            thumbColor: AppColors.emotionAccent,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ],
    );

    return mainSlider;
  }
}
