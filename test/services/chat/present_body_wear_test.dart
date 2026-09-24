// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';

void main() {
  test('regen wears a present member once: 80 stays 78, not 76', () {
    final before = {
      'speaker': {'hunger': 80},
      'other': {'hunger': 80},
    };
    const pace = BodyPace.normal;
    const on = ['hunger'];

    final worn = wearPresentBodies(
      before: before,
      minutes: 30,
      paceOf: (_) => pace,
      needsOn: (_) => on,
    );
    expect(worn['speaker']!['hunger'], 78);
    expect(worn['other']!['hunger'], 78);

    final replayed = replayPresentWear(
      before: before,
      worn: worn,
      minutes: 30,
      paceOf: (_) => pace,
      needsOn: (_) => on,
    );
    expect(
      replayed['other']!['hunger'],
      78,
      reason: 'wearing the already-worn bars again would leave them at 76',
    );
    expect(replayed['speaker']!['hunger'], 78);
  });
}
