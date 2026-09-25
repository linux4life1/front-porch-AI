// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure backfill pins for the one-path clock. Runtime live = tip.after.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';

const _start = '2026-06-28';
const _day1Nine = '2026-06-28T09:00:00.000Z';
const _day1Six = '2026-06-28T18:00:00.000Z';
const _day3 = '2026-06-30T16:00:00.000Z';
const _day12 = '2026-07-09T16:00:00.000Z';

ChatMessage _bot(String text, Map<String, dynamic> meta, {int idx = 0}) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: Map<String, dynamic>.from(meta),
    swipeIndex: idx,
    swipes: meta['swipes'] as List<String>? ?? [text],
    swipeMetadata: meta['swipeMeta'] as List<Map<String, dynamic>?>?,
  );
}

void main() {
  test('Carmen frozen evening snaps take live, never Day 1', () {
    final greeting = {
      'realism_state': {
        'storyClock': _day1Six,
        'storyStartDate': _start,
        'timeOfDay': 'evening',
        'dayCount': 1,
      },
    };
    final messages = [
      _bot('Evening.', greeting),
      ChatMessage(text: 'Hi.', sender: 'You', isUser: true),
      _bot('Still here.', greeting),
    ];
    final live = DateTime.utc(2026, 6, 30, 16, 0);
    backfillSlotClocks(messages, liveClock: live);
    expect(slotClockAfter(messages.last.activeMetadata), live);
    expect(slotClockAfter(messages.first.activeMetadata), live);
  });

  test('dayCount-only sibling swipe keeps live Day 12', () {
    final msg = ChatMessage(
      text: 'Later.',
      sender: 'Nia',
      isUser: false,
      swipeIndex: 1,
      swipes: const ['Day-count only', 'Stamped later'],
      metadata: {'story_clock_before': _day12, 'story_clock_after': _day12},
      swipeMetadata: [
        {
          'realism_state': {'dayCount': 1, 'timeOfDay': 'morning'},
        },
        {'story_clock_before': _day12, 'story_clock_after': _day12},
      ],
    );
    final live = DateTime.utc(2026, 7, 9, 16, 0);
    backfillSlotClocks([msg], liveClock: live);
    expect(slotClockAfter(msg.swipeMetadata[0]), live);
    expect(slotClockAfter(msg.swipeMetadata[1]), live);
  });

  test('dayCount-only chat with no storyClock uses that day', () {
    final msg = _bot('Day nine.', {
      'realism_state': {'dayCount': 9, 'timeOfDay': 'afternoon'},
    });
    final live = DateTime.utc(2026, 7, 9, 16, 0);
    final start = DateTime.utc(2026, 6, 28);
    backfillSlotClocks([msg], liveClock: live, startDate: start);
    expect(slotClockAfter(msg.metadata), DateTime.utc(2026, 7, 6, 14, 30));
  });

  test('dayCount-only nearest stamp is tip-backward, not first roster', () {
    final bea = ChatMessage(
      text: 'early bea',
      sender: 'Bea',
      isUser: false,
      metadata: {
        'realism_state': {'dayCount': 40, 'timeOfDay': 'evening'},
      },
    );
    final ana = ChatMessage(
      text: 'late ana',
      sender: 'Ana',
      isUser: false,
      metadata: {
        'realism_state': {'dayCount': 9, 'timeOfDay': 'afternoon'},
      },
    );
    final live = DateTime.utc(2026, 9, 25, 22, 30);
    final start = DateTime.utc(2026, 6, 28);
    backfillSlotClocks([bea, ana], liveClock: live, startDate: start);
    expect(slotClockAfter(ana.metadata), DateTime.utc(2026, 7, 6, 14, 30));
    expect(slotClockAfter(bea.metadata), DateTime.utc(2026, 7, 6, 14, 30));
  });

  test('no stamp floors to Day 1 only when asked', () {
    final msg = _bot('yo', {});
    final live = DateTime.utc(2026, 9, 25, 22, 30);
    final start = DateTime.utc(2026, 6, 18);
    backfillSlotClocks(
      [msg],
      liveClock: live,
      startDate: start,
      floorUnstampedToDay1: true,
    );
    expect(slotClockAfter(msg.metadata), DateTime.utc(2026, 6, 18, 22, 30));
    final lived = _bot('still here', {});
    backfillSlotClocks([lived], liveClock: live, startDate: start);
    expect(slotClockAfter(lived.metadata), live);
  });

  test('dayCount-derived pair refreshes when start moves', () {
    final msg = _bot('Day five.', {'story_day': 5});
    final live = DateTime.utc(2026, 9, 25, 22, 30);
    backfillSlotClocks(
      [msg],
      liveClock: live,
      startDate: DateTime.utc(2026, 9, 1),
    );
    expect(slotClockAfter(msg.metadata), DateTime.utc(2026, 9, 5, 22, 30));
    backfillSlotClocks(
      [msg],
      liveClock: live,
      startDate: DateTime.utc(2026, 6, 1),
    );
    expect(slotClockAfter(msg.metadata), DateTime.utc(2026, 6, 5, 22, 30));
  });

  test('v1.4 before + later snap fills after from the snap', () {
    final greeting = _bot('Morning.', {
      'realism_state': {'storyClock': _day1Nine, 'storyStartDate': _start},
    });
    final later = _bot('Hi.', {
      'story_clock_before': _day1Nine,
      'realism_state': {'storyClock': _day3, 'storyStartDate': _start},
    });
    backfillSlotClocks([
      greeting,
      later,
    ], liveClock: DateTime.utc(2026, 6, 30, 16, 0));
    expect(slotClockAfter(later.metadata), DateTime.utc(2026, 6, 30, 16, 0));
    expect(slotClockBefore(later.metadata), DateTime.utc(2026, 6, 28, 9, 0));
  });

  test('backfill is idempotent', () {
    final msg = _bot('Hi.', {
      'story_clock_before': _day3,
      'story_clock_after': _day3,
    });
    final first = backfillSlotClocks([
      msg,
    ], liveClock: DateTime.utc(2026, 6, 30, 16, 0));
    final second = backfillSlotClocks([
      msg,
    ], liveClock: DateTime.utc(2026, 6, 30, 16, 0));
    expect(first, isFalse);
    expect(second, isFalse);
    expect(slotClockAfter(msg.metadata), DateTime.utc(2026, 6, 30, 16, 0));
  });
}
