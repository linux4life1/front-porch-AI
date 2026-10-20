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

  // calcTier() and tierName() used to live here as a second, hand-copied
  // ladder and vocabulary. Both had drifted from the engine: the numeric
  // bands at three rungs (75/110/150 vs 80/120/160) and the names at five
  // (tier 5 was 'Warm' here and 'Amiable' in the engine, while 'Warm' in
  // the engine means tier 3 — the same word for two different bonds).
  // Tiers and names now come from RelationshipService; this class owns
  // only the colour mapping, which is a genuine UI concern.

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
