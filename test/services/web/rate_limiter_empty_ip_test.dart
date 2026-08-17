// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Empty / whitespace / null IP must not skip the login sliding-window cap.
// Fail closed: those values share one bucket and are recorded.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/web/auth/rate_limiter.dart';

void main() {
  test('empty IP is not unlimited — the sliding-window cap still applies', () {
    var now = DateTime(2026, 1, 1, 12);
    final rl = RateLimiter(now: () => now);
    expect(rl.ipAllowed(''), isTrue);
    for (var i = 0; i < 50; i++) {
      rl.recordFailure('u$i', '');
    }
    expect(rl.ipAllowed(''), isFalse);
    expect(rl.ipAllowed(null), isFalse);
    expect(rl.ipAllowed('   '), isFalse);
  });

  test('null and whitespace share the empty-IP bucket', () {
    var now = DateTime(2026, 1, 1, 12);
    final rl = RateLimiter(now: () => now);
    for (var i = 0; i < 50; i++) {
      rl.recordFailure('u$i', null);
    }
    expect(rl.ipAllowed(null), isFalse);
    expect(rl.ipAllowed(''), isFalse);
    expect(rl.ipAllowed('9.9.9.9'), isTrue);
  });
}
