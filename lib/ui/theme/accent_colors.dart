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

/// Decorative hues that mark a feature on a page, not a status: Director
/// and Always Active amber, Realism teal, the Chaos ink, the world lorebook's
/// emerald and the Stoop's done mark. Dark mode keeps the bright tone; light
/// mode deepens it so it reads on paper.
class AccentColors {
  AccentColors._();

  /// Director Mode, Always Active lore and import actions.
  static Color amberOf(BuildContext context) =>
      AppColors.resolve(context, Colors.amberAccent, const Color(0xFF92400E));

  /// The soft amber panel behind a Director hint, in both modes.
  static final Color amberWash = Colors.amber.withValues(alpha: 0.08);

  /// The Realism Engine's on state.
  static Color tealOf(BuildContext context) =>
      AppColors.resolve(context, Colors.tealAccent, const Color(0xFF00695C));

  /// Chaos Mode text.
  static Color chaosInkOf(BuildContext context) => AppColors.resolve(
    context,
    AppColors.chaosAccent,
    const Color(0xFF92400E),
  );

  /// A world's lorebook, and its solid Add button.
  static Color emeraldOf(BuildContext context) =>
      AppColors.resolve(context, emeraldFill, const Color(0xFF047857));
  static const Color emeraldFill = Color(0xFF10B981);

  /// A Stoop card field that is filled in.
  static Color mintOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF3ECF8E),
    const Color(0xFF047857),
  );
}
