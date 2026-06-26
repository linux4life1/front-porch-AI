// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/web/auth/rate_limiter.dart';

void main() {
  group('RateLimiter', () {
    test('locks out after 5 consecutive failures', () {
      var now = DateTime(2026, 1, 1, 12);
      final rl = RateLimiter(now: () => now);
      expect(rl.lockoutFor('bob'), isNull);
      for (var i = 0; i < 5; i++) {
        rl.recordFailure('bob', '1.2.3.4');
      }
      expect(rl.lockoutFor('bob'), isNotNull);
    });

    test('lockout expires after the backoff window passes', () {
      var now = DateTime(2026, 1, 1, 12);
      final rl = RateLimiter(now: () => now);
      for (var i = 0; i < 5; i++) {
        rl.recordFailure('bob', null);
      }
      expect(rl.lockoutFor('bob'), isNotNull);
      now = now.add(const Duration(minutes: 30));
      expect(rl.lockoutFor('bob'), isNull);
    });

    test('a successful login clears the failure streak', () {
      var now = DateTime(2026, 1, 1, 12);
      final rl = RateLimiter(now: () => now);
      for (var i = 0; i < 5; i++) {
        rl.recordFailure('bob', null);
      }
      rl.recordSuccess('bob');
      expect(rl.lockoutFor('bob'), isNull);
    });

    test('per-IP sliding window blocks excessive attempts', () {
      var now = DateTime(2026, 1, 1, 12);
      final rl = RateLimiter(now: () => now);
      expect(rl.ipAllowed('9.9.9.9'), isTrue);
      for (var i = 0; i < 50; i++) {
        rl.recordFailure('u$i', '9.9.9.9');
      }
      expect(rl.ipAllowed('9.9.9.9'), isFalse);
      now = now.add(const Duration(minutes: 6));
      expect(rl.ipAllowed('9.9.9.9'), isTrue);
    });
  });
}
