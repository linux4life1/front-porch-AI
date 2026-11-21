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

import 'dart:math';

/// One turn of a grow → roll → cooldown pressure gauge — the math Chance Time
/// and Boons & Bogies' bogey rolls share (docs/design/boons-and-bogies.md §6).
///
/// Pure and side-effect free: the caller owns the stored gauge (the 1:1
/// Chaos Mode scalars, a group member's realism bag, or a growth ring's
/// columns) and commits a fire itself. [tick] advances the gauge one turn;
/// [cooldownAfterFire] draws the cooldown a caller starts when it applies a
/// fire.
///
/// Chance Time is the first caller and must stay bit-for-bit unchanged: it
/// passes fixed growth/cooldown (so no extra random draws are consumed) and a
/// 100-point chance cap, exactly the arithmetic it had inline. The golden
/// vectors in `test/fixtures/chaos/pressure_roll_vectors.json` fail if this
/// class ever shifts a roll.
class PressureRoll {
  PressureRoll._();

  /// Rolls are drawn on a 0–99 percent scale — the `nextInt(100)` Chance Time
  /// has always used, so extracting this class cannot move its stream.
  static const int rollScale = 100;

  /// One turn on the gauge.
  ///
  /// A cooldown turn spends the turn with no growth and no roll. Otherwise
  /// the pressure grows by a value in [growthMin]..[growthMax] (a fixed value
  /// draws nothing), the chance is `base + pressure` capped at [chanceCap],
  /// and one [rollScale]-sided roll decides it. Pressure itself is capped at
  /// [pressureCap].
  static PressureRollTick tick({
    required int base,
    required int growthMin,
    required int growthMax,
    required int pressureCap,
    required int chanceCap,
    required int pressure,
    required int cooldown,
    required Random random,
  }) {
    if (cooldown > 0) {
      return PressureRollTick(
        fired: false,
        pressure: pressure,
        cooldown: cooldown - 1,
      );
    }
    final growth = growthMin == growthMax
        ? growthMin
        : growthMin + random.nextInt(growthMax - growthMin + 1);
    final newPressure = (pressure + growth).clamp(0, pressureCap);
    final chance = (base + newPressure).clamp(0, chanceCap);
    final roll = random.nextInt(rollScale);
    return PressureRollTick(
      fired: roll < chance,
      pressure: newPressure,
      cooldown: 0,
      roll: roll,
    );
  }

  /// The cooldown to start after a fire, in [min]..[max]. A fixed range
  /// returns without drawing (Chance Time's frequencies), so a shared roll
  /// stream keeps its exact sequence; a jittered range (bogey rolls) draws
  /// once.
  static int cooldownAfterFire({
    required int min,
    required int max,
    required Random random,
  }) {
    if (min == max) return min;
    return min + random.nextInt(max - min + 1);
  }
}

/// The gauge after one [PressureRoll.tick].
class PressureRollTick {
  const PressureRollTick({
    required this.fired,
    required this.pressure,
    required this.cooldown,
    this.roll,
  });

  /// Whether the roll fired this turn.
  final bool fired;

  /// The gauge after the turn (grown, or unchanged on a cooldown turn).
  final int pressure;

  /// The cooldown after the turn (decremented, or 0 outside one).
  final int cooldown;

  /// The 0–99 draw; null on a cooldown turn, when no roll happened.
  final int? roll;
}
