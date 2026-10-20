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

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/accent_fit.dart';
import 'package:front_porch_ai/ui/theme/app_palette.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:front_porch_ai/ui/theme/chat_default_colors.dart';
import 'package:front_porch_ai/ui/theme/themes/app_theme_id.dart';
import 'settings_base.dart';

/// The app theme and its customisations: which built-in theme, light/dark/
/// system mode, a custom accent, the UI font and corner roundness.
///
/// [resolvedPalettes] is the one place a theme's colors are worked out; the
/// desktop root and the web settings snapshot both read it.
class AppearanceSettings with SettingsBase {
  AppThemeId _theme = AppThemeId.porch;
  AppThemeMode _mode = AppThemeMode.dark;
  Color? _accent;
  UiFont _font = UiFont.inter;
  UiCorners _corners = UiCorners.standard;
  Brightness _platformBrightness =
      PlatformDispatcher.instance.platformBrightness;

  (AppThemeId, Color?)? _resolvedKey;
  AppThemePalettes _resolved = AppThemePalettes.porch;

  AppThemeId get theme => _theme;
  AppThemeMode get mode => _mode;

  /// The user's accent pick, or null for the theme's own accent.
  Color? get accentOverride => _accent;
  UiFont get font => _font;
  UiCorners get corners => _corners;

  /// The brightness in force now; [AppThemeMode.system] follows the OS.
  bool get isDark => switch (_mode) {
    AppThemeMode.dark => true,
    AppThemeMode.light => false,
    AppThemeMode.system => _platformBrightness == Brightness.dark,
  };
  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  /// High Contrast holds a custom accent to the same AAA bar as its own.
  static double accentMinRatio(AppThemeId theme) =>
      theme == AppThemeId.highContrast ? 7.0 : 4.5;

  /// [theme]'s palettes with the current custom accent fitted in.
  AppThemePalettes palettesFor(AppThemeId theme) {
    final accent = _accent;
    return accent == null
        ? theme.palettes
        : withCustomAccent(
            theme.palettes,
            accent,
            minRatio: accentMinRatio(theme),
          );
  }

  /// The active theme's palettes with the custom accent fitted in.
  AppThemePalettes resolvedPalettes() {
    final key = (_theme, _accent);
    if (_resolvedKey != key) {
      _resolved = palettesFor(_theme);
      _resolvedKey = key;
    }
    return _resolved;
  }

  /// The palette at the current brightness.
  AppPalette get activePalette =>
      isDark ? resolvedPalettes().dark : resolvedPalettes().light;

  /// Chat colors the user has not picked come from here.
  ChatDefaultColors get chatDefaults => activePalette.chat;

  /// Whether the custom accent was nudged for readability on this theme, in
  /// the mode on screen now.
  bool get accentAdjusted {
    final accent = _accent;
    final base = _theme.palettes;
    return accent != null &&
        fitAccent(
          accent,
          isDark ? base.dark : base.light,
          dark: isDark,
          minRatio: accentMinRatio(_theme),
        ).adjusted;
  }

  void load() {
    _theme = AppThemeId.fromKey(prefs?.getString(k('app_theme')));
    final storedMode = prefs?.getString(k('theme_mode'));
    _mode = storedMode != null
        ? AppThemeMode.fromKey(storedMode)
        : (prefs?.getBool(k('dark_mode')) ?? true)
        ? AppThemeMode.dark
        : AppThemeMode.light;
    _accent = parseAccentHex(prefs?.getString(k('accent_override')));
    _font = UiFont.fromKey(prefs?.getString(k('ui_font')));
    _corners = UiCorners.fromKey(prefs?.getString(k('ui_radius')));
  }

  Future<void> setTheme(AppThemeId value) async {
    if (_theme == value) return;
    _theme = value;
    await prefs?.setString(k('app_theme'), value.key);
    notify();
  }

  Future<void> setMode(AppThemeMode value) async {
    if (_mode == value) return;
    _mode = value;
    await prefs?.setString(k('theme_mode'), value.key);
    // Older builds only read dark_mode; keep it in step so a downgrade
    // opens in the brightness the user last saw.
    await prefs?.setBool(k('dark_mode'), isDark);
    notify();
  }

  Future<void> setAccentOverride(Color? value) async {
    final solid = value?.withValues(alpha: 1);
    if (_accent == solid) return;
    _accent = solid;
    await prefs?.setString(
      k('accent_override'),
      solid == null ? '' : accentHex(solid),
    );
    notify();
  }

  Future<void> setFont(UiFont value) async {
    if (_font == value) return;
    _font = value;
    await prefs?.setString(k('ui_font'), value.key);
    notify();
  }

  Future<void> setCorners(UiCorners value) async {
    if (_corners == value) return;
    _corners = value;
    await prefs?.setString(k('ui_radius'), value.key);
    notify();
  }

  /// Clears the accent, font and corner choices; the theme and mode stay.
  Future<void> resetCustomisations() async {
    _accent = null;
    _font = UiFont.inter;
    _corners = UiCorners.standard;
    await prefs?.setString(k('accent_override'), '');
    await prefs?.setString(k('ui_font'), UiFont.inter.key);
    await prefs?.setString(k('ui_radius'), UiCorners.standard.key);
    notify();
  }

  /// Fed by the app root when the OS switches light/dark.
  void setPlatformBrightness(Brightness value) {
    if (_platformBrightness == value) return;
    _platformBrightness = value;
    if (_mode == AppThemeMode.system) notify();
  }
}
