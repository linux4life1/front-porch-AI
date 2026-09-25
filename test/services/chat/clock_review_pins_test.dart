// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// K-2 / B1 / B2 / greeting-repair pins for the one-path backfill.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';

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
    expect(slotClockAfter(d3.metadata), live);
  });
}
