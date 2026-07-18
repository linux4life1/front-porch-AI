// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The one warm-porch dialog scaffold. Every app dialog should route through
/// [showWarmDialog] instead of hand-rolling an [AlertDialog] with hardcoded
/// colors — that hand-rolling is what left the app with a dozen mismatched,
/// dark-only dialogs (bespoke `Color(0xFF2D1111)` red-tint, `Color(0xFF1E293B)`
/// blue-tint, `Colors.white70` bodies that ignored light mode, and five
/// different corner radii).
///
/// This uses the [AppColors] `*Of(context)` helpers throughout, so dialogs are
/// theme-aware (correct in light mode) for the first time, with one radius and
/// one border convention. An [accent] tints the title icon + hairline border;
/// [destructive] swaps it to the negative/red accent for delete confirms.
Future<T?> showWarmDialog<T>(
  BuildContext context, {
  required String title,
  required Widget content,
  List<Widget>? actions,
  IconData? icon,
  Color? accent,
  bool destructive = false,
  double width = 320,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      final tint =
          destructive ? AppColors.negativeAccentOf(ctx) : accent;
      return AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        // One radius (matches the sidebar's warm-porch cards) and one border
        // convention: an accent-tinted hairline, or the neutral border.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: tint?.withValues(alpha: 0.5) ??
                AppColors.borderOf(ctx).withValues(alpha: 0.6),
          ),
        ),
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: tint ?? AppColors.iconSecondary(ctx), size: 22),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: destructive
                      ? AppColors.negativeAccentOf(ctx)
                      : AppColors.textPrimary(ctx),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(width: width, child: content),
        actions: actions,
      );
    },
  );
}

/// A dialog body paragraph in the warm-porch secondary text color (theme-aware).
/// Replaces the ubiquitous `Colors.white70` bodies that were invisible in light
/// mode.
class WarmDialogText extends StatelessWidget {
  const WarmDialogText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: AppColors.textSecondary(context), height: 1.5),
  );
}

/// The standard cancel/dismiss text button for a warm dialog. Pops with [value]
/// (null by default).
Widget warmDialogCancel(
  BuildContext context, {
  String label = 'Cancel',
  Object? value,
}) {
  return TextButton(
    onPressed: () => Navigator.of(context).pop(value),
    child: Text(
      label,
      style: TextStyle(color: AppColors.textSecondary(context)),
    ),
  );
}

/// The primary (or destructive) confirm action for a warm dialog.
Widget warmDialogConfirm(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool destructive = false,
  Color? accent,
}) {
  final bg = destructive
      ? AppColors.negativeAccentOf(context)
      : (accent ?? AppColors.porchAmberOf(context));
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: AppColors.resolve(context, Colors.white, Colors.white),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
