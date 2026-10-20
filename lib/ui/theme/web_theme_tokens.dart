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
import 'app_palette.dart';
import 'studio_colors.dart';

/// The colour tokens the web companion paints with.
///
/// The web never works out a palette itself: the desktop resolves the
/// theme here and the PWA writes each entry onto `:root` as `--<key>`.
/// Keys are the CSS custom property names in `web_ui/src/styles`; the dark
/// values are the web's own `:root` defaults, so a page that has not heard
/// from the desktop yet looks the same. Light values follow the desktop's
/// light tokens, and where only a context helper knows them
/// (`StatusColors`, `RealismColors`, `ChatColors`) the test pins them to
/// that helper.
class WebThemeTokens {
  WebThemeTokens._();

  /// The wire shape the snapshot and `settings_changed` carry: the
  /// desktop's mode and both resolved maps, so a device that overrides the
  /// mode switches without asking again.
  static Map<String, Object> wire(
    AppThemePalettes palettes, {
    required bool isDark,
  }) => {
    'mode': isDark ? 'dark' : 'light',
    'dark': resolve(palettes.dark, Brightness.dark),
    'light': resolve(palettes.light, Brightness.light),
  };

  /// Every token for [p] at [brightness], as CSS colour strings.
  static Map<String, String> resolve(AppPalette p, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    Color pick(Color d, Color l) => dark ? d : l;
    final wash = dark ? Colors.white : Colors.black;
    final colors = <String, Color>{
      // Grounds and ink (base.css).
      'bg': p.background,
      'surface': p.surface,
      'surface-2': p.surfaceContainer,
      'card': p.card,
      'border': p.border,
      'text': p.textPrimary,
      'muted': p.textSecondary,
      'faint': p.textTertiary,
      'text-strong': pick(Colors.white.withValues(alpha: 0.87), Colors.black87),
      'porch-terracotta': p.terracotta,
      'porch-honey': p.honey,
      'porch-amber': p.amber,
      // The ink on the accent fill, as the app theme's onPrimary.
      'on-accent': pick(AppColors.onChaosAccent, Colors.white),
      'accent-ink': Colors.white,
      'sparkle': pick(Colors.amberAccent, const Color(0xFF92400E)),
      // The theme's chat defaults; a colour the user picked still wins.
      'user-bubble': p.chat.userBubble,
      'ai-bubble': p.chat.aiBubble,
      'dialogue': p.chat.dialogue,
      'action': p.chat.action,
      'danger': pick(AppColors.logError, const Color(0xFFB71C1C)),
      'ok': pick(Colors.greenAccent, const Color(0xFF1B5E20)),
      'logwarn': pick(const Color(0xFFF0C000), const Color(0xFF92400E)),
      'accent-amber': pick(Colors.amber, const Color(0xFF92400E)),
      'tag-text': pick(const Color(0xFFF0D492), p.honey),
      'group-accent-bright': pick(const Color(0xFFF0B195), p.terracotta),
      'bond-high': pick(AppColors.bondHigh, AppColors.bondHighLight),
      'bond-mid': pick(AppColors.bondMid, AppColors.bondMidLight),
      'bond-low': pick(AppColors.bondLow, AppColors.bondLowLight),
      'bond-neg': pick(AppColors.bondNeg, AppColors.bondNegLight),
      'guest-bg': pick(
        Colors.pinkAccent,
        AppColors.relationshipAccentLight,
      ).withValues(alpha: 0.9),
      'wash': wash,
      'scrim-ink': Colors.black,
      'image-ink': Colors.white,
      'image-scrim': AppColors.background,
      'info': pick(const Color(0xFF3B82F6), const Color(0xFF1D4ED8)),
      'warn': pick(Colors.amber, const Color(0xFF92400E)),
      'alert': pick(AppColors.alertRed, AppColors.alertRedLight),
      'quote-ink': pick(Colors.amberAccent, const Color(0xFF92400E)),
      'narration-ink': pick(AppColors.action, AppColors.actionLight),
      'growth-habit': pick(const Color(0xFF9EC97F), const Color(0xFF3F6212)),
      'growth-archive': pick(const Color(0xFF7E8798), const Color(0xFF5F6675)),
      'chip-well': pick(Colors.transparent, p.card),
      'growth-scar': pick(const Color(0xFFD99AA6), const Color(0xFF9D174D)),
      ..._realism(pick),
      ..._studio(p),
      ..._kobold(p, dark, wash),
    };
    return {for (final e in colors.entries) e.key: css(e.value)};
  }

