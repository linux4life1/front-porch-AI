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

/// The Boons & Bogies milestone colours (docs/design/boons-and-bogies.md §7):
/// the celebration's game identity, fixed in every theme like Chance Time's.
/// The card's chrome (surface, border, text) follows the app theme instead.
/// The web twin is `web_ui/src/theme/milestonePalette.ts` (theme-keep).
class MilestonePalette {
  MilestonePalette._();

  /// Boon gold: the star, the Accept button, a boon's ring box.
  static const Color gold = Color(0xFFFFD166);
  static const Color goldDeep = Color(0xFFFFC233);

  /// Ink on a gold fill.
  static const Color onGold = Color(0xFF1A1200);

  /// Bogey violet: a bogey's ring box and its Master badge.
  static const Color violet = Color(0xFF9B5DE5);

  /// Smoke.
  static const Color smoke = Color(0xFF7D7590);

  /// Overcome green.
  static const Color overcome = Color(0xFF06D6A0);

  static const Color pink = Color(0xFFFF6B9D);
  static const Color blue = Color(0xFF118AB2);
  static const Color white = Color(0xFFFFFFFF);

  /// The card's drop shadow over the scrim, and the celebration's clear
  /// backdrop.
  static const Color shadow = Color(0x59000000);
  static const Color clear = Color(0x00000000);

  /// The sim's colour slots, in `BurstColor` order
  /// (lib/services/chat/milestone_burst.dart).
  static const List<Color> slots = [
    gold,
    goldDeep,
    violet,
    smoke,
    overcome,
    pink,
    blue,
    white,
  ];
}
