// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Direct backfillSlotClocks rules: a null swipe slot stays null, the
// greeting clock comes only from index 0, a guessed after yields to a
// surviving snap, stored befores survive, non-tip afters stay off the
// live clock, and an empty slot takes the earlier real stamp.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

ChatMessage _bot(
  String text,
  Map<String, dynamic>? meta, {
  List<String>? swipes,
  List<Map<String, dynamic>?>? swipeMeta,
  int idx = 0,
}) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: meta == null ? null : Map<String, dynamic>.from(meta),
    swipes: swipes ?? [text],
    swipeMetadata: swipeMeta,
    swipeIndex: idx,
  );
}

void main() {
  test('K-2: null swipe slot above 0 stays null and keeps metadata flags', () {
    final msg = _bot(
      'A',
      {
        'realism_state': {'trustLevel': 45, 'affectionScore': 10},
        'is_dream': true,
        'time_passed': '30 min',
      },
      swipes: ['A', 'B'],
      swipeMeta: [null, null],
      idx: 1,
    );
    backfillSlotClocks(
      [msg],
      liveClock: DateTime.utc(2026, 6, 30, 16, 0),
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(msg.swipeMetadata[1], isNull, reason: 'must not shadow metadata');
    expect(msg.activeMetadata?['realism_state'], isA<Map>());
    expect((msg.activeMetadata?['realism_state'] as Map)['trustLevel'], 45);
    expect(msg.activeMetadata?['is_dream'], isTrue);
    expect(msg.metadata?['story_clock_after'], isNotNull);
  });

  test('nearestReal prefers an earlier stamp over a closer later one', () {
    final earlier = _bot('nine-thirty', {
      'story_clock_before': '2026-06-28T09:30:00.000Z',
      'story_clock_after': '2026-06-28T09:30:00.000Z',
    });
    final mid = _bot('unstamped', {});
    final later = _bot('evening', {
      'story_clock_before': '2026-06-28T18:00:00.000Z',
      'story_clock_after': '2026-06-28T18:00:00.000Z',
    });
    backfillSlotClocks(
      [
        earlier,
        ChatMessage(text: 'ok', sender: 'You', isUser: true),
        mid,
        later,
      ],
      liveClock: DateTime.utc(2026, 6, 28, 18, 0),
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(
      slotClockAfter(mid.metadata),
      DateTime.utc(2026, 6, 28, 9, 30),
      reason: 'pos 2 must take earlier 09:30, not closer later 18:00',
    );
  });

  test('B1: greetingClock comes only from index 0, not a later snap', () {
    final greeting = _bot('Hi.', {});
    final reply = _bot('Later.', {
      'story_clock_before': '2026-06-28T09:00:00.000Z',
      'realism_state': {
        'storyClock': '2026-06-28T09:30:00.000Z',
        'storyStartDate': '2026-06-28',
      },
    });
    final tip = _bot('Night.', {
      'story_clock_before': '2026-07-01T18:00:00.000Z',
      'story_clock_after': '2026-07-01T18:00:00.000Z',
      'realism_state': {
        'storyClock': '2026-07-01T18:00:00.000Z',
        'storyStartDate': '2026-06-28',
      },
    });
    backfillSlotClocks(
      [
        greeting,
        ChatMessage(text: 'ok', sender: 'You', isUser: true),
        reply,
        tip,
      ],
      liveClock: DateTime.utc(2026, 7, 1, 18, 0),
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(
      slotClockAfter(reply.metadata),
      DateTime.utc(2026, 6, 28, 9, 30),
      reason: 'v1.4 reply snap is live, not a frozen greeting',
    );
  });

  test('B1 repair: guessed neighbour after yields to the surviving snap', () {
    final reply = _bot('Later.', {
      'story_clock_before': '2026-06-28T09:00:00.000Z',
      'story_clock_after': '2026-07-01T18:00:00.000Z',
      'realism_state': {
        'storyClock': '2026-06-28T09:30:00.000Z',
        'storyStartDate': '2026-06-28',
      },
    });
    backfillSlotClocks(
      [_bot('Hi.', {}), reply],
      liveClock: DateTime.utc(2026, 7, 1, 18, 0),
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(slotClockAfter(reply.metadata), DateTime.utc(2026, 6, 28, 9, 30));
    expect(slotClockBefore(reply.metadata), DateTime.utc(2026, 6, 28, 9, 0));
  });

  test('B2: existing befores are never overwritten by dayClock', () {
    final d1 = _bot('one', {
      'story_clock_before': '2026-06-28T09:00:00.000Z',
      'story_day': 1,
    });
    final d2 = _bot('two', {
      'story_clock_before': '2026-06-29T08:00:00.000Z',
      'story_day': 2,
    });
    final d3 = _bot('three', {
      'story_clock_before': '2026-06-30T23:40:00.000Z',
      'story_day': 3,
    });
    final live = DateTime.utc(2026, 7, 1, 0, 10);
    backfillSlotClocks(
      [d1, d2, d3],
      liveClock: live,
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(slotClockBefore(d1.metadata), DateTime.utc(2026, 6, 28, 9, 0));
    expect(slotClockBefore(d2.metadata), DateTime.utc(2026, 6, 29, 8, 0));
    expect(slotClockBefore(d3.metadata), DateTime.utc(2026, 6, 30, 23, 40));
    // d3 is the tip but it stores a before and story_day 3 — not
    // "nothing stored". After is that slot's own clock (dayCount>1),
    // never the session live clock. TOD on a dayCount clock is
    // unresolved; pin the calendar day and the no-rewind bound.
    final d3After = slotClockAfter(d3.metadata);
    expect(d3After, isNotNull);
    expect(
      d3After,
      isNot(live),
      reason: 'history/tip with stored day 3 must not take the live clock',
    );
    expect(d3After!.year, 2026);
    expect(d3After.month, 6);
    expect(d3After.day, 30, reason: 'Day 3 of a 2026-06-28 start is 06-30');
    expect(
      d3After.isBefore(slotClockBefore(d3.metadata)!),
      isFalse,
      reason: 'after must not rewind behind this slot\'s own before',
    );
    expect(
      slotClockAfter(d1.metadata),
      isNot(live),
      reason: 'non-tip after must be that reply\'s own clock, not the live tip',
    );
    expect(
      slotClockAfter(d2.metadata),
      isNot(live),
      reason: 'non-tip after must be that reply\'s own clock, not the live tip',
    );
  });

  test('B2: unstamped rows keep non-tip after off the live tip clock', () {
    final d1 = _bot('one', {'story_day': 1});
    final d2 = _bot('two', {'story_day': 2});
    final d3 = _bot('three', {'story_day': 3});
    final live = DateTime.utc(2026, 7, 1, 0, 10);
    backfillSlotClocks(
      [d1, d2, d3],
      liveClock: live,
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(slotClockAfter(d3.metadata), isNotNull);
    expect(
      slotClockAfter(d1.metadata),
      isNot(live),
      reason: 'backfill must not paint every older slot with the tip clock',
    );
    expect(slotClockAfter(d2.metadata), isNot(live));
  });
}
