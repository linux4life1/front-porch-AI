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

// The Chance Time spin (`chance_spin.dart`): outcome first, the plan lands
// on the slot it was given for every seed; the stepped sim reproduces the
// shared vectors (test/fixtures/chaos/chance_spin_vectors.json) the web
// twin is pinned to; the last peg passes late so the finish is a near
// miss, not a dead second; the landing fires once; reduce motion's jump
// lands settled with nothing swung.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chaos/chance_spin.dart';

final Map<String, dynamic> _vectors =
    jsonDecode(
          File(
            'test/fixtures/chaos/chance_spin_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Matcher _near(num v) => closeTo(v, 1e-9);

void main() {
  group('outcome first', () {
    test('every plan lands on the slot it was given', () {
      for (var seed = 1; seed <= 200; seed++) {
        for (var slot = 0; slot < kChanceWheelSlots; slot++) {
          final plan = ChanceSpinPlan.draw(seed: seed * 7919, slot: slot);
          expect(
            chanceSlotUnderPointer(plan.total),
            slot,
            reason: 'seed ${seed * 7919} slot $slot',
          );
          expect(plan.turns, inInclusiveRange(4, 6));
          expect(plan.within, inInclusiveRange(0.25, 0.75));
        }
      }
    });

    test('the settled wheel sits on the slot after the overshoot too', () {
      final plan = ChanceSpinPlan.draw(seed: 31, slot: 2);
      final sim = ChanceSpinSim(plan)..start();
      while (!sim.settled) {
        sim.step(1 / 60);
      }
      expect(chanceSlotUnderPointer(sim.angle), 2);
      expect(sim.angle, closeTo(plan.total, 0.02));
    });
  });

  group('shared vectors', () {
    test('the plans draw the recorded turns, stop and total', () {
      for (final raw in _vectors['plans'] as List) {
        final v = raw as Map<String, dynamic>;
        final plan = ChanceSpinPlan.draw(
          seed: v['seed'] as int,
          slot: v['slot'] as int,
        );
        expect(plan.turns, v['turns'], reason: 'seed ${v['seed']}');
        expect(plan.within, _near(v['within'] as num));
        expect(plan.total, _near(v['total'] as num));
        expect(chanceSlotUnderPointer(plan.total), v['slotUnderPointer']);
      }
    });

    test('the stepped sim reproduces every sample', () {
      final first = (_vectors['plans'] as List).first as Map<String, dynamic>;
      final plan = ChanceSpinPlan.draw(
        seed: first['seed'] as int,
        slot: first['slot'] as int,
      );
      final dt = _vectors['dt'] as double;
      final sim = ChanceSpinSim(plan)..start();
      var steps = 0;
      var landedStep = -1;
      var lastClickStep = 0;
      var clicks = 0;
      for (final raw in _vectors['samples'] as List) {
        final s = raw as Map<String, dynamic>;
        while (steps < (s['steps'] as int)) {
          if (sim.step(dt)) landedStep = steps;
          steps++;
          if (sim.clicks != clicks) {
            clicks = sim.clicks;
            lastClickStep = steps;
          }
        }
        expect(sim.angle, _near(s['angle'] as num), reason: 't=${s['time']}');
        expect(sim.omega, _near(s['omega'] as num), reason: 't=${s['time']}');
        expect(
          sim.pointer,
          _near(s['pointer'] as num),
          reason: 't=${s['time']}',
        );
        expect(sim.clicks, s['clicks'], reason: 't=${s['time']}');
        expect(sim.phase.name, s['phase'], reason: 't=${s['time']}');
      }
      expect(landedStep, _vectors['landedStep']);
      expect(lastClickStep, _vectors['lastClickStep']);
      expect(chanceSlotUnderPointer(sim.angle), _vectors['finalSlot']);
    });
  });

  group('the shape of the spin', () {
    test('the last peg passes late, in the final second', () {
      final dt = _vectors['dt'] as double;
      final lastClick = (_vectors['lastClickStep'] as int) * dt;
      expect(lastClick, greaterThan(kChanceSpinSeconds - 1.0));
      expect(lastClick, lessThan(kChanceSpinSeconds));
    });

    test('phases run idle, windup, fast, slowing, near miss, landing, '
        'reveal, and the landing fires exactly once', () {
      final sim = ChanceSpinSim(ChanceSpinPlan.draw(seed: 7, slot: 4));
      expect(sim.phase, ChanceSpinPhase.idle);
      expect(sim.step(1 / 60), isFalse);
      sim.start();
      final seen = <ChanceSpinPhase>[];
      var landings = 0;
      for (var i = 0; i < 6 * 60; i++) {
        if (sim.step(1 / 60)) landings++;
        if (seen.isEmpty || seen.last != sim.phase) seen.add(sim.phase);
      }
      expect(landings, 1);
      expect(seen.first, ChanceSpinPhase.windup);
      expect(seen, contains(ChanceSpinPhase.fast));
      expect(seen, contains(ChanceSpinPhase.slowing));
      expect(seen, contains(ChanceSpinPhase.landing));
      expect(seen.last, ChanceSpinPhase.reveal);
      expect(
        seen.indexOf(ChanceSpinPhase.landing),
        greaterThan(seen.indexOf(ChanceSpinPhase.slowing)),
      );
      expect(sim.clicks, greaterThan(kChanceWheelSlots * 4));
    });

    test('the pointer kicks back on a peg and the spring brings it home', () {
      final sim = ChanceSpinSim(ChanceSpinPlan.draw(seed: 7, slot: 4))..start();
      var minPointer = 0.0;
      while (!sim.landed) {
        sim.step(1 / 120);
        if (sim.pointer < minPointer) minPointer = sim.pointer;
      }
      expect(minPointer, lessThan(-0.5));
      expect(minPointer, greaterThanOrEqualTo(-1.1));
      while (!sim.settled) {
        sim.step(1 / 120);
      }
      expect(sim.pointer.abs(), lessThan(0.02));
    });

    test('reduce motion jumps to the settled stop with nothing swung', () {
      final plan = ChanceSpinPlan.draw(seed: 99, slot: 6);
      final sim = ChanceSpinSim(plan)..jumpToEnd();
      expect(sim.landed, isTrue);
      expect(sim.settled, isTrue);
      expect(sim.phase, ChanceSpinPhase.reveal);
      expect(sim.angle, plan.total);
      expect(sim.pointer, 0);
      expect(sim.omega, 0);
      expect(sim.clicks, 0);
      expect(chanceSlotUnderPointer(sim.angle), 6);
      // A later step never re-fires the landing.
      expect(sim.step(1 / 60), isFalse);
    });
  });
}
