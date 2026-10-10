// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The "Model Thinking" reasoning toggle shared by all creation modes.
/// Restored from the god file's `_buildReasoningToggle`.
class ReasoningToggle extends StatelessWidget {
  final bool enabled;
  final Color accentColor;
  final ValueChanged<bool> onChanged;

  const ReasoningToggle({
    super.key,
    required this.enabled,
    required this.accentColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: enabled
              ? accentColor.withValues(alpha: 0.08)
              : AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled
                ? accentColor.withValues(alpha: 0.5)
                : AppColors.borderOf(context).withValues(alpha: 0.2),
            width: enabled ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.psychology,
              color: enabled ? accentColor : AppColors.textTertiary(context),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model Thinking',
                    style: TextStyle(
                      color: enabled
                          ? AppColors.textPrimary(context)
                          : AppColors.textSecondary(context),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Let the model reason before generating. Higher quality, but slower',
                    style: TextStyle(
                      color: enabled
                          ? accentColor.withValues(alpha: 0.6)
                          : AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              onChanged: onChanged,
              // Switches are porch amber app-wide; [accentColor] tints the card.
              activeTrackColor: AppColors.porchAmberOf(context),
            ),
          ],
        ),
      ),
    );
  }
}
