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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_palette.dart';

/// WCAG 2 contrast ratio of [fg] drawn over [bg]; a translucent [fg] is
/// composited onto [bg] first.
double contrastRatio(Color fg, Color bg) {
  final solid = Color.alphaBlend(fg, bg.withValues(alpha: 1));
  final a = solid.computeLuminance();
  final b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// The readable ink for text on a solid [fill]: white or near-black,
/// whichever contrasts more.
Color inkOn(Color fill) =>
    contrastRatio(Colors.white, fill) >= contrastRatio(_darkInk, fill)
    ? Colors.white
    : _darkInk;

const _darkInk = Color(0xFF141414);

/// A custom accent fitted to one palette.
@immutable
class FittedAccent {
  const FittedAccent(this.accent, this.onAccent, {required this.adjusted});

  final Color accent;
  final Color onAccent;

  /// Whether [accent] differs from the pick because the pick was too faint
  /// on this palette's panels.
  final bool adjusted;
}

/// Fits a user-picked accent to a palette: the pick's lightness is nudged
/// toward white (dark palettes) or black (light palettes) until it reads at
/// [minRatio] on every panel the accent is drawn on, and its ink reads at
/// 4.5:1 on it (a mid-tone fill has no ink that does).
FittedAccent fitAccent(
  Color pick,
  AppPalette palette, {
  required bool dark,
  double minRatio = 4.5,
}) {
  final grounds = [
    palette.background,
    palette.surface,
    palette.card,
    palette.studioCard,
  ];
  final toward = dark ? Colors.white : Colors.black;
  final solid = pick.withValues(alpha: 1);
  var color = solid;
  for (var step = 1; step <= 40 && !_reads(color, grounds, minRatio); step++) {
    color = Color.lerp(solid, toward, step * 0.025)!;
  }
  return FittedAccent(color, inkOn(color), adjusted: color != solid);
}

bool _reads(Color c, List<Color> grounds, double minRatio) =>
    grounds.every((g) => contrastRatio(c, g) >= minRatio) &&
    contrastRatio(inkOn(c), c) >= 4.5;

/// [base] with every accent role replaced by [pick], fitted per brightness.
AppThemePalettes withCustomAccent(
  AppThemePalettes base,
  Color pick, {
  double minRatio = 4.5,
}) => AppThemePalettes(
  dark: _withAccent(
    base.dark,
    fitAccent(pick, base.dark, dark: true, minRatio: minRatio),
  ),
  light: _withAccent(
    base.light,
    fitAccent(pick, base.light, dark: false, minRatio: minRatio),
  ),
);

/// Whether [pick] needs nudging on either brightness of [base].
bool customAccentAdjusted(
  AppThemePalettes base,
  Color pick, {
  double minRatio = 4.5,
}) =>
    fitAccent(pick, base.dark, dark: true, minRatio: minRatio).adjusted ||
    fitAccent(pick, base.light, dark: false, minRatio: minRatio).adjusted;

AppPalette _withAccent(AppPalette p, FittedAccent a) => AppPalette(
  background: p.background,
  surface: p.surface,
  card: p.card,
  surfaceContainer: p.surfaceContainer,
  sunken: p.sunken,
  deepWell: p.deepWell,
  insetPanel: p.insetPanel,
  border: p.border,
  navigationSelection: p.navigationSelection,
  textPrimary: p.textPrimary,
  textSecondary: p.textSecondary,
  textTertiary: p.textTertiary,
  ink: p.ink,
  muted: p.muted,
  faint: p.faint,
  amber: a.accent,
  honey: p.honey,
  terracotta: p.terracotta,
  sage: p.sage,
  formAccent: a.accent,
  onAccent: a.onAccent,
  studioCard: p.studioCard,
  studioRaise: p.studioRaise,
  studioLineStrong: p.studioLineStrong,
  studioProse: p.studioProse,
  studioNarration: p.studioNarration,
  studioAmberInk: a.onAccent,
  studioTeal: p.studioTeal,
  studioBad: p.studioBad,
  chat: p.chat,
  page: p.page,
);

/// `#RRGGBB` for a stored or sent accent.
String accentHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Parses `#RRGGBB` (or `RRGGBB`); anything else is no accent.
Color? parseAccentHex(String? hex) {
  final digits = hex?.replaceFirst('#', '');
  if (digits == null || digits.length != 6) return null;
  final value = int.tryParse(digits, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
