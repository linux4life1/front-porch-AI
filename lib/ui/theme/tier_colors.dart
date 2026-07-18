// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'app_colors.dart';

/// The single relationship-tier ladder (score → tier → name → color).
///
/// Consolidates the two byte-identical copies that lived in
/// realism_section.dart (getTierColor closure) and group_member_card.dart
/// (_calcTier/_tierName/_tierColor) so 1:1 bars, group member cards, and any
/// future surface always agree. Semantics preserved verbatim from those
/// copies, with two deliberate reroutes into the warm-porch token family:
/// tier 5 "Warm" → AppColors.porchAmber and the plain negative reds →
/// AppColors.negativeAccent where the shade matched.
class TierColors {
  TierColors._();

  /// Score (±300 bond scale) → tier (−10…10).
  static int calcTier(int score) {
    final abs = score.abs();
    if (abs < 5) return 0;
    if (abs < 15) return score > 0 ? 1 : -1;
    if (abs < 30) return score > 0 ? 2 : -2;
    if (abs < 50) return score > 0 ? 3 : -3;
    if (abs < 75) return score > 0 ? 4 : -4;
    if (abs < 110) return score > 0 ? 5 : -5;
    if (abs < 150) return score > 0 ? 6 : -6;
    if (abs < 200) return score > 0 ? 7 : -7;
    if (abs < 250) return score > 0 ? 8 : -8;
    if (abs < 300) return score > 0 ? 9 : -9;
    return score > 0 ? 10 : -10;
  }

  static String tierName(int tier) {
    switch (tier) {
      case 10:
        return 'Devoted';
      case 9:
        return 'Enamored';
      case 8:
        return 'Smitten';
      case 7:
        return 'Affectionate';
      case 6:
        return 'Fond';
      case 5:
        return 'Warm';
      case 4:
        return 'Friendly';
      case 3:
        return 'Neutral+';
      case 2:
        return 'Neutral';
      case 1:
        return 'Cool';
      case 0:
        return 'Indifferent';
      case -1:
        return 'Distant';
      case -2:
        return 'Cold';
      case -3:
        return 'Hostile';
      case -4:
        return 'Resentful';
      case -5:
        return 'Bitter';
      case -6:
        return 'Hateful';
      case -7:
        return 'Despising';
      case -8:
        return 'Loathing';
      case -9:
        return 'Reviling';
      case -10:
        return 'Abhorrent';
      default:
        return 'Unknown';
    }
  }

  /// Tier → bar/label color, light-mode safe.
  static Color tierColor(BuildContext context, int tier) {
    // Strong positive tiers (vibrant, work on both themes)
    if (tier >= 10) return Colors.deepPurpleAccent;
    if (tier >= 9) return Colors.purpleAccent;
    if (tier >= 8) return Colors.pinkAccent;
    if (tier >= 7) return Colors.pink;
    if (tier >= 6) return Colors.pink.shade200;
    if (tier >= 5) return AppColors.porchAmberOf(context);
    if (tier >= 4) return AppColors.bondHighOf(context);

    // Neutral / low tiers — context-aware for light mode readability
    if (tier >= 3) {
      return AppColors.resolve(context, Colors.lightBlue, Colors.blue.shade700);
    }
    if (tier >= 2) {
      return AppColors.resolve(
        context,
        Colors.blueGrey,
        Colors.blueGrey.shade700,
      );
    }
    if (tier >= 1) {
      return AppColors.resolve(
        context,
        Colors.grey.shade400,
        Colors.grey.shade700,
      );
    }
    if (tier == 0) {
      return AppColors.textTertiary(context);
    }

    // Negative tiers
    if (tier >= -1) {
      return AppColors.resolve(
        context,
        Colors.orangeAccent.shade100,
        Colors.orange.shade700,
      );
    }
    if (tier >= -2) {
      return AppColors.resolve(
        context,
        Colors.redAccent.shade100,
        Colors.red.shade600,
      );
    }
    if (tier >= -3) return AppColors.negativeAccentOf(context);
    if (tier >= -4) return Colors.red;
    if (tier >= -5) {
      return AppColors.resolve(context, Colors.red.shade900, Colors.red.shade800);
    }
    if (tier >= -6) {
      return AppColors.resolve(
        context,
        Colors.brown.shade900,
        Colors.brown.shade700,
      );
    }
    if (tier >= -7) {
      return AppColors.resolve(
        context,
        Colors.deepOrange.shade900,
        Colors.deepOrange.shade700,
      );
    }
    if (tier >= -8) {
      return AppColors.resolve(
        context,
        Colors.amber.shade900,
        Colors.amber.shade800,
      );
    }
    if (tier >= -9) {
      return AppColors.resolve(
        context,
        Colors.orange.shade900,
        Colors.orange.shade800,
      );
    }
    return AppColors.textPrimary(context);
  }
}
