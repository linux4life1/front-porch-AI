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

import 'app_colors.dart';

/// The Porch Stories palette, transcribed from the approved story mockups.
///
/// Source of truth: docs/design/porch-stories-ui-spec.md. The web twin is
/// `web_ui/src/styles/studio.css` (`--studio-*`); the three must agree
/// value for value. Story screens use ONLY these surfaces and accents — never
/// `AppColors.cardOf` / `surfaceOf` / `frostAccentOf` and the like — so the
/// desktop app and the web UI look the same.
class StudioColors {
  StudioColors._();

  /// Page background.
  static const Color bg = Color(0xFF1B1611);
  static const Color bgLight = Color(0xFFF8F4ED);
  static Color bgOf(BuildContext context) =>
      AppColors.resolve(context, bg, bgLight);

  /// Sidebar and header surface.
  static const Color side = Color(0xFF1F1913);
  static const Color sideLight = Color(0xFFF0EBE3);
  static Color sideOf(BuildContext context) =>
      AppColors.resolve(context, side, sideLight);

  /// Card fill.
  static const Color card = Color(0xFF251E17);
  static const Color cardLight = Color(0xFFFFFDF9);
  static Color cardOf(BuildContext context) =>
      AppColors.resolve(context, card, cardLight);

  /// Raised fill: selected nav item, secondary buttons, insets.
  static const Color raise = Color(0xFF30271E);
  static const Color raiseLight = Color(0xFFE9E2D8);
  static Color raiseOf(BuildContext context) =>
      AppColors.resolve(context, raise, raiseLight);

  /// Hairline borders and dividers.
  static const Color line = Color(0xFF3E3328);
  static const Color lineLight = Color(0xFFD4CFC6);
  static Color lineOf(BuildContext context) =>
      AppColors.resolve(context, line, lineLight);

  /// Text.
  static const Color ink = Color(0xFFEFE6DA);
  static const Color inkLight = Color(0xFF2A231C);
  static Color inkOf(BuildContext context) =>
      AppColors.resolve(context, ink, inkLight);

  /// Muted text.
  static const Color muted = Color(0xFFA89A89);
  static const Color mutedLight = Color(0xFF6E6357);
  static Color mutedOf(BuildContext context) =>
      AppColors.resolve(context, muted, mutedLight);

  /// Faint text: placeholders, counts.
  static const Color faint = Color(0xFF7A6E62);
  static const Color faintLight = Color(0xFF9A8E82);
  static Color faintOf(BuildContext context) =>
      AppColors.resolve(context, faint, faintLight);

  /// Prose: serif body text in the writer and reader.
  static const Color prose = Color(0xFFE8DDCF);
  static const Color proseLight = Color(0xFF2A231C);
  static Color proseOf(BuildContext context) =>
      AppColors.resolve(context, prose, proseLight);

  /// Amber: primary action and selection.
  static const Color amber = Color(0xFFF4A259);
  static const Color amberLight = Color(0xFFB45309);
  static Color amberOf(BuildContext context) =>
      AppColors.resolve(context, amber, amberLight);

  /// Honey: sequence headings, planning chips, "new" badges.
  static const Color honey = Color(0xFFE9C46A);
  static const Color honeyLight = Color(0xFF8F6400);
  static Color honeyOf(BuildContext context) =>
      AppColors.resolve(context, honey, honeyLight);

  /// Terracotta: tension bars, prose chips.
  static const Color terra = Color(0xFFE29578);
  static const Color terraLight = Color(0xFF9C4B2F);
  static Color terraOf(BuildContext context) =>
      AppColors.resolve(context, terra, terraLight);

  /// Teal: written, pass, good.
  static const Color teal = Color(0xFF4DB6AC);
  static const Color tealLight = Color(0xFF00695C);
  static Color tealOf(BuildContext context) =>
      AppColors.resolve(context, teal, tealLight);

  /// Bad: fail, banned, destructive.
  static const Color bad = Color(0xFFE57373);
  static const Color badLight = Color(0xFFB3261E);
  static Color badOf(BuildContext context) =>
      AppColors.resolve(context, bad, badLight);

  /// Text on an amber fill.
  static const Color amberInk = Color(0xFF2A1A08);
  static const Color amberInkLight = Color(0xFFFFFDF9);
  static Color amberInkOf(BuildContext context) =>
      AppColors.resolve(context, amberInk, amberInkLight);

  /// Shelf cover gradient (sketch H).
  static const Color coverStart = Color(0xFF4A3421);
  static const Color coverEnd = Color(0xFF251E17);

  /// Portrait placeholder gradient (top-left → bottom-right).
  static const Color portraitStart = Color(0xFF6A4A2A);
  static const Color portraitEnd = Color(0xFF30271E);

  /// Continuity diff: removed text.
  static const Color diffDelBg = Color(0xFF3A1E1C);
  static const Color diffDelFg = Color(0xFFF0B3AE);

  /// Continuity diff: inserted text.
  static const Color diffInsBg = Color(0xFF16302D);
  static const Color diffInsFg = Color(0xFFA6E3DB);
}
