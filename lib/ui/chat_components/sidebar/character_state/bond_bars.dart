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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/tier_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_progress_row.dart';

/// The 1:1 relationship bars — Short-Term Bond, Long-Term Bond, Trust, and
/// (when NSFW enhancements are on) Lust — all rendered through the ONE shared
/// [RealismProgressRow] geometry, ending the era of three divergent
/// hand-drawn bar styles. Lust living here IS the nsfw_section merge: one
/// emotional dashboard, no separate box. The refractory countdown renders as
/// a small line directly under the Lust bar.
///
/// 1:1 bars fill by "progress toward the next tier"
/// (relationshipService.*ProgressPercent) via the row's `progress` override;
/// group member cards use the same widget with the absolute ±max fill.
class BondBars extends StatelessWidget {
  final ChatService chat;

  const BondBars({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final rel = chat.relationshipService;
    final nsfw = chat.nsfwService;
    final arousalTier = nsfw.arousalTier;

    final lustColor = arousalTier >= 6
        ? AppColors.lustDeepOf(context)
        : arousalTier <= -1
        ? AppColors.frostAccentOf(context)
        : AppColors.lustAccentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RealismProgressRow(
          label: 'Short-Term Bond',
          value: rel.affectionScore,
          tier: rel.relationshipTier,
          tierName: rel.shortTermTierName,
          color: TierColors.tierColor(context, rel.relationshipTier),
          icon: rel.relationshipTier < 0 ? Icons.heart_broken : Icons.favorite,
          maxValue: rel.shortTermProgressTarget,
          progress: rel.shortTermProgressPercent,
          tooltip:
              'Short-term Dynamic: The immediate "tension in the room" or how '
              'they feel about you right now. Evolves quickly based on recent '
              'events.',
        ),
        const SizedBox(height: 8),
        RealismProgressRow(
          label: 'Long-Term Bond',
          value: rel.longTermScore,
          tier: rel.longTermTier,
          tierName: rel.longTermTierName,
          color: TierColors.tierColor(context, rel.longTermTier),
          icon: rel.longTermTier < 0
              ? Icons.heart_broken_sharp
              : Icons.monitor_heart,
          maxValue: rel.longTermProgressTarget,
          progress: rel.longTermProgressPercent,
          tooltip:
              'Long-term Relationship: Your deep, overarching history '
              'together. Evolves slowly and sets the foundation for your '
              'interactions.',
        ),
        const SizedBox(height: 8),
        RealismProgressRow(
          label: 'Trust',
          value: rel.trustLevel,
          tier: rel.trustTier,
          tierName: rel.trustTierName,
          color: AppColors.trustAccentOf(context),
          icon: rel.trustLevel < 0 ? Icons.vpn_key_off : Icons.vpn_key,
          maxValue: rel.trustProgressTarget,
          progress: rel.trustProgressPercent,
          tooltip:
              'Trust: Paranoia vs absolute faith. Dictates whether the '
              'character questions your motives or readily believes you.',
        ),
        if (nsfw.nsfwCooldownEnabled) ...[
          const SizedBox(height: 8),
          RealismProgressRow(
            label: 'Lust',
            value: nsfw.arousalLevel.clamp(-100, 100),
            tier: arousalTier,
            tierName: nsfw.arousalTierName,
            color: lustColor,
            icon: arousalTier >= 6
                ? Icons.local_fire_department
                : arousalTier <= -1
                ? Icons.ac_unit
                : Icons.favorite_border,
            maxValue: 100,
            progress: (nsfw.arousalLevel.abs() / 100).clamp(0.0, 1.0),
            tooltip: 'Arousal: Physical/sexual tension level.',
          ),
          if (nsfw.cooldownTurnsRemaining > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.hourglass_bottom,
                  size: 12,
                  color: AppColors.lustAccentOf(context),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Refractory: ${nsfw.cooldownTurnsRemaining} '
                    'turn${nsfw.cooldownTurnsRemaining == 1 ? '' : 's'} remaining',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.lustAccentOf(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
