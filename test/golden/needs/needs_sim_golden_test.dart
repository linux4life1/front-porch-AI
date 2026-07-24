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

// Golden snapshots for the deterministic Needs simulation mechanics that drive
// character behavior: step thresholds, urgency phrasing, per-turn decay, and
// delta clamping. Locks the tuning so any accidental change to the curves is
// caught. Reuses createTestSim from the existing needs_simulation_test.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';

import '../golden_harness.dart';
import '../../services/chat/needs_simulation_test.dart' show createTestSim;

void main() {
  test('need step thresholds across the full 0..100 range', () {
    final sim = createTestSim();
    final table = <String, int>{
      for (var v = 0; v <= 100; v += 5) '$v': sim.getNeedStep('hunger', v),
    };
    expectGoldenJson(table, group: 'needs', name: 'need_steps');
  });

  test('hygiene step inverts when the character enjoys low hygiene', () {
    final normal = createTestSim();
    final inverted = createTestSim(enjoysFn: () => true);
    final table = <String, dynamic>{
      for (var v = 0; v <= 100; v += 10)
        '$v': {
          'normal': normal.getInjectionEffectiveStep('hygiene', v),
          'enjoysLow': inverted.getInjectionEffectiveStep('hygiene', v),
        },
    };
    expectGoldenJson(table, group: 'needs', name: 'hygiene_inversion');
  });

  test('per-turn decay from fresh defaults is stable', () {
    final sim = createTestSim();
    sim.initializeFresh();
    final snapshots = <String, Map<String, int>>{
      'turn0': Map<String, int>.from(sim.vector),
    };
    for (var turn = 1; turn <= 5; turn++) {
      sim.tickDecay();
      snapshots['turn$turn'] = Map<String, int>.from(sim.vector);
    }
    expectGoldenJson(snapshots, group: 'needs', name: 'decay_curve');
  });

  test('applyNeedsDeltas clamps to 0..100', () {
    final sim = createTestSim();
    sim.initializeFreshWithDefaults({
      for (final k in NeedsSimulation.needKeys) k: 50,
    });
    sim.applyNeedsDeltas({
      'hunger': 999, // clamps to 100
      'energy': -999, // clamps to 0
      'social': 10,
      'fun': -10,
    });
    expectGoldenJson(Map<String, int>.from(sim.vector),
        group: 'needs', name: 'delta_clamp');
  });
}
