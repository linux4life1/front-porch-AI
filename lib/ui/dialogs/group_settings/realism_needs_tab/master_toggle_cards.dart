// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/realism_needs_tab/group_realism_controller.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart'
    show realismAllowedOf;

/// The group chat's Realism Engine card: one switch that turns the whole cast
/// on or off for this chat at once. Each character's own switch for this chat
/// is in the sidebar's Character State; this one is on while any of them is.
/// While Porch Life does not allow Realism it greys out at the chat's own
/// choice, which is kept.
class GroupRealismEngineCard extends StatelessWidget {
  final GroupRealismNeedsController controller;

  const GroupRealismEngineCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final realismEnabled = controller.realismEnabled;
    final allowed = realismAllowedOf(context);
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
                  'Realism Engine for every character in this chat',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Switch(
                value: realismEnabled,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: allowed ? controller.updateRealism : null,
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
          if (!allowed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                "The Realism Engine is off in Porch Life, so no chat runs it. "
                "This chat's own choice is kept.",
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
          if (allowed && !realismEnabled)
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
