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

import 'package:front_porch_ai/database/database.dart' show GrowthRingData;
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/chat/pressure_roll.dart';

/// One bogey's gauge: pressure 0..100 and replies of cooldown left.
typedef BogeyGauge = ({int pressure, int cooldown});

/// One reply's outcome ([BogeyRoll.reply]): the index that fired (null =
/// quiet) and every gauge after the reply, index for index.
typedef BogeyReply = ({int? fired, List<BogeyGauge> after});

/// Bogey rolls — the Boons & Bogies half of the shared pressure gauge
/// (docs/design/boons-and-bogies.md §6).
///
/// Pure and side-effect free, like [PressureRoll] itself: one [tick] per
/// reply per active bogey, and at most one of the fired ones is chosen
/// ([pickFired]) — highest pressure, ties random. The rate must not scale
/// with the number of flaws, so the caller rolls every bogey but parks at
/// most one injection per reply.
///
/// The tuning (base 3, growth 4 jittered 2–6, cooldown 2 jittered 1–3,
/// chance capped 45%) is pinned by a simulation test over 10k replies that
/// asserts the median gap between fires is 7–9 replies. Move the constants,
/// not the test (spec §6).
class BogeyRoll {
  BogeyRoll._();

  /// Chance in percent before any pressure has built.
  static const int base = 3;

  /// Pressure added per reply: [growthMin]..[growthMax].
  static const int growthMin = 2;
  static const int growthMax = 6;

  /// Replies spent quiet after a fire: [cooldownMin]..[cooldownMax].
  static const int cooldownMin = 1;
  static const int cooldownMax = 3;

  /// The chance ceiling. Without it the v1 numbers produced a gap near
  /// 10–11 replies instead of the promised 6–9.
  static const int chanceCap = 45;

  static const int pressureCap = 100;

  /// One reply on one bogey's gauge.
  static PressureRollTick tick({
    required int pressure,
    required int cooldown,
    required Random random,
  }) => PressureRoll.tick(
    base: base,
    growthMin: growthMin,
    growthMax: growthMax,
    pressureCap: pressureCap,
    chanceCap: chanceCap,
    pressure: pressure,
    cooldown: cooldown,
    random: random,
  );

  /// The quiet stretch after a fire.
  static int cooldownAfterFire(Random random) => PressureRoll.cooldownAfterFire(
    min: cooldownMin,
    max: cooldownMax,
    random: random,
  );

  /// One whole reply over every rollable bogey's gauge, in [gauges] order:
  /// tick each, pick at most one fired index, and start that one's cooldown
  /// with its pressure back at zero. [BogeyRolls.rollTurn] persists exactly
  /// what this returns, so the simulation test that drives it pins the rate
  /// the app really rolls — not a loop the test wrote for itself.
  static BogeyReply reply(List<BogeyGauge> gauges, Random random) {
    final ticks = [
      for (final g in gauges)
        tick(pressure: g.pressure, cooldown: g.cooldown, random: random),
    ];
    final fired = pickFiredIndex(ticks, random);
    return (
      fired: fired,
      after: [
        for (var i = 0; i < ticks.length; i++)
          i == fired
              ? (pressure: 0, cooldown: cooldownAfterFire(random))
              : (pressure: ticks[i].pressure, cooldown: ticks[i].cooldown),
      ],
    );
  }

  /// The count a fire leaves behind (§3.2: bogies advance on times they
  /// actually fired), held one below Master until the milestone ships.
  /// Strength follows it through [BoonsBogies.bogeyStrength].
  static int advanceAfterFire(int advanceCount) =>
      BoonsBogies.nextBogeyAdvance(advanceCount);

  /// The one ring that fires this reply: highest post-tick pressure among
  /// the fired ones, ties broken at random. Null when none fired.
  ///
  /// [rings] and [ticks] are parallel lists, index for index.
  static GrowthRingData? pickFired(
    List<GrowthRingData> rings,
    List<PressureRollTick> ticks,
    Random random,
  ) {
    final i = pickFiredIndex(ticks, random);
    return i == null ? null : rings[i];
  }

  /// [pickFired] by index.
  static int? pickFiredIndex(List<PressureRollTick> ticks, Random random) {
    var best = -1;
    var ties = 0;
    for (var i = 0; i < ticks.length; i++) {
      if (!ticks[i].fired) continue;
      final p = ticks[i].pressure;
      if (best < 0 || p > ticks[best].pressure) {
        best = i;
        ties = 1;
      } else if (p == ticks[best].pressure) {
        // Reservoir pick among equal pressures: stays fair without a list.
        ties++;
        if (random.nextInt(ties) == 0) best = i;
      }
    }
    return best < 0 ? null : best;
  }

  /// The rings a reply rolls for: active bogeys of one owner. Pinned rings
  /// still fire — pinning protects a flaw from fading, not from the story.
  static List<GrowthRingData> rollable(List<GrowthRingData> activeRings) =>
      activeRings
          .where((r) => r.category == 'bogey' && !r.retired)
          .toList(growable: false);

  /// The nudge injected when [ring] fires (§6). Soft, not an event, and
  /// deliberately free of a "try something new" hint: regen and swipe
  /// re-inject this identical line, and the user's own regen reason is the
  /// only thing steering how the flaw lands (ruling 19).
  static String injectionText(GrowthRingData ring, String charName) =>
      'This reply, let $charName\'s flaw show in a small, natural way: '
      '${ring.content}';
}
