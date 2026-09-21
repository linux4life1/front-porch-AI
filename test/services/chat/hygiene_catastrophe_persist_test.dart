// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Hygiene-at-0 is acknowledged once. That ack used to live only in RAM, so a
// reload of a filthy character re-injected "they can smell themselves".

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/needs_persist.dart';

import 'needs_simulation_test.dart' show createTestSim;

Map<String, int> get _bottomHygiene => {
  'hunger': 60,
  'bladder': 60,
  'energy': 60,
  'social': 60,
  'fun': 60,
  'hygiene': 0,
  'comfort': 60,
};

void main() {
  test('hygiene catastrophe ack survives snapshot restore', () {
    final live = createTestSim();
    live.initializeFresh();
    live.restoreFromSnapshot({'vector': _bottomHygiene});
    live.applyCatastropheIfNeeded();
    expect(live.pendingCatastrophe, contains('smell themselves'));
    live.consumePendingCatastrophe();

    final blob = encodeNeedsPersist(live);
    final reloaded = createTestSim();
    reloaded.initializeFresh();
    applyNeedsPersist(reloaded, blob);
    reloaded.applyCatastropheIfNeeded();
    expect(reloaded.vector['hygiene'], 0);
    expect(
      reloaded.pendingCatastrophe,
      isNull,
      reason: 'reload must not replay the canon wash-now beat',
    );
  });

  test('legacy flat needs_vector still hydrates the meters', () {
    final sim = createTestSim();
    sim.initializeFresh();
    applyNeedsPersist(sim, _bottomHygiene);
    expect(sim.vector['hygiene'], 0);
    expect(sim.vector['hunger'], 60);
  });
}
