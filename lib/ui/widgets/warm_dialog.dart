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

import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';

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
///
/// Opened inside the AI Character Creator (its theme carries a
/// [CreatorPalette]), the dialog and its text and buttons take the creator
/// spec's Dialog shape instead (docs/design/creator-ui-spec.md): card fill,
/// a `line` hairline, radius 20, padding 24, 520 wide, 44px buttons.
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
  return showWarmDialogOf<T>(
    context,
    barrierDismissible: barrierDismissible,
    builder: (_) => WarmDialog(
      title: title,
      content: content,
      actions: actions,
      icon: icon,
      accent: accent,
      destructive: destructive,
      width: width,
    ),
  );
}

/// Opens a dialog that owns its own state: [builder] returns a widget (usually
/// a StatefulWidget) whose `build` returns a [WarmDialog], so the body and the
/// buttons can share that state (a Save that disables while saving, a message
/// a button sets). For a dialog with fixed content and buttons, [showWarmDialog]
/// is shorter.
Future<T?> showWarmDialogOf<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// The warm-porch dialog scaffold itself. [showWarmDialog] builds one; a
/// dialog with its own state returns one from `build` (see [showWarmDialogOf]).
class WarmDialog extends StatelessWidget {
  const WarmDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.icon,
    this.accent,
    this.destructive = false,
    this.width = 320,
  });
  final String title;
  final Widget content;
  final List<Widget>? actions;
  final IconData? icon;
  final Color? accent;
  final bool destructive;
  final double width;

  /// The creator spec's Dialog: 520 wide, so the body is 472 inside the 24
  /// padding.
  static const _creatorBodyWidth = 472.0;

  @override
  Widget build(BuildContext ctx) {
    final studio = ctx.creatorPalette;
    if (studio != null) return _creator(ctx, studio);
    final tint = destructive ? AppColors.negativeAccentOf(ctx) : accent;
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(ctx),
      // One radius (matches the sidebar's warm-porch cards) and one border
      // convention: an accent-tinted hairline, or the neutral border.
      shape: RoundedRectangleBorder(
        borderRadius: AppCorners.of(ctx).circular(12),
        side: BorderSide(
          color:
              tint?.withValues(alpha: 0.5) ??
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
  }

  /// The creator's Dialog: title 20 / 700 beside a 22px amber icon (`bad`
  /// when destructive), 16 between the blocks, 10 between the buttons.
  /// The sketch's text has no tracking and the browser's line height, where
  /// the app's text theme adds both.
  Widget _creator(BuildContext ctx, CreatorPalette studio) {
    final tint = destructive ? studio.bad : (accent ?? studio.amber);
    return AlertDialog(
      backgroundColor: studio.card,
      surfaceTintColor: studio.card,
      shape: RoundedRectangleBorder(
        borderRadius: AppCorners.of(ctx).circular(20),
        side: BorderSide(color: studio.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      buttonPadding: const EdgeInsets.symmetric(horizontal: 10),
      title: Row(
        spacing: 10,
        children: [
          if (icon != null) Icon(icon, color: tint, size: 22),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                height: 1.2,
                color: destructive ? studio.bad : studio.ink,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: _creatorBodyWidth,
        child: DefaultTextStyle.merge(
          style: const TextStyle(letterSpacing: 0),
          child: content,
        ),
      ),
      actions: actions,
    );
  }
}

/// A dialog body paragraph in the warm-porch secondary text color (theme-aware).
/// Replaces the ubiquitous `Colors.white70` bodies that were invisible in light
/// mode. Inside the creator: 14 / 1.5 `prose`.
class WarmDialogText extends StatelessWidget {
  const WarmDialogText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final studio = context.creatorPalette;
    return Text(
      text,
      style: studio == null
          ? TextStyle(color: AppColors.textSecondary(context), height: 1.5)
          : TextStyle(
              color: studio.prose,
              fontSize: 14,
              height: 1.5,
              letterSpacing: 0,
            ),
    );
  }
}

/// The standard cancel/dismiss text button for a warm dialog. Pops with [value]
/// (null by default). Inside the creator: a 44px `prose` text button.
Widget warmDialogCancel(
  BuildContext context, {
  String label = 'Cancel',
  Object? value,
}) {
  final studio = context.creatorPalette;
  if (studio != null) {
    return SizedBox(
      height: 44,
      child: TextButton(
        onPressed: () => Navigator.of(context).pop(value),
        style: TextButton.styleFrom(
          foregroundColor: studio.prose,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: AppCorners.of(context).circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
  return TextButton(
    onPressed: () => Navigator.of(context).pop(value),
    child: Text(
      label,
      style: TextStyle(color: AppColors.textSecondary(context)),
    ),
  );
}

/// The primary (or destructive) confirm action for a warm dialog. A null
/// [onPressed] draws it disabled. Inside the creator: amber (`bad` when
/// destructive), 44px, radius 12, 14 / 700 in amber ink.
Widget warmDialogConfirm(
  BuildContext context, {
  required String label,
  required VoidCallback? onPressed,
  bool destructive = false,
  Color? accent,
  Key? key,
}) {
  final studio = context.creatorPalette;
  if (studio != null) {
    final fill = destructive ? studio.bad : (accent ?? studio.amber);
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        key: key,
        style: ElevatedButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: studio.amberInk,
          disabledBackgroundColor: fill.withValues(alpha: 0.4),
          disabledForegroundColor: studio.amberInk.withValues(alpha: 0.7),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: AppCorners.of(context).circular(12),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
  final bg = destructive
      ? AppColors.negativeAccentOf(context)
      : (accent ?? AppColors.porchAmberOf(context));
  // Dark ink on a bright fill (dark mode's amber), white on a deep one.
  final onBright = ThemeData.estimateBrightnessForColor(bg) == Brightness.light;
  return ElevatedButton(
    key: key,
    style: ElevatedButton.styleFrom(
      backgroundColor: bg,
      // The theme accent carries its own fitted ink; a brightness guess can
      // pick white on a pale custom accent.
      foregroundColor:
          bg == AppColors.porchAmberOf(context) ||
              bg == AppColors.formAccentOf(context)
          ? AppColors.onAccentOf(context)
          : !onBright
          ? StatusColors.onFill
          // theme-keep: a danger or caller fill keeps Porch's dark ink.
          : AppColors.onChaosAccent,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
