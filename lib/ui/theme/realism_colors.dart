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

/// One hue per Realism and Needs stat on the chips under a reply. Users learn
/// "orange is hunger", so the hue never changes by theme; only brightness
/// tunes it. Mood and Chance Time reuse [AppColors.emotionAccentOf] and
/// [AppColors.chaosAccentOf].
class RealismColors {
  RealismColors._();

  static Color hungerOf(BuildContext context) =>
      AppColors.resolve(context, Colors.orangeAccent, const Color(0xFFA03C08));
  static Color bladderOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.lightBlueAccent,
    const Color(0xFF075985),
  );
  static Color energyOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFD97706),
    const Color(0xFF92400E),
  );
  static Color socialOf(BuildContext context) =>
      AppColors.resolve(context, Colors.pinkAccent, const Color(0xFF9D174D));
  static Color funOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.deepPurpleAccent,
    const Color(0xFF6D28D9),
  );
  static Color hygieneOf(BuildContext context) =>
      AppColors.resolve(context, Colors.cyanAccent, const Color(0xFF155E75));
  static Color comfortOf(BuildContext context) =>
      AppColors.resolve(context, Colors.greenAccent, const Color(0xFF1B5E20));

  /// The needs bar's energy fill, a brighter gold than the chip.
  static Color energyBarOf(BuildContext context) =>
      AppColors.resolve(context, Colors.amberAccent, const Color(0xFF92400E));

  /// A need this build has no hue for.
  static Color otherNeedOf(BuildContext context) =>
      AppColors.resolve(context, Colors.grey, const Color(0xFF575757));

  static Color bondUpOf(BuildContext context) => socialOf(context);
  static Color bondDownOf(BuildContext context) =>
      AppColors.resolve(context, Colors.redAccent, const Color(0xFFB71C1C));

  /// The bond meter's middle blue in dark mode.
  static Color trustUpOf(BuildContext context) =>
      AppColors.resolve(context, AppColors.bondMid, const Color(0xFF1D4ED8));
  static Color trustDownOf(BuildContext context) => funOf(context);
  static Color lustUpOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.deepOrangeAccent,
    const Color(0xFFA3330F),
  );
  static Color lustDownOf(BuildContext context) => bladderOf(context);

  /// Time running the wrong way.
  static Color timeOddOf(BuildContext context) => hygieneOf(context);

  /// Valence of an intragroup feeling score, green for warm and red for
  /// hostile. The thresholds match the tier boundaries.
  static Color feelingScaleOf(BuildContext context, int value) {
    final light = AppColors.isLight(context);
    if (value >= 80) {
      return light ? const Color(0xFF14532D) : Colors.greenAccent.shade200;
    }
    if (value >= 50) {
      return light ? const Color(0xFF166534) : Colors.greenAccent.shade400;
    }
    if (value >= 20) {
      return light ? const Color(0xFF1E6B34) : Colors.greenAccent.shade700;
    }
    if (value >= 5) return light ? const Color(0xFF3F6212) : Colors.lightGreen;
    if (value >= -4) return AppColors.textSecondary(context);
    if (value >= -19) {
      return light ? const Color(0xFF9A3412) : Colors.orangeAccent;
    }
    if (value >= -49) {
      return light ? const Color(0xFFA3330F) : Colors.deepOrangeAccent;
    }
    if (value >= -79) return light ? const Color(0xFFB71C1C) : Colors.redAccent;
    return light ? const Color(0xFF7F1D1D) : Colors.red.shade700;
  }

  /// The ring around a group member's avatar, by their current emotion. A
  /// legend: grief and anger must not look alike, so the hues are the
  /// meaning. Unrecognised labels fall back to grey.
  static Color emotionRing(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'joy':
      case 'amusement':
      case 'excitement':
        return Colors.amber;
      case 'sadness':
      case 'grief':
      case 'disappointment':
        return Colors.blueGrey;
      case 'anger':
      case 'annoyance':
        return Colors.redAccent;
      case 'fear':
      case 'nervousness':
        return Colors.deepPurpleAccent;
      case 'affection':
      case 'love':
        return Colors.pinkAccent;
      case 'anticipation':
      case 'desire':
        return Colors.orangeAccent;
      default:
        return Colors.grey;
    }
  }

  /// The tooltip on a chip: the theme's card, not a fixed slate.
  static BoxDecoration tooltipDecoration(BuildContext context) => BoxDecoration(
    color: AppColors.cardOf(context),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: AppColors.borderOf(context)),
  );

  static TextStyle tooltipText(BuildContext context) =>
      TextStyle(fontSize: 12, color: AppColors.textPrimary(context));
}
