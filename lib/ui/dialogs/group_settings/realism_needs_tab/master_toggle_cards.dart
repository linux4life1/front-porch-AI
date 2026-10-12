// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/group_realism_controller.dart';

/// The group's master Realism Engine switch card.
class GroupRealismEngineCard extends StatelessWidget {
  final GroupRealismNeedsController controller;

  const GroupRealismEngineCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final realismEnabled = controller.realismEnabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppColors.porchAmberOf(context),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Realism Engine for this group',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Switch(
                value: realismEnabled,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: controller.updateRealism,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tracks emotions, short/long-term bond, trust, arousal, and fixation per character. Only takes effect when not in Director Mode.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (!realismEnabled)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Sub-features (Needs, etc.) have no effect while the master toggle is off.',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// NSFW Enhancements (arousal / Lust bar + post-climax cooldowns).
/// Mirrors the sidebar Character State gear toggle so it's findable
/// where users expect group-wide switches; applies to every member.
class GroupNsfwEnhancementsCard extends StatelessWidget {
  final GroupRealismNeedsController controller;

  const GroupNsfwEnhancementsCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final nsfwEnabled = controller.nsfwEnhancementsEnabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🔥', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'NSFW Enhancements',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Switch(
                value: nsfwEnabled,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: controller.updateNsfwEnhancements,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tracks arousal (the Lust bar) with post-climax refractory '
            'cooldowns for every character in this group. Only takes '
            'effect while the Realism Engine above is on.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (nsfwEnabled && !controller.realismEnabled)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Turn on the Realism Engine above for this to have any '
                'effect.',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
