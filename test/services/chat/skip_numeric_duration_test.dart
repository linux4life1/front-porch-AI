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

  group('day-plus spans (2026-10-13)', () {
    test('"two weeks later" is fourteen days, not one week', () {
      expect(
        StoryClock.resolveSkipTarget(nine, '*two weeks later*'),
        DateTime.utc(2026, 7, 16, 9, 0),
      );
    });

    test('"a few days later" skips with no OOC marker', () {
      expect(hasSkipPhrase('a few days later we meet again'), isTrue);
      expect(
        StoryClock.resolveSkipTarget(nine, 'a few days later we meet again'),
        DateTime.utc(2026, 7, 5, 9, 0),
      );
    });

    test('months and years are calendar months, same time of day', () {
      expect(
        StoryClock.resolveSkipTarget(nine, '3 months later'),
        DateTime.utc(2026, 10, 2, 9, 0),
      );
      expect(
        StoryClock.resolveSkipTarget(nine, 'a year later'),
        DateTime.utc(2027, 7, 2, 9, 0),
      );
      expect(
        StoryClock.resolveSkipTarget(
          DateTime.utc(2026, 1, 31, 9, 0),
          'a month later',
        ),
        DateTime.utc(2026, 2, 28, 9, 0),
      );
    });

    test('"skip ahead two weeks" asks for the same jump', () {
      expect(hasSkipPhrase('(ooc: skip ahead two weeks)'), isTrue);
      expect(
        StoryClock.resolveSkipTarget(nine, '(ooc: skip ahead two weeks)'),
        DateTime.utc(2026, 7, 16, 9, 0),
      );
    });

    test('a span that is not narrated as passing is not a skip', () {
      expect(hasSkipPhrase('i was away for two weeks'), isFalse);
      expect(hasSkipPhrase('we met three years ago'), isFalse);
    });

    test('backstory and a skipped class are not skips', () {
      for (final line in [
        '*three years had passed since the accident*',
        '*a few days have passed since our date*',
        'two years passed since we last spoke',
        '*i skip a day of school to see you*',
        'i jump two days ahead in my reading',
      ]) {
        expect(hasSkipPhrase(line), isFalse, reason: line);
      }
    });

    test('a skip a character says out loud is not a skip', () async {
      final t = skipClock();
      await t.detectOocTimeSkip(
        '"Two weeks later and you still owe me," she says.',
      );
      expect(t.clock, DateTime.utc(2026, 7, 2, 9, 0));
    });

    test('detectOocTimeSkip reports the minutes it skipped', () async {
      final t = skipClock();
      expect(await t.detectOocTimeSkip('Two weeks later.'), 14 * 24 * 60);
      expect(await t.detectOocTimeSkip('I smile at her.'), 0);
    });
  });
}
