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

/// Purple-themed fixation indicator matching the 1:1 sidebar treatment exactly.
///
/// Compact variant for group member lists (single line + turns remaining).
/// Expanded/rich variant for the focused speaker card (read-only, same as 1:1).
///
/// Fixations are intrusive thoughts controlled exclusively by the Realism Engine
/// (LLM narrative eval + natural 3-turn lifespan decay). They are deliberately
/// not user-clearable in either 1:1 or group mode.
class FixationChip extends StatelessWidget {
  final String topic;
  final int? lifespan;
  final bool compact;

  const FixationChip({
    super.key,
    required this.topic,
    this.lifespan,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final lifespanText = (lifespan != null && lifespan! > 0)
        ? ' · ${lifespan}t'
        : '';

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.resolve(
            context,
            AppColors.fixationAccent.withValues(alpha: 0.12),
            AppColors.fixationAccentLight.withValues(alpha: 0.6),
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.resolve(
              context,
              AppColors.fixationAccent.withValues(alpha: 0.35),
              AppColors.fixationAccentLight.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology,
              size: 11,
              color: AppColors.resolve(
                context,
                AppColors.fixationAccent,
                AppColors.fixationAccentLight,
              ),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                'Fixated: $topic$lifespanText',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.resolve(
                    context,
                    AppColors.fixationAccent,
                    AppColors.fixationAccentLight,
                  ),
                  fontStyle: FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Rich / expanded variant — matches the 1:1 fixation card treatment
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.resolve(
          context,
          AppColors.fixationAccent.withValues(alpha: 0.12),
          AppColors.fixationAccentLight.withValues(alpha: 0.6),
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.resolve(
            context,
            AppColors.fixationAccent.withValues(alpha: 0.4),
            AppColors.fixationAccentLight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.psychology,
            size: 16,
            color: AppColors.fixationAccentOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CURRENT FIXATION',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.fixationAccentOf(context),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  topic + (lifespanText.isNotEmpty ? lifespanText : ''),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
