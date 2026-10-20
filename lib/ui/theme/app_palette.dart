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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'book_page_colors.dart';
import 'chat_default_colors.dart';
import 'studio_colors.dart';

const Color _porchAmberReadable = Color(0xFFA84B06);

/// The chrome colors of one app theme at one brightness.
///
/// These are the roles an app theme may retint: grounds, text, the porch
/// accent family, and the Porch Stories surfaces. Status and identity colors
/// (bond, lust, chaos, errors, the Stoop badges) are not here; they stay
/// brightness-only in [AppColors]. Read the active one with [AppPalette.of].
@immutable
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.card,
    required this.surfaceContainer,
    required this.sunken,
    required this.deepWell,
    required this.insetPanel,
    required this.border,
    required this.navigationSelection,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.amber,
    required this.honey,
    required this.terracotta,
    required this.sage,
    required this.formAccent,
    required this.onAccent,
    required this.studioCard,
    required this.studioRaise,
    required this.studioLineStrong,
    required this.studioProse,
    required this.studioNarration,
    required this.studioAmberInk,
    required this.studioTeal,
    required this.studioBad,
    this.chat = ChatDefaultColors.porchDark,
    this.page = BookPageColors.cream,
  });

  /// Scaffold and page background.
  final Color background;

  /// Dialogs, panels, sidebars.
  final Color surface;

  /// Cards, dropdowns, elevated surfaces.
  final Color card;

  /// Inputs, dropdown fields, dialog wells.
  final Color surfaceContainer;

  /// Inset settings wells.
  final Color sunken;

  /// The deepest read-only text wells.
  final Color deepWell;

  /// KoboldCpp preset and model-card insets.
  final Color insetPanel;

  /// Subtle card and panel borders.
  final Color border;

  /// The selected navigation item's fill.
  final Color navigationSelection;

  /// Material text ramp: primary, secondary, tertiary (icons share it).
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Warm text ramp used by the presets, the model card and Porch Stories.
  final Color ink;
  final Color muted;
  final Color faint;

  /// The porch accent family: primary accent, Story Tools, Character State,
  /// Journal & Memory.
  final Color amber;
  final Color honey;
  final Color terracotta;
  final Color sage;

  /// Accent for forms, dialogs, Image Studio and the gallery: icons, badges,
  /// borders and primary buttons.
  final Color formAccent;

  /// Text and icons drawn on a solid accent fill.
  final Color onAccent;

  /// Porch Stories surfaces that have no app-wide twin.
  final Color studioCard;
  final Color studioRaise;
  final Color studioLineStrong;
  final Color studioProse;
  final Color studioNarration;
  final Color studioAmberInk;
  final Color studioTeal;
  final Color studioBad;

  /// Default chat colors where the user has not picked their own.
  final ChatDefaultColors chat;

  /// The story reader's printed page.
  final BookPageColors page;

  /// Porch, dark: the values every screen used before themes existed.
  static const AppPalette porchDark = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    card: AppColors.card,
    surfaceContainer: AppColors.surfaceContainer,
    sunken: AppColors.sunkenSurface,
    deepWell: AppColors.deepWell,
    insetPanel: AppColors.insetPanel,
    border: StudioColors.line,
    navigationSelection: Color.from(alpha: 0.08, red: 1, green: 1, blue: 1),
    textPrimary: Colors.white,
    textSecondary: Colors.white70,
    textTertiary: Colors.white38,
    ink: AppColors.slateInk,
    muted: AppColors.slateMuted,
    faint: AppColors.slateFaint,
    amber: AppColors.porchAmber,
    honey: AppColors.porchHoney,
    terracotta: AppColors.porchTerracotta,
    sage: AppColors.journalAccent,
    formAccent: AppColors.formMasterAccent,
    onAccent: AppColors.onChaosAccent,
    studioCard: StudioColors.card,
    studioRaise: StudioColors.raise,
    studioLineStrong: StudioColors.lineStrong,
    studioProse: StudioColors.prose,
    studioNarration: StudioColors.narration,
    studioAmberInk: StudioColors.amberInk,
    studioTeal: StudioColors.teal,
    studioBad: StudioColors.bad,
    chat: ChatDefaultColors.porchDark,
  );

  /// Porch, light (warm paper).
  static const AppPalette porchLight = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    card: AppColors.lightCard,
    surfaceContainer: AppColors.surfaceContainerLight,
    sunken: AppColors.sunkenSurfaceLight,
    deepWell: AppColors.deepWellLight,
    insetPanel: AppColors.insetPanelLight,
    border: AppColors.lightBorder,
    navigationSelection: Color(0xFFF3E0C4),
    textPrimary: Colors.black87,
    textSecondary: Colors.black54,
    textTertiary: Colors.black45,
    ink: AppColors.slateInkLight,
    muted: AppColors.slateMutedLight,
    faint: AppColors.slateFaintLight,
    // Darker than the old B45309 (4.2:1 on the paper) so accent text clears
    // 4.5:1; forms use it too instead of the dark-mode amber.
    amber: _porchAmberReadable,
    honey: AppColors.porchHoneyLight,
    terracotta: AppColors.porchTerracottaLight,
    sage: AppColors.journalAccentLight,
    formAccent: _porchAmberReadable,
    onAccent: Colors.white,
    studioCard: StudioColors.cardLight,
    studioRaise: StudioColors.raiseLight,
    studioLineStrong: StudioColors.lineStrongLight,
    studioProse: StudioColors.proseLight,
    studioNarration: StudioColors.mutedLight,
    studioAmberInk: StudioColors.amberInkLight,
    studioTeal: StudioColors.tealLight,
    studioBad: StudioColors.badLight,
    chat: ChatDefaultColors.porchLight,
  );

  /// The active palette: the theme's [AppThemePalettes] at the current
  /// brightness, or Porch when no app theme is installed (tests, goldens).
  static AppPalette of(BuildContext context) {
    final theme = Theme.of(context);
    final pair = theme.extension<AppThemePalettes>() ?? AppThemePalettes.porch;
    return theme.brightness == Brightness.light ? pair.light : pair.dark;
  }

  static AppPalette lerp(AppPalette a, AppPalette b, double t) {
    Color c(Color Function(AppPalette p) role) =>
        Color.lerp(role(a), role(b), t)!;
    return AppPalette(
      background: c((p) => p.background),
      surface: c((p) => p.surface),
      card: c((p) => p.card),
      surfaceContainer: c((p) => p.surfaceContainer),
      sunken: c((p) => p.sunken),
      deepWell: c((p) => p.deepWell),
      insetPanel: c((p) => p.insetPanel),
      border: c((p) => p.border),
      navigationSelection: c((p) => p.navigationSelection),
      textPrimary: c((p) => p.textPrimary),
      textSecondary: c((p) => p.textSecondary),
      textTertiary: c((p) => p.textTertiary),
      ink: c((p) => p.ink),
      muted: c((p) => p.muted),
      faint: c((p) => p.faint),
      amber: c((p) => p.amber),
      honey: c((p) => p.honey),
      terracotta: c((p) => p.terracotta),
      sage: c((p) => p.sage),
      formAccent: c((p) => p.formAccent),
      onAccent: c((p) => p.onAccent),
      studioCard: c((p) => p.studioCard),
      studioRaise: c((p) => p.studioRaise),
      studioLineStrong: c((p) => p.studioLineStrong),
      studioProse: c((p) => p.studioProse),
      studioNarration: c((p) => p.studioNarration),
      studioAmberInk: c((p) => p.studioAmberInk),
      studioTeal: c((p) => p.studioTeal),
      studioBad: c((p) => p.studioBad),
      chat: ChatDefaultColors.lerp(a.chat, b.chat, t),
      page: BookPageColors.lerp(a.page, b.page, t),
    );
  }

  List<Object> get _roles => [
    background,
    surface,
    card,
    surfaceContainer,
    sunken,
    deepWell,
    insetPanel,
    border,
    navigationSelection,
    textPrimary,
    textSecondary,
    textTertiary,
    ink,
    muted,
    faint,
    amber,
    honey,
    terracotta,
    sage,
    formAccent,
    onAccent,
    studioCard,
    studioRaise,
    studioLineStrong,
    studioProse,
    studioNarration,
    studioAmberInk,
    studioTeal,
    studioBad,
    chat,
    page,
  ];

  /// Value equality, so palettes built at runtime (a custom accent) share
  /// one [AppTheme] cache entry instead of leaking one per rebuild.
  @override
  bool operator ==(Object other) =>
      other is AppPalette && listEquals(_roles, other._roles);

  @override
  int get hashCode => Object.hashAll(_roles);
}

/// One app theme: its dark and light palettes, installed on [ThemeData] so
/// a theme switch animates and a subtree that flips brightness locally still
/// gets the matching palette.
@immutable
class AppThemePalettes extends ThemeExtension<AppThemePalettes> {
  const AppThemePalettes({required this.dark, required this.light});

  final AppPalette dark;
  final AppPalette light;

  static const AppThemePalettes porch = AppThemePalettes(
    dark: AppPalette.porchDark,
    light: AppPalette.porchLight,
  );

  @override
  AppThemePalettes copyWith({AppPalette? dark, AppPalette? light}) =>
      AppThemePalettes(dark: dark ?? this.dark, light: light ?? this.light);

  @override
  AppThemePalettes lerp(AppThemePalettes? other, double t) {
    if (other == null) return this;
    return AppThemePalettes(
      dark: AppPalette.lerp(dark, other.dark, t),
      light: AppPalette.lerp(light, other.light, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppThemePalettes && other.dark == dark && other.light == light;

  @override
  int get hashCode => Object.hash(dark, light);
}
