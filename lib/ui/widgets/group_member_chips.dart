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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// The compact chips a NON-expanded group member card shows, plus the emotion
// ring colour, lifted verbatim out of group_member_card.dart on 2026-08-08.
//
// Why: that file was already 681 lines, past the 500 cap, and adding the
// Pockets & Wardrobe mount would have pushed it to 708. CLAUDE.md's rule for a
// file already over the cap is not "add carefully" but "extract something", so
// these three pure presentational leaves — no state, nothing but their
// arguments and the theme — moved out. The card gains a feature and ends up
// SMALLER than it started, which is the character_grid_card precedent.
//
// Moved byte-for-byte, including the hardcoded emotion hues below. Those are a
// semantic legend (this palette IS the meaning), they predate the warm-porch
// standard, and rewriting them here would change pixels in goldens that cover
// this card — a colour decision is its own change, not a side effect of a move.

/// A tiny "B60" / "T-20" tier pill on a collapsed member card. Negative values
/// flip to the negative accent regardless of the passed [color], which is how
/// a bad bond reads as bad at a glance.
class MiniTierChip extends StatelessWidget {
  const MiniTierChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isNeg = value < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: (isNeg ? AppColors.negativeAccentOf(context) : color)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$label${value.abs()}',
        style: TextStyle(
          fontSize: 9,
          color: isNeg ? AppColors.negativeAccentOf(context) : color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One urgent need as a two-letter abbreviation and a number ("Hu12"), amber
/// normally and the negative accent once it crosses [needCriticalThreshold].
/// Two letters (not one) so needs sharing an initial — hunger/hygiene,
/// bladder/bowels — stay distinguishable at a glance.
class MiniNeedChip extends StatelessWidget {
  const MiniNeedChip({super.key, required this.name, required this.value});

  final String name;
  final int value;

  @override
  Widget build(BuildContext context) {
    final isCrit = value <= needCriticalThreshold;
    final abbr = name.length >= 2 ? name.substring(0, 2) : name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color:
            (isCrit
                    ? AppColors.negativeAccentOf(context)
                    : AppColors.porchAmberOf(context))
                .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '${abbr[0].toUpperCase()}${abbr.substring(1)}$value',
        style: TextStyle(
          fontSize: 9,
          color: isCrit
              ? AppColors.negativeAccentOf(context)
              : AppColors.porchAmberOf(context),
        ),
      ),
    );
  }
}

/// The ring drawn around a member's avatar, coloured by their current emotion.
///
/// A semantic legend rather than chrome — the whole point is that grief and
/// anger do not look alike — which is why these stay off the warm-porch
/// palette. Moved verbatim; unrecognised labels fall back to grey.
// theme-keep: emotion legend — the hues ARE the meaning, and were approved as
// semantic when this card shipped.
Color emotionRingColor(String emotion) {
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
