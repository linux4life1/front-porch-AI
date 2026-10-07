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

import 'package:front_porch_ai/services/chat/body_clock.dart';

/// Wear the story clock charges a body, in points per story hour, day or
/// night. Nothing here assumes a night was slept: sleep is an event the
/// needs judge scores when the reply shows it. The other four needs move
/// only on events. See docs/design/needs-on-the-clock.md.
const Map<String, int> needsWearPerHour = {
  'hunger': 6,
  'bladder': 15,
  'energy': 5,
};

/// Off-screen, people look after themselves: a skip (OOC, narrative, time
/// away, next morning) never wears a bar below these.
const Map<String, int> needsSkipFloors = {
  'hunger': 45,
  'bladder': 60,
  'energy': 25,
};

/// A beat's wear stops at this bar unless the bar was already in the crisis
/// band when the beat began, so there is always one warning turn before
/// the catastrophe at 0.
const int needsWearStopsAt = 1;

/// The crisis band's top: a bar at or under it may be worn to 0.
const int needsCrisisBandTop = 10;

/// Snapshot key for the carried fractions, beside `vector`.
const String kNeedsWearCarryKey = 'wear_carry';

/// Message metadata: the speaker's carry when the turn began, beside
/// `needs_pre_turn_vector`, so a regen replays the beat from the same
/// fraction.
const String kNeedsPreTurnCarry = 'needs_pre_turn_carry';

/// A carry map read back from JSON or a dynamic snapshot.
Map<String, double> wearCarryFrom(Map<dynamic, dynamic> raw) => {
  for (final e in raw.entries)
    if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
};

/// Points one span costs, plus the fraction carried to the next beat.
class NeedsWear {
  const NeedsWear({required this.points, required this.carry});

  /// Whole points to subtract, per need that wears (never negative).
  final Map<String, int> points;

  /// The fraction left over per need, carried into the next span so ten
  /// 2-minute beats cost what one 20-minute beat costs.
  final Map<String, double> carry;

  bool get isEmpty => points.values.every((p) => p == 0);
}

/// Wear for [minutes] of story time at [pace], continuing from [carry].
/// Needs not in [on] are skipped and keep their carry. Pace scales the wear
/// exactly as it scales a scene drop (sloth two thirds, fast four thirds).
NeedsWear needsWearForSpan({
  required int minutes,
  required BodyPace pace,
  required Iterable<String> on,
  Map<String, double> carry = const {},
}) {
  final points = <String, int>{};
  final nextCarry = Map<String, double>.from(carry);
  if (minutes <= 0) return NeedsWear(points: points, carry: nextCarry);
  final factor = switch (pace) {
    BodyPace.sloth => 2 / 3,
    BodyPace.normal => 1.0,
    BodyPace.fast => 4 / 3,
  };
  for (final need in on) {
    final rate = needsWearPerHour[need];
    if (rate == null) continue;
    final owed = (carry[need] ?? 0) + minutes / 60 * rate * factor;
    final whole = owed.floor();
    points[need] = whole;
    nextCarry[need] = owed - whole;
  }
  return NeedsWear(points: points, carry: nextCarry);
}

/// Where a bar lands after [drop] points of wear.
///
/// On-screen ([offScreen] false) the wear stops at [needsWearStopsAt] unless
/// the bar began in the crisis band, so the accident never ambushes a bar
/// that was fine a turn ago. Off-screen the bar never lands below the
/// need's skip floor; a bar already under the floor is left where it is.
int wornBar({
  required String need,
  required int current,
  required int drop,
  required bool offScreen,
}) {
  if (drop <= 0 || current <= 0) return current;
  if (offScreen) {
    final floor = needsSkipFloors[need] ?? 0;
    if (current <= floor) return current;
    return (current - drop).clamp(floor, current);
  }
  final stop = current <= needsCrisisBandTop ? 0 : needsWearStopsAt;
  return (current - drop).clamp(stop, current);
}
