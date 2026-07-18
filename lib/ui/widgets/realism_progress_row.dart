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

/// Reusable progress row for Realism Engine values (Bond, Trust, Arousal, etc.).
///
/// Supports both the rich 1:1 sidebar style and a compact variant for dense
/// group member lists. Handles negative values with red accent coloring,
/// normalized progress for -300..300 (or custom maxValue) ranges, and
/// light/dark mode safe AppColors usage.
///
/// This is the single source of truth for the visual treatment so that the
/// expanded speaker card in group chats can be pixel-identical to the 1:1
/// sidebar while compact cards remain scannable.
class RealismProgressRow extends StatelessWidget {
  final String label;
  final int value;
  final int tier;
  final String tierName;
  final Color color;
  final IconData icon;
  final int maxValue;
  final String? tooltip;
  final bool compact;

  /// When non-null, overrides the ±maxValue normalization with an explicit
  /// 0..1 fill (used by the 1:1 sidebar's "progress toward next tier" bars —
  /// relationshipService.*ProgressPercent). Group cards omit it and keep the
  /// absolute ±max fill, pixel-identical to before.
  final double? progress;

  const RealismProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.tier,
    required this.tierName,
    required this.color,
    required this.icon,
    this.maxValue = 300,
    this.tooltip,
    this.compact = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isNegative = value < 0;
    final displayColor = isNegative
        ? AppColors.negativeAccentOf(context)
        : color;
    final absVal = value.abs();
    final target = maxValue;
    final norm = (progress ?? ((value + maxValue) / (maxValue * 2.0))).clamp(
      0.0,
      1.0,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message:
              tooltip ??
              (label.toLowerCase().contains('bond')
                  ? 'Bond: Current relationship strength.'
                  : (label.toLowerCase().contains('trust')
                        ? 'Trust: How much the character believes and relies on you.'
                        : 'Arousal: Physical/sexual tension level.')),
          preferBelow: false,
          child: Row(
            children: [
              Icon(icon, size: compact ? 11 : 13, color: displayColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$label: $tierName',
                  style: TextStyle(
                    fontSize: compact ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    color: displayColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  '$absVal/$target',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: norm,
            minHeight: compact ? 3 : 5,
            backgroundColor: AppColors.borderOf(
              context,
            ).withValues(alpha: 0.35),
            valueColor: AlwaysStoppedAnimation<Color>(displayColor),
          ),
        ),
      ],
    );

    if (compact) {
      return content;
    }

    return Padding(padding: const EdgeInsets.only(bottom: 2), child: content);
  }
}
