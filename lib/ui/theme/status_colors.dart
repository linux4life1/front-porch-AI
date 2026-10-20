// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Status hues. They mean the same in every app theme, so only brightness
/// tunes them: dark keeps the Material accents the app always used, light
/// takes a deeper tone that stays readable on paper.
class StatusColors {
  StatusColors._();

  /// Errors, failures and stop buttons.
  static Color dangerOf(BuildContext context) =>
      AppColors.resolve(context, Colors.redAccent, const Color(0xFFB71C1C));

  /// Cautions and troubleshooting hints.
  static Color warningOf(BuildContext context) =>
      AppColors.resolve(context, Colors.orangeAccent, const Color(0xFF9A3412));

  /// Done, accepted, installed.
  static Color successOf(BuildContext context) =>
      AppColors.resolve(context, Colors.greenAccent, const Color(0xFF1B5E20));

  /// A solid success button.
  static Color successFillOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.greenAccent.shade700,
    const Color(0xFF1B5E20),
  );

  /// A solid danger button, such as Disconnect.
  static final Color dangerFill = Colors.redAccent.shade700;

  /// A spelling mistake's wavy underline. Read without a context, so it is
  /// one tone for both modes.
  static final Color misspelling = Colors.redAccent.withValues(alpha: 0.6);

  /// A softer caution: empty lists and missing backups.
  static Color cautionOf(BuildContext context) =>
      AppColors.resolve(context, Colors.orange, const Color(0xFF9A3412));

  /// A download or setup step that is running.
  static Color progressOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF1DE9B6),
    const Color(0xFF00695C),
  );

  /// Neutral, reassuring notes.
  static Color infoOf(BuildContext context) =>
      AppColors.resolve(context, Colors.tealAccent, const Color(0xFF00695C));

  /// Text and icons on a solid status or identity fill.
  static const Color onFill = Colors.white;
  static const Color onFillMuted = Colors.white70;

  /// Solid snackbar fills, the same in both modes: a refused action, a
  /// failed save, an error toast, and a finished job.
  static const Color alertFill = Colors.redAccent;
  static final Color failFill = Colors.red.shade800;
  static const Color errorToast = Color(0xFFB91C1C);
  static const Color doneFill = Colors.green;

  /// A solid caution button and its ink, such as Accept Risk.
  static const Color warningFill = Colors.orangeAccent;
  static const Color onWarningFill = Colors.black87;

  /// The banner behind a warning line, such as the trust-repair notice.
  static Color warningPanelOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF7C2D12),
    const Color(0xFFFEF3C7),
  );

  /// A soft danger tint behind a short label, at [alpha].
  static Color dangerWashOf(BuildContext context, double alpha) =>
      AppColors.resolve(
        context,
        Colors.redAccent.withValues(alpha: alpha),
        Colors.red.withValues(alpha: alpha),
      );

  /// The strip behind an inline error message.
  static Color errorPanelOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.red.withValues(alpha: 0.1),
    Colors.red.withValues(alpha: 0.08),
  );

  /// Notice text on a tinted row: blockers and advisories.
  static Color noticeDangerOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFF2B3A5),
    const Color(0xFFB71C1C),
  );
  static Color noticeWarnOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFE8CF96),
    const Color(0xFF92400E),
  );
}
