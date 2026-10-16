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
import 'package:front_porch_ai/ui/theme/creator_palette.dart';

/// The labelled switch row the realism and needs forms share.
Widget buildRealismToggleRow({
  required IconData icon,
  required String label,
  String subtitle = '',
  required bool value,
  required ValueChanged<bool> onChanged,
  required BuildContext context,
}) {
  final onColor =
      context.creatorPalette?.amber ?? AppColors.porchAmberOf(context);
  return Row(
    children: [
      Icon(
        icon,
        color: value
            ? onColor
            : context.creatorPalette?.muted ?? AppColors.iconSecondary(context),
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
                    ? context.creatorPalette?.ink ??
                          AppColors.textPrimary(context)
                    : context.creatorPalette?.prose ??
                          AppColors.textSecondary(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(
                  color:
                      context.creatorPalette?.muted ??
                      AppColors.textTertiary(context),
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

/// Accent-coloured icon + label above a realism form card.
class RealismSectionHeader extends StatelessWidget {
  const RealismSectionHeader(this.icon, this.label, this.color, {super.key});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
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
}

/// Labelled slider with a tier pill, as in the Relationship card.
class RealismSliderRow extends StatelessWidget {
  const RealismSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.tierName,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String tierName;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color:
                    context.creatorPalette?.prose ??
                    AppColors.textSecondary(context),
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
            inactiveTrackColor:
                (context.creatorPalette?.line ?? AppColors.borderOf(context))
                    .withValues(alpha: 0.3),
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
