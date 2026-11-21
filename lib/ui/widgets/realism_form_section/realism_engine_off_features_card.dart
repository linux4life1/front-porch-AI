// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';

import 'member_starts_away_row.dart';
import 'realism_optional_features_card.dart';

/// The Optional Features card with the Realism Engine off. The engine's own
/// rows are hidden; what remains is what runs without it — a group member's
/// Starts away (a door fact, not an engine feature — R6) and Chaos Mode,
/// greyed when [chaosLockedTooltip] says it is not this editor's to set.
class RealismEngineOffFeaturesCard extends StatelessWidget {
  const RealismEngineOffFeaturesCard({
    super.key,
    required this.chaosModeEnabled,
    required this.onChaosModeChanged,
    required this.showChaosToggle,
    this.chaosLockedTooltip,
    this.startsAwayEnabled = false,
    this.onStartsAwayChanged,
    this.startsAwayMemberName,
  });

  final bool chaosModeEnabled;
  final ValueChanged<bool> onChaosModeChanged;

  /// A creator surface may hide the engine's Chaos row even here.
  final bool showChaosToggle;
  final String? chaosLockedTooltip;

  final bool startsAwayEnabled;
  final ValueChanged<bool>? onStartsAwayChanged;

  /// The member's name as the editor has it now, for the row's hint.
  final String? startsAwayMemberName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.creatorPalette?.card ?? AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.creatorPalette?.line ?? AppColors.borderOf(context),
        ),
      ),
      child: Column(
        children: [
          if (onStartsAwayChanged != null) ...[
            memberStartsAwayRow(
              context,
              startsAwayEnabled,
              onStartsAwayChanged!,
              memberName: startsAwayMemberName,
            ),
            if (showChaosToggle) const SizedBox(height: 12),
          ],
          if (showChaosToggle)
            realismChaosRow(
              context,
              value: chaosModeEnabled,
              onChanged: onChaosModeChanged,
              lockedTooltip: chaosLockedTooltip,
            ),
        ],
      ),
    );
  }
}
