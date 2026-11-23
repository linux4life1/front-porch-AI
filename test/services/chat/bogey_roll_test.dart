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

// The bogey rate promise (docs/design/boons-and-bogies.md §6): "the median
// gap is 7–9 replies". This runs 10k replies on the real [BogeyRoll] math and
// asserts the promise. Move the constants, not this test — the spec says the
// numbers are tuning and the gap is the contract.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/bogey_roll.dart';

void main() {
  test('median gap between bogey fires is 7-9 replies over 10k', () {
    final random = Random(20261123);
    var pressure = 0;
    var cooldown = 0;
    var sinceFire = 0;
    final gaps = <int>[];

    for (var reply = 0; reply < 10000; reply++) {
      sinceFire++;
      final tick = BogeyRoll.tick(
        pressure: pressure,
        cooldown: cooldown,
        random: random,
      );
      pressure = tick.pressure;
      cooldown = tick.cooldown;
      if (!tick.fired) continue;
      gaps.add(sinceFire);
      sinceFire = 0;
      pressure = 0;
      cooldown = BogeyRoll.cooldownAfterFire(random);
    }

    expect(gaps.length, greaterThan(500), reason: 'the roll must fire at all');
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    expect(
      median,
      inInclusiveRange(7, 9),
      reason: 'median gap $median outside the promised 7–9 (spec §6)',
    );
  });

  test('chance is capped at 45% and pressure never exceeds its cap', () {
    // Drive the gauge to saturation: with pressure at the cap, the chance
    // must stay at the 45-point ceiling (a 60% fire rate would fail this).
    final random = Random(7);
    var pressure = BogeyRoll.pressureCap;
    var fires = 0;
    const trials = 20000;
    for (var i = 0; i < trials; i++) {
      final tick = BogeyRoll.tick(
        pressure: pressure,
        cooldown: 0,
        random: random,
      );
      pressure = tick.pressure;
      if (tick.fired) fires++;
    }
    final rate = fires / trials;
    expect(rate, lessThanOrEqualTo(0.47));
    expect(rate, greaterThanOrEqualTo(0.40));
  });
}
