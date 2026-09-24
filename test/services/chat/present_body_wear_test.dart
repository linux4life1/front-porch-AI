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

  test('tail-delete refunds co-present wear from the pre-restore bars', () {
    // Bea finished her turn at 78. Ana's beat wore her to 76. Deleting Ana
    // restores Bea's snapshot to 78 first. The refund has to start from 76.
    final refunded = refundCoPresentWear(
      captured: {
        'bea': {'hunger': 76},
      },
      preWear: {
        'bea': {'hunger': 78},
      },
      worn: {
        'bea': {'hunger': 76},
      },
      skipId: 'ana',
    );
    expect(
      refunded['bea']!['hunger'],
      78,
      reason: 'refunding the restored 78 would land on 80',
    );
  });
}
