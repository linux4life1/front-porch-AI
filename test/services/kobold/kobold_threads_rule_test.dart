// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The thread count the preset editor suggests for KoboldCpp. A preset made
// on an 18-core Mac asked for 17 threads: every core but one, the twelve
// efficiency cores included, so reading a long prompt starved the app's
// window (the engine printed "Reported frame time is older than the last
// one" for every frame it missed) and ran the maths on the slow cores.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  test(
    'Apple Silicon gets its performance cores, never the efficiency ones',
    () {
      // An M5 Max: 6 "Super" + 12 "Performance" cores, no efficiency ones;
      // two fast cores stay with the app.
      expect(koboldThreadsFor(logical: 18, physical: 18, performance: 18), 16);
      // An M4 Pro: 10 performance + 4 efficiency.
      expect(koboldThreadsFor(logical: 14, physical: 14, performance: 10), 8);
      // A base chip with 4 performance + 6 efficiency keeps its four.
      expect(koboldThreadsFor(logical: 10, physical: 10, performance: 4), 4);
    },
  );

  test('without hyper-threading one core stays free for the app', () {
    expect(koboldThreadsFor(logical: 8, physical: 8), 7);
    expect(koboldThreadsFor(logical: 16, physical: 16), 15);
  });

  test('with hyper-threading the physical cores are used; the second threads '
      'keep the app responsive', () {
    expect(koboldThreadsFor(logical: 16, physical: 8), 8);
    expect(koboldThreadsFor(logical: 32, physical: 16), 16);
  });

  test('a small machine never goes below one thread', () {
    expect(koboldThreadsFor(logical: 1, physical: 1), 1);
    expect(koboldThreadsFor(logical: 2, physical: 2), 1);
    expect(koboldThreadsFor(logical: 2, physical: 2, performance: 0), 1);
  });
}
