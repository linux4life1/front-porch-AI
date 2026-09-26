// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';

void main() {
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
