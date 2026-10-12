// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One selectable turn-order card on the Group Settings General tab.
class GroupTurnStrategyCard extends StatelessWidget {
  final bool isSelected;
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const GroupTurnStrategyCard({
    super.key,
    required this.isSelected,
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final borderColor = isSelected ? amber : AppColors.borderOf(context);
    final bgColor = isSelected
        ? amber.withValues(alpha: 0.12)
        : AppColors.surfaceContainerOf(context);
    final iconColor = isSelected ? amber : AppColors.iconSecondary(context);
    final textColor = isSelected
        ? AppColors.textPrimary(context)
        : AppColors.textSecondary(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
