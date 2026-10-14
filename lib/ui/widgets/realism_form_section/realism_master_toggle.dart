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

/// Realism Engine master switch card.
class RealismMasterToggle extends StatelessWidget {
  const RealismMasterToggle({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.creatorPalette?.card ?? AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? (context.creatorPalette?.amber ?? AppColors.formMasterAccent)
                    .withValues(alpha: 0.4)
              : context.creatorPalette?.line ?? AppColors.borderOf(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: enabled
                  ? (context.creatorPalette?.amber ??
                            AppColors.formMasterAccent)
                        .withValues(alpha: 0.2)
                  : (context.creatorPalette?.raise ??
                            AppColors.surfaceContainerOf(context))
                        .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.psychology,
              color: enabled
                  ? context.creatorPalette?.amber ?? AppColors.formMasterAccent
                  : context.creatorPalette?.muted ??
                        AppColors.iconSecondary(context),
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
                    color:
                        context.creatorPalette?.ink ??
                        AppColors.textPrimary(context),
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
                        ? context.creatorPalette?.amber ??
                              AppColors.formMasterAccent
                        : context.creatorPalette?.muted ??
                              AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled,
            onChanged: onEnabledChanged,
            activeTrackColor:
                (context.creatorPalette?.amber ?? AppColors.formMasterAccent)
                    .withValues(alpha: 0.5),
            activeThumbColor:
                context.creatorPalette?.amber ?? AppColors.formMasterAccent,
          ),
        ],
      ),
    );
  }
}
