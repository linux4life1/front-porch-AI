// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Auto-advance switch card on the Group Settings General tab.
class GroupAutoAdvanceCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const GroupAutoAdvanceCard({
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
                Icons.play_circle_outline,
                size: 18,
                color: AppColors.iconSecondary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Auto-advance',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
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
              'After a character finishes responding, automatically prompt the next speaker. Works with both turn orders and Director Mode.',
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
