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

part of 'realism_form_section.dart';

/// Shared chrome: labels, bond/trust colours, section header, slider row.
extension RealismFormControls on RealismFormSection {
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

  Widget _sectionHeader(IconData icon, String label, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.0,
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
}
