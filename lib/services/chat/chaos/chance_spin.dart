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

import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';

/// The Chance Time wheel's spin as plain maths, shared bit for bit with the
/// web twin (`web_ui/src/theme/chanceSpin.ts`) and pinned by
/// `test/fixtures/chaos/chance_spin_vectors.json`.
///
/// Outcome first: the slot is decided before anything moves and the plan
/// solves the spin that lands on it. Nothing stepped here can change where
/// the wheel stops; the engines on each surface (Flame on the desktop, a
/// canvas on the web) only dress what this says.

/// Slots on the wheel.
const int kChanceWheelSlots = 8;

/// One slot's angle.
const double kChanceSlotAngle = 2 * pi / kChanceWheelSlots;

/// How long the spin itself runs, before the settle.
const double kChanceSpinSeconds = 4.2;

/// How long the wheel creeps past the peg and settles back after the spin.
const double kChanceSettleSeconds = 0.55;

/// How far the landing overshoot reaches at its first swing, in radians.
const double kChanceOvershoot = 0.045;

/// Where the wheel is going: the slot it lands on and the total turn that
/// puts that slot under the pointer at the top.
class ChanceSpinPlan {
  const ChanceSpinPlan({
    required this.seed,
    required this.slot,
    required this.turns,
    required this.within,
    required this.total,
  });

  /// Draws the plan for [slot] from [seed]: four to six full turns, then a
  /// stop somewhere in the middle half of the slot so the same slot can
  /// land a little differently each time.
  factory ChanceSpinPlan.draw({required int seed, required int slot}) {
    final rng = Mulberry32(seed);
    final turns = 4 + (rng.next() * 3).floor();
    final within = 0.25 + rng.next() * 0.5;
    final landIn = slot * kChanceSlotAngle + kChanceSlotAngle * within;
    return ChanceSpinPlan(
      seed: seed,
      slot: slot,
      turns: turns,
      within: within,
      total: turns * 2 * pi + (2 * pi - landIn),
    );
  }

  final int seed;
  final int slot;
  final int turns;
  final double within;

  /// The whole rotation, in radians, from rest to the stop.
  final double total;
}

/// The slot under the pointer at the top for a wheel turned by [angle]:
/// slot i starts at i × slot angle at the top and the wheel turns
/// clockwise, so the pointer reads the wheel backwards.
int chanceSlotUnderPointer(double angle) {
  final tau = 2 * pi;
  final back = (tau - angle % tau) % tau;
  return (back / kChanceSlotAngle).floor() % kChanceWheelSlots;
}

/// Ease-out with a 2.5 power: quick off the line, and a tail that still
/// moves, so the last peg passes late and slowly instead of the wheel
/// sitting all but still for the final second.
double chanceEaseOut(double t) => 1 - pow(1 - t, 2.5).toDouble();

/// The wheel's angle at [time] seconds into the plan: the eased spin, then
/// the damped overshoot that settles onto the stop.
double chanceAngleAt(ChanceSpinPlan plan, double time) {
  if (time <= kChanceSpinSeconds) {
    return plan.total * chanceEaseOut(time / kChanceSpinSeconds);
  }
  final s = time - kChanceSpinSeconds;
  return plan.total + kChanceOvershoot * exp(-4.5 * s) * sin(14 * s);
}

/// Where the spin is, for the dressing each surface puts on it.
enum ChanceSpinPhase {
  /// At rest before the spin.
  idle,

  /// The first instant: bulbs wake, the glow swells.
  windup,

  /// Flat out: sparks shed off the rim.
  fast,

  /// Slowing: each peg clicks the pointer harder as the gaps open.
  slowing,

  /// The last stretch and the settle: the pointer trembles on the peg.
  nearMiss,

  /// The instant of the stop: shake, pop, flash.
  landing,

  /// Settled: the reveal plays and the card shows.
  reveal,
}

/// The spin stepped in time: the angle, its speed, the pointer's swing on
/// the pegs and the phase. Deterministic for a plan and a step size, which
/// is what the shared vectors pin.
class ChanceSpinSim {
  ChanceSpinSim(this.plan);

  final ChanceSpinPlan plan;

  double _time = 0;
  double _angle = 0;
  double _omega = 0;
  double _pointer = 0;
  double _pointerV = 0;
  int _clicks = 0;
  bool _started = false;
  bool _landedFired = false;

  /// Seconds since the spin started.
  double get time => _time;

  /// The wheel's rotation, radians, clockwise.
  double get angle => _angle;

  /// Angular speed, radians per second, from the last step.
  double get omega => _omega;

  /// The pointer's swing off its rest, radians; negative is bent back
  /// against the spin.
  double get pointer => _pointer;

  /// Pegs that have passed the pointer so far.
  int get clicks => _clicks;

  /// Whether the spin has been started.
  bool get started => _started;

  /// Whether the spin part is over and the wheel is on (or settling onto)
  /// its slot.
  bool get landed => _started && _time >= kChanceSpinSeconds;

  /// Whether the settle is over too and the reveal can play.
  bool get settled =>
      _started && _time >= kChanceSpinSeconds + kChanceSettleSeconds;

  /// Progress through the spin part, 0 to 1.
  double get progress => (_time / kChanceSpinSeconds).clamp(0.0, 1.0);

  ChanceSpinPhase get phase {
    if (!_started) return ChanceSpinPhase.idle;
    if (!landed) {
      if (progress < 0.08) return ChanceSpinPhase.windup;
      if (_omega.abs() > 9) return ChanceSpinPhase.fast;
      if (progress < 0.86) return ChanceSpinPhase.slowing;
      return ChanceSpinPhase.nearMiss;
    }
    if (settled) return ChanceSpinPhase.reveal;
    return _time - kChanceSpinSeconds < 0.25
        ? ChanceSpinPhase.landing
        : ChanceSpinPhase.nearMiss;
  }

  /// Starts the spin from rest.
  void start() => _started = true;

  /// Puts the wheel straight onto its slot, settled, with nothing moved:
  /// the reduce-motion path.
  void jumpToEnd() {
    _started = true;
    _time = kChanceSpinSeconds + kChanceSettleSeconds;
    _angle = plan.total;
    _omega = 0;
    _pointer = 0;
    _pointerV = 0;
    _landedFired = true;
  }

  /// Advances [dt] seconds. Returns true on the step that lands, once, so
  /// an engine can fire its landing effects.
  bool step(double dt) {
    if (!_started || dt <= 0) return false;
    final prev = _angle;
    _time += dt;
    _angle = chanceAngleAt(plan, _time);
    _omega = (_angle - prev) / dt;

    // Every peg that crossed the pointer this step kicks it back, harder
    // the faster the wheel; a spring brings it home.
    final crossed =
        (_angle / kChanceSlotAngle).floor() - (prev / kChanceSlotAngle).floor();
    if (crossed > 0) {
      _pointer -= (0.25 + _omega.abs() * 0.045).clamp(0.3, 0.95);
      _clicks += crossed;
    }
    const k = 260.0, c = 14.0;
    final ds = min(dt, 0.1);
    _pointerV += (-k * _pointer - c * _pointerV) * ds;
    _pointer += _pointerV * ds;
    // Flat out, the pegs come faster than the spring returns: the tip
    // lies back against the spin instead of winding up for ever.
    _pointer = _pointer.clamp(-1.1, 0.4);
    // The tip trembles on the last peg.
    if (!landed && progress > 0.86) _pointer += sin(_time * 90) * 0.01;

    if (landed && !_landedFired) {
      _landedFired = true;
      return true;
    }
    return false;
  }
}
