// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Start this group in Director Mode" switch card in the group editor.
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
              'When enabled, entering the group begins in observer/director mode. You steer via the input box while characters respond autonomously. This is only where it starts: the live Director switch for a chat is in its sidebar.',
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
