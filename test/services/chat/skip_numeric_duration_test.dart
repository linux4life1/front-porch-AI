// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "[6 hours passed]" fell through to the +1h default (the "hours pass"
// bucket did not match "passed"). Chip stamped 10:00; the strip barely
// moved. Six hours never happened.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  final nine = DateTime.utc(2026, 7, 2, 9, 0);

  test('[6 hours passed] is +6h, not the 3h "hours pass" bucket', () {
    expect(
      StoryClock.resolveSkipTarget(nine, '[6 hours passed]'),
      DateTime.utc(2026, 7, 2, 15, 0),
    );
  });

  test('6 hours later is +6h, not the +1h default', () {
    expect(
      StoryClock.resolveSkipTarget(nine, '6 hours later'),
      DateTime.utc(2026, 7, 2, 15, 0),
    );
  });

  test('named clocks still win over a stray digit', () {
    expect(
      StoryClock.resolveSkipTarget(nine, 'skip to 2pm'),
      DateTime.utc(2026, 7, 2, 14, 0),
    );
  });

  test('several hours without a number stays +3h', () {
    expect(
      StoryClock.resolveSkipTarget(nine, 'several hours pass'),
      DateTime.utc(2026, 7, 2, 12, 0),
    );
  });

  test('six hours passed is +6h too', () {
    expect(
      StoryClock.resolveSkipTarget(nine, 'six hours passed'),
      DateTime.utc(2026, 7, 2, 15, 0),
    );
  });

  TimeService skipClock() {
    final t = TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
      onPatchLastMessageRealismState: (_, _, _) {},
    );
    t.seedFromV2OrExt(
      dayCount: 3,
      timeOfDay: 'morning',
      storyStartDate: '2026-06-30',
    );
    return t;
  }

  test('detectOocTimeSkip honours [6 hours passed] with no OOC marker', () {
    final t = skipClock();
    t.detectOocTimeSkip('[6 hours passed]');
    expect(t.clock, DateTime.utc(2026, 7, 2, 15, 0));
  });

  test('a wait of 6 hours is not a skip', () {
    final t = skipClock();
    t.detectOocTimeSkip('I waited 6 hours for you');
    expect(
      t.clock,
      DateTime.utc(2026, 7, 2, 9, 0),
      reason:
          'mentioning a duration is not jumping it — same class as '
          '"next week" in quoted speech',
    );
  });
}
