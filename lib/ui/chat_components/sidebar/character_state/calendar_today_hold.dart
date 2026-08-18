// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live hold on the Story Calendar. Not a leftover under TimeStrip.
// One sentence they wrote, or nothing. User only deletes.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Today's sentence on the calendar Joe already opens from the date.
class CalendarTodayHold extends StatelessWidget {
  final String? text;
  final bool enabled;
  final VoidCallback? onAbandon;

  const CalendarTodayHold({
    super.key,
    this.text,
    this.enabled = true,
    this.onAbandon,
  });

  @override
  Widget build(BuildContext context) {
    final line = text?.trim() ?? '';
    if (!enabled || line.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TODAY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              if (onAbandon != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: AppColors.textTertiary(context),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: "Clear today's plan",
                  onPressed: onAbandon,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
