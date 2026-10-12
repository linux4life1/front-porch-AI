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

/// Chance Time's game-show palette (Mario Party style). It is the wheel's
/// own look in both themes, so it has no AppColors pairs.
class ChanceTimePalette {
  ChanceTimePalette._();

  /// Star gold: the title, rims, glow, spin button and the chaos reveal.
  static const Color gold = Color(0xFFFFD166);

  /// The deeper end of the spin button's gold gradient.
  static const Color goldDeep = Color(0xFFFFC233);

  /// The pale centre of the wheel's hub.
  static const Color goldPale = Color(0xFFFFF9C4);

  /// Ink on a gold fill.
  static const Color onGold = Color(0xFF1A1200);

  /// The overlay card's near-black backdrop.
  static const Color backdrop = Color(0xFF0D1117);

  /// Good-luck reveal.
  static const Color fortune = Color(0xFF06D6A0);

  /// Bad-luck reveal, and the hot end of the chaos pressure scale.
  static const Color misfortune = Color(0xFFE63946);

  /// Wild-card reveal and its shimmer.
  static const Color wildCard = Color(0xFF9B5DE5);

  /// The calm end of the chaos pressure scale.
  static const Color calm = Color(0xFF2EC4B6);

  /// Wheel segment colours, in slot order.
  static const List<Color> segments = [
    misfortune, // red
    Color(0xFFFF9F1C), // orange
    calm, // teal
    wildCard, // purple
    fortune, // green
    Color(0xFFFF6B9D), // pink
    gold, // amber
    Color(0xFF118AB2), // blue
  ];
}