  /// Realism & Needs chips: one hue per stat, only lightness moves by mode.
  static Map<String, Color> _realism(Color Function(Color, Color) pick) => {
    'need-hunger': pick(Colors.orangeAccent, const Color(0xFFA03C08)),
    'need-bladder': pick(Colors.lightBlueAccent, const Color(0xFF075985)),
    'need-energy': pick(const Color(0xFFD97706), const Color(0xFF92400E)),
    'need-social': pick(Colors.pinkAccent, const Color(0xFF9D174D)),
    'need-fun': pick(Colors.deepPurpleAccent, const Color(0xFF6D28D9)),
    'need-hygiene': pick(Colors.cyanAccent, const Color(0xFF155E75)),
    'need-comfort': pick(Colors.greenAccent, const Color(0xFF1B5E20)),
    'need-other': pick(Colors.grey, const Color(0xFF575757)),
    'bond-up': pick(Colors.pinkAccent, const Color(0xFF9D174D)),
    'bond-down': pick(Colors.redAccent, const Color(0xFFB71C1C)),
    'trust-up': pick(AppColors.bondMid, const Color(0xFF1D4ED8)),
    'trust-down': pick(Colors.deepPurpleAccent, const Color(0xFF6D28D9)),
    'lust-up': pick(Colors.deepOrangeAccent, const Color(0xFFA3330F)),
    'lust-down': pick(Colors.lightBlueAccent, const Color(0xFF075985)),
  };

  /// Porch Stories (studio.css), the web twin of [StudioColors].
  static Map<String, Color> _studio(AppPalette p) => {
    'studio-bg': p.background,
    'studio-side': p.surface,
    'studio-card': p.studioCard,
    'studio-raise': p.studioRaise,
    'studio-line': p.border,
    'studio-line-strong': p.studioLineStrong,
    'studio-scrim': StudioColors.scrim,
    'studio-ink': p.ink,
    'studio-muted': p.muted,
    'studio-faint': p.faint,
    'studio-prose': p.studioProse,
    'studio-amber': p.amber,
    'studio-honey': p.honey,
    'studio-terra': p.terracotta,
    'studio-teal': p.studioTeal,
    'studio-bad': p.studioBad,
    'studio-amber-ink': p.studioAmberInk,
    // Cover and portrait gradients are one tone in both modes, as on the
    // desktop.
    'studio-avatar-from': StudioColors.portraitStart,
    'studio-cover-from': StudioColors.coverStart,
  };

  /// The local-model and KoboldCpp preset cards (kobold.css).
  static Map<String, Color> _kobold(AppPalette p, bool dark, Color wash) {
    T pick<T>(T d, T l) => dark ? d : l;
    return {
      'kc-card': p.card,
      'kc-inset': p.insetPanel,
      'kc-sunken': p.sunken,
      'kc-ink': p.ink,
      'kc-muted': p.muted,
      'kc-faint': p.faint,
      'kc-amber': p.amber,
      'kc-amber-solid': p.formAccent,
      'kc-on-amber': AppColors.onPorchAmber,
      'kc-honey': p.honey,
      'kc-teal': p.sage,
      'kc-on-teal': AppColors.onJournalAccent,
      'kc-red': pick(AppColors.alertRed, AppColors.alertRedLight),
      'kc-line': wash.withValues(alpha: pick(0.1, 0.09)),
      'kc-line-strong': wash.withValues(alpha: pick(0.12, 0.11)),
    };
  }

  /// [c] as `#rrggbb`, or `rgba(r, g, b, a)` when it is translucent.
  static String css(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
    final a = (argb >> 24) & 0xFF;
    if (a == 0xFF) {
      String hex(int v) => v.toRadixString(16).padLeft(2, '0');
      return '#${hex(r)}${hex(g)}${hex(b)}';
    }
    final alpha = double.parse((a / 255).toStringAsFixed(3));
    return 'rgba($r, $g, $b, $alpha)';
  }
}
