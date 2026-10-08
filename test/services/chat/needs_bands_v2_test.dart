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

// Needs v2 bands: nothing above 55; mild 41-55, moderate 26-40, strong
// 11-25, crisis 1-10, empty 0. Every need injects from mild, three per
// turn, worst first. The wording stays pronoun-free and five lines deep.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/needs_simulation.dart';

NeedsSimulation _sim({bool enjoysLow = false}) => NeedsSimulation(
  onNotify: () {},
  onSaveChat: () async {},
  getTimeOfDay: () => 'morning',
  getRealismEnabled: () => true,
  getObserverMode: () => false,
  getCurrentSpeakerIdForRealism: () => 'c',
  getIsGroupNonObserverMode: () => false,
  getGroupNeeds: (_) => const {},
  setGroupNeeds: (_, _) {},
  getEnjoysLowHygiene: () => enjoysLow,
  getNeedsSimEnabled: () => true,
);

Map<String, int> _all(int v) => {
  for (final k in NeedsSimulation.needKeys) k: v,
};

void main() {
  test('the bands are 0 / 10 / 25 / 40 / 55 and the colours follow them', () {
    expect(NeedsSimulation.needStepUpperBounds, [0, 10, 25, 40, 55]);
    expect(NeedsSimulation.needUrgentThreshold, 40);
    expect(NeedsSimulation.needCriticalThreshold, 25);
    final sim = _sim();
    expect(sim.getNeedStep('hunger', 0), 0);
    expect(sim.getNeedStep('hunger', 1), 1);
    expect(sim.getNeedStep('hunger', 10), 1);
    expect(sim.getNeedStep('hunger', 11), 2);
    expect(sim.getNeedStep('hunger', 25), 2);
    expect(sim.getNeedStep('hunger', 26), 3);
    expect(sim.getNeedStep('hunger', 40), 3);
    expect(sim.getNeedStep('hunger', 41), 4);
    expect(sim.getNeedStep('hunger', 55), 4);
    expect(sim.getNeedStep('hunger', 56), 5);
  });

  test('56 injects nothing; 55 injects the mild line, for every need', () {
    final sim = _sim();
    expect(sim.getLowNeedsForInjection(_all(56)), isEmpty);
    final mild = sim.getLowNeedsForInjection({..._all(90), 'bladder': 55});
    expect(mild.map((e) => e.key), ['bladder']);
    expect(mild.single.effectiveStep, 4);
    for (final need in NeedsSimulation.needKeys) {
      final one = sim.getLowNeedsForInjection({..._all(90), need: 50});
      expect(one.map((e) => e.key), [need], reason: '$need injects at 50');
    }
  });

  test('three speak per turn, worst first', () {
    final sim = _sim();
    final picked = sim.getLowNeedsForInjection({
      ..._all(90),
      'hunger': 50,
      'bladder': 20,
      'energy': 35,
      'fun': 45,
    });
    expect(picked.map((e) => e.key), ['bladder', 'energy', 'fun']);
  });

  test('every need has five lines, worst first, with no pronouns', () {
    final pronoun = RegExp(r'\b(she|he|they|her|his|their|them)\b');
    for (final need in NeedsSimulation.needKeys) {
      final lines = NeedsSimulation.needSteppedText[need]!;
      expect(lines, hasLength(5), reason: need);
      for (final line in lines) {
        expect(pronoun.hasMatch(line.toLowerCase()), isFalse, reason: line);
      }
      expect(
        lines[4],
        contains(
          RegExp(
            r'nothing pressing|nothing more|not bothered|nothing that changes|easily ignored',
          ),
        ),
      );
    }
    expect(NeedsSimulation.hygieneSteppedTextWhenEnjoysLow, hasLength(5));
    expect(
      NeedsSimulation.needSteppedText['bladder']![3],
      contains('a bathroom'),
    );
    expect(
      NeedsSimulation.needSteppedText['bladder']![1],
      contains('a bathroom'),
    );
  });

  test('enjoys-low hygiene walks the same bands from the other end', () {
    final sim = _sim(enjoysLow: true);
    expect(sim.getInjectionEffectiveStep('hygiene', 100), 0);
    expect(sim.getInjectionEffectiveStep('hygiene', 90), 1);
    expect(sim.getInjectionEffectiveStep('hygiene', 60), 3);
    expect(sim.getInjectionEffectiveStep('hygiene', 45), 4);
    expect(sim.getInjectionEffectiveStep('hygiene', 44), 5);
  });

  test('the carried fraction rides the snapshot', () {
    final sim = _sim();
    sim.initializeFresh();
    sim.applyTimeWear(
      points: const {'hunger': 2},
      carry: const {'hunger': 0.4},
      offScreen: false,
    );
    expect(sim.vector['hunger'], 73);
    expect(sim.wearCarry['hunger'], 0.4);
    sim.restoreFromSnapshot({
      'vector': sim.vector,
      'wear_carry': {'hunger': 0.9},
    });
    expect(sim.wearCarry['hunger'], 0.9);
    sim.restoreFromSnapshot({'vector': sim.vector});
    expect(sim.wearCarry, isEmpty);
  });
}
