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

  /// Neutral, reassuring notes.
  static Color infoOf(BuildContext context) =>
      AppColors.resolve(context, Colors.tealAccent, const Color(0xFF00695C));

  /// Text and icons on a solid status or identity fill.
  static const Color onFill = Colors.white;
}
