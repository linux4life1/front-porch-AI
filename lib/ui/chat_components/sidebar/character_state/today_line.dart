// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One sentence under the time strip. Omitted when the feature is off or
// the sentence is blank — no row, not an empty-state. Never a list,
// checkbox, weekday, or temperament switch.
// Gap lives here so mounting under TimeStrip adds zero height when empty.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The only on-screen plan. [text] is the session sentence. Null/blank or
/// [enabled] false = no widget.
class TodayLine extends StatelessWidget {
  final String? text;
  final bool enabled;
  final VoidCallback? onDelete;

  const TodayLine({
    super.key,
    this.text,
    this.enabled = true,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final line = text?.trim() ?? '';
    if (!enabled || line.isEmpty) return const SizedBox.shrink();
    final textWidget = Text(
      line,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontStyle: FontStyle.italic,
        color: AppColors.textSecondary(context),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: onDelete == null
          ? textWidget
          : Row(
              children: [
                Expanded(child: textWidget),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  color: AppColors.textTertiary(context),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  tooltip: "Clear today's plan",
                  onPressed: onDelete,
                ),
              ],
            ),
    );
  }
}
