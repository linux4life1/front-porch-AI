// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// alignGreetingSeeds(..., 0) used to return const []. The character and
// group editors then _seeds.add(null) on Add — UnmodifiableListMixin.add.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';

void main() {
  test(
    'alignGreetingSeeds with no alts is growable so Add greeting can append',
    () {
      final seeds = alignGreetingSeeds(const [], 0);
      seeds.add(null);
      expect(seeds, [null]);
    },
  );
}
