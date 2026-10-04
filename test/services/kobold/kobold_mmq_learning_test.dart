// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Auto mode learns, per card and KoboldCpp version, whether MMQ is faster,
// from the speeds KoboldCpp prints after each reply: on first (its
// default), then off, then the faster is kept. The figures are the
// original author's GTX 1060 (on: 761.63 T/s reading, 9.90 writing; off:
// 988.62 and 20.04), as KoboldCpp prints them.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold_mmq_timing.dart';

import '../../golden/support/fakes_storage.dart';

String _line(int read, double readSeconds, int written, double writeSeconds) =>
    '[10:01:02] CtxLimit:${read + written}/16384, Init:0.01s, '
    'Processed:$read in ${readSeconds}s '
    '(${(read / readSeconds).toStringAsFixed(2)}T/s), '
    'Generated:$written/$written in ${writeSeconds}s '
    '(${(written / writeSeconds).toStringAsFixed(2)}T/s), '
    'Total:${readSeconds + writeSeconds}s';

// 32,668 tokens read in 42.892 s, 100 written in 10.104 s; and off.
final _on = _line(32668, 42.892, 100, 10.104);
final _off = _line(32668, 33.044, 100, 4.989);

void main() {
  test('a real KoboldCpp speed line is read; other lines are not', () {
    final s = parseKoboldSpeed(
      '[01:15:31] CtxLimit:2213/16384, Init:0.01s, Processed:2181 in 0.68s '
      '(3212.08T/s), Generated:32/32 in 0.38s (83.33T/s), Total:1.07s',
    )!;
    expect(s.read, 2181);
    expect(s.readSeconds, 0.68);
    expect(s.written, 32);
    expect(s.writeSeconds, 0.38);
    expect(
      parseKoboldSpeed('Processing Prompt [BLAS] (512 / 2181 tokens)'),
      isNull,
    );
  });

  test('replies too short to time do not count, nor a slow first one', () {
    final short = parseKoboldSpeed(_line(54, 38.75, 1, 0.07))!;
    final good = parseKoboldSpeed(_on)!;
    expect(koboldTurnSeconds([short, good, good]), isNull);
    // The disk-bound first read does not decide: the middle one is taken.
    final slow = parseKoboldSpeed(_line(32668, 300.0, 100, 10.104))!;
    expect(
      koboldTurnSeconds([slow, good, good]),
      koboldTurnSeconds([good, good, good]),
    );
  });

  test('auto mode times on, then off, then keeps the faster', () {
    final b = FakeStorageService().backendSettings;
    const card = 'NVIDIA GeForce GTX 1060 6GB';
    expect(b.mmqForLaunch(card, '1.122.1'), isTrue, reason: 'on first');
    for (var i = 0; i < 3; i++) {
      b.noteKoboldOutput('Generating (100 / 100 tokens)\n$_on\n');
    }
    expect(b.mmqFor(card, '1.122.1'), isNull, reason: 'off not timed yet');
    expect(b.mmqForLaunch(card, '1.122.1'), isFalse, reason: 'then off');
    for (var i = 0; i < 3; i++) {
      b.noteKoboldOutput(_off);
    }
    expect(b.mmqFor(card, '1.122.1'), isFalse, reason: 'off was faster');
    expect(b.mmqForLaunch(card, '1.122.1'), isFalse);
    // Learned: later replies change nothing.
    for (var i = 0; i < 9; i++) {
      b.noteKoboldOutput(_on);
    }
    expect(b.mmqFor(card, '1.122.1'), isFalse);
    // Another KoboldCpp version is learned again.
    expect(b.mmqForLaunch(card, '1.123.0'), isTrue);
  });

  test('while the editor times it, replies are not taken for auto mode', () {
    final b = FakeStorageService().backendSettings;
    expect(b.mmqForLaunch('GPU', '1'), isTrue);
    b.pauseMmqLearning();
    for (var i = 0; i < 6; i++) {
      b.noteKoboldOutput(_on);
    }
    expect(b.mmqForLaunch('GPU', '1'), isTrue, reason: 'nothing was counted');
  });
}
