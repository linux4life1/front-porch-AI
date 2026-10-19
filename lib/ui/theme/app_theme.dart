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
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_palette.dart';

/// Builds the app-wide [ThemeData] for one app theme at one brightness.
///
/// Results are cached: [ColorScheme.fromSeed] and the Inter text theme are
/// not free, and the root rebuilds on every [StorageService] notify. The
/// cache only ever holds a handful of entries (themes × 2 brightnesses).
class AppTheme {
  AppTheme._();

  static final Map<(AppThemePalettes, Brightness), ThemeData> _cache = {};

  static ThemeData build({
    AppThemePalettes palettes = AppThemePalettes.porch,
    required Brightness brightness,
  }) => _cache.putIfAbsent((
    palettes,
    brightness,
  ), () => _build(palettes, brightness));

  /// What `Theme.of` returns above [MaterialApp]: the fallback theme
  /// localized for English-like scripts.
  static final TextTheme _baseTextTheme = () {
    final fallback = ThemeData.fallback();
    return ThemeData.localize(
      fallback,
      fallback.typography.geometryThemeFor(ScriptCategory.englishLike),
    ).textTheme;
  }();

  static ThemeData _build(AppThemePalettes palettes, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? palettes.dark : palettes.light;
    return ThemeData(
      brightness: brightness,
      // Seed Material 3 from the theme's accent so every default control
      // (switches, sliders, buttons, progress bars, the cursor, tab
      // indicators) matches the chrome; surfaces are pinned to the palette
      // grounds so only the accent roles change.
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: palettes.dark.amber,
            brightness: brightness,
          ).copyWith(
            primary: palette.amber,
            onPrimary: isDark ? AppColors.onChaosAccent : Colors.white,
            surface: palette.surface,
          ),
      scaffoldBackgroundColor: palette.background,
      cardColor: palette.card,
      textTheme: GoogleFonts.interTextTheme(_baseTextTheme).apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      extensions: [palettes],
      useMaterial3: true,
    );
  }
}
