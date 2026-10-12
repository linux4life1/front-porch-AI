// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Start this group in Director Mode" switch card on the General tab.
class GroupDirectorModeDefaultCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GroupDirectorModeDefaultCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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
                Icons.visibility,
                size: 18,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Start this group in Director Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              Switch(
                value: value,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: onChanged,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              'When enabled, entering the group begins in observer/director mode. You steer via the input box while characters respond autonomously. The live toggle is also available in the group sidebar.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer note on how the General tab's values are stored.
class GroupGeneralStorageNote extends StatelessWidget {
  const GroupGeneralStorageNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: AppColors.iconSecondary(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'These settings are stored with the group definition. Saving here updates the live session immediately. The values are persisted to the database automatically on membership changes (add/remove character) and on session checkpoints.',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary(context),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
