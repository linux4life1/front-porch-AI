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

import 'app_corners.dart';
import 'app_palette.dart';
import 'appearance_options.dart';

/// Builds the app-wide [ThemeData] for one app theme at one brightness, with
/// the user's UI font and corner choice.
///
/// Results are cached: [ColorScheme.fromSeed] is not free, and the root
/// rebuilds on every [StorageService] notify. [AppThemePalettes] has value
/// equality, so a palette rebuilt at runtime (a custom accent) reuses its
/// entry instead of adding one per rebuild.
class AppTheme {
  AppTheme._();

  static final Map<(AppThemePalettes, Brightness, UiFont, UiCorners), ThemeData>
  _cache = {};

  static ThemeData build({
    AppThemePalettes palettes = AppThemePalettes.porch,
    required Brightness brightness,
    UiFont font = UiFont.inter,
    UiCorners corners = UiCorners.standard,
  }) => _cache.putIfAbsent((
    palettes,
    brightness,
    font,
    corners,
  ), () => _build(palettes, brightness, font, corners));

  /// What `Theme.of` returns above [MaterialApp]: the fallback theme
  /// localized for English-like scripts.
  static final TextTheme _baseTextTheme = () {
    final fallback = ThemeData.fallback();
    return ThemeData.localize(
      fallback,
      fallback.typography.geometryThemeFor(ScriptCategory.englishLike),
    ).textTheme;
  }();

  static ThemeData _build(
    AppThemePalettes palettes,
    Brightness brightness,
    UiFont font,
    UiCorners corners,
  ) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? palettes.dark : palettes.light;
    final shapes = _CornerShapes.of(corners);
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
            onPrimary: palette.onAccent,
            surface: palette.surface,
          ),
      scaffoldBackgroundColor: palette.background,
      cardColor: palette.card,
      textTheme: _baseTextTheme.apply(
        fontFamily: font.fontFamily,
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      cardTheme: shapes?.card,
      dialogTheme: shapes?.dialog,
      chipTheme: shapes?.chip,
      popupMenuTheme: shapes?.menu,
      filledButtonTheme: shapes?.filled,
      elevatedButtonTheme: shapes?.elevated,
      outlinedButtonTheme: shapes?.outlined,
      textButtonTheme: shapes?.text,
      extensions: [palettes, AppCorners(corners)],
      useMaterial3: true,
    );
  }
}

/// Material component shapes for a non-default corner choice. Default keeps
/// every Material shape as it was, so Porch at Default paints unchanged.
class _CornerShapes {
  _CornerShapes(UiCorners c)
    : card = CardThemeData(shape: _rounded(12 * c.scale)),
      dialog = DialogThemeData(shape: _rounded(28 * c.scale)),
      chip = ChipThemeData(shape: _rounded(8 * c.scale)),
      menu = PopupMenuThemeData(shape: _rounded(4 * c.scale)),
      filled = FilledButtonThemeData(style: _button(c)),
      elevated = ElevatedButtonThemeData(style: _button(c)),
      outlined = OutlinedButtonThemeData(style: _button(c)),
      text = TextButtonThemeData(style: _button(c));

  static _CornerShapes? of(UiCorners c) =>
      c == UiCorners.standard ? null : _CornerShapes(c);

  final CardThemeData card;
  final DialogThemeData dialog;
  final ChipThemeData chip;
  final PopupMenuThemeData menu;
  final FilledButtonThemeData filled;
  final ElevatedButtonThemeData elevated;
  final OutlinedButtonThemeData outlined;
  final TextButtonThemeData text;

  static RoundedRectangleBorder _rounded(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  // Material 3 buttons are stadiums; Sharp squares them off, Round keeps
  // the stadium.
  static ButtonStyle _button(UiCorners c) => ButtonStyle(
    shape: WidgetStatePropertyAll(
      c == UiCorners.sharp ? _rounded(4) : const StadiumBorder(),
    ),
  );
}
