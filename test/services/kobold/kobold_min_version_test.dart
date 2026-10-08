// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The one place the oldest supported KoboldCpp is decided. An engine before
// 1.112 stops at load on the config the app stages, so it is refused with a
// sentence instead of being started to fail; there is no older form of the
// config to write for it. (The launch itself refusing is pinned on a real
// start in old_engine_refused_test.dart.)

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  test('an engine before 1.112 is too old', () {
    for (final version in [
      '1.111.2',
      '1.111.0',
      '1.110',
      '1.104',
      '1.9',
      '0.99',
    ]) {
      expect(
        KoboldBinaryVersion.tooOldProblem(version),
        isNotNull,
        reason: version,
      );
    }
  });

  test('1.112 and everything after it is fine', () {
    for (final version in [
      '1.112',
      '1.112.0',
      '1.112.1',
      '1.117.1',
      '1.122.1',
      '2.0',
      'v1.113-rocm',
    ]) {
      expect(
        KoboldBinaryVersion.tooOldProblem(version),
        isNull,
        reason: version,
      );
    }
  });

  test('an engine whose version is not known is taken as current: the app '
      'downloads the engine itself', () {
    expect(KoboldBinaryVersion.tooOldProblem(null), isNull);
    expect(KoboldBinaryVersion.tooOldProblem(''), isNull);
    expect(KoboldBinaryVersion.tooOldProblem('not a version'), isNull);
  });

  test('the reason names the engine, and what to do about it', () {
    final problem = KoboldBinaryVersion.tooOldProblem('1.111.2')!;
    expect(problem, contains('1.111.2'));
    expect(problem, contains('1.112 or newer'));
  });
}
