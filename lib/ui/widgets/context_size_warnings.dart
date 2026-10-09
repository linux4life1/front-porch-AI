// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Under a control that sets chat's context: a plain warning when it is set
/// below [kKoboldContextFloor], and one when the longest reply allowed
/// ([maxOutput]) would take up the whole context. Nothing when both are fine.
/// The number stays the user's; this only says what it means.
class ContextSizeWarnings extends StatelessWidget {
  const ContextSizeWarnings({
    super.key,
    required this.contextSize,
    this.maxOutput,
  });

  /// Null while the box holds no number.
  final int? contextSize;
  final int? maxOutput;

  @override
  Widget build(BuildContext context) {
    final c = contextSize;
    final low = c != null && c > 0 && c < kKoboldContextFloor;
    final fills = c == null || maxOutput == null
        ? null
        : koboldReplyFillsContextWarning(context: c, maxOutput: maxOutput!);
    if (!low && fills == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (low)
            _line(
              context,
              const ValueKey('context-floor-warning'),
              kKoboldContextFloorWords,
            ),
          if (fills != null)
            _line(context, const ValueKey('context-reply-warning'), fills),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, Key key, String text) {
    final honey = AppColors.porchHoneyOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: honey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: honey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
