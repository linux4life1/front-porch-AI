// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// History slots must not inherit the live tip clock. Each message uses
// its own stored dayCount / before, or a neighbour's real stamp.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';

ChatMessage _bot(String text, Map<String, dynamic> meta) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: Map<String, dynamic>.from(meta),
  );
}

void main() {
  test('history with a Day-2 before does not take the live Day-4 after', () {
    final greeting = _bot('Morning.', {
      'story_clock_before': '2026-06-28T09:00:00.000Z',
    });
    final mid = _bot('Later.', {
      'story_clock_before': '2026-06-29T16:00:00.000Z',
    });
    final tip = _bot('Night.', {});
    final live = DateTime.utc(2026, 7, 1, 0, 10);
    backfillSlotClocks(
      [greeting, mid, tip],
      liveClock: live,
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(
      slotClockAfter(greeting.metadata),
      DateTime.utc(2026, 6, 28, 9, 0),
      reason: 'history after comes from that slot, never live Day 4',
    );
    expect(
      slotClockAfter(mid.metadata),
      DateTime.utc(2026, 6, 29, 16, 0),
      reason: 'Day-2 before stays Day 2 after',
    );
    expect(
      slotClockAfter(tip.metadata),
      live,
      reason: 'only the visible tip after equals the live clock',
    );
  });

  test('each history slot uses its own stored dayCount, not the tip\'s', () {
    final day2 = _bot('Day two.', {
      'realism_state': {'dayCount': 2, 'timeOfDay': 'morning'},
    });
    final day3 = _bot('Day three.', {
      'realism_state': {'dayCount': 3, 'timeOfDay': 'evening'},
    });
    final tip = _bot('Day four.', {
      'realism_state': {'dayCount': 4, 'timeOfDay': 'night'},
    });
    final live = DateTime.utc(2026, 7, 1, 22, 30);
    backfillSlotClocks(
      [day2, day3, tip],
      liveClock: live,
      startDate: DateTime.utc(2026, 6, 28),
    );
    expect(slotClockAfter(day2.metadata), DateTime.utc(2026, 6, 29, 9, 0));
    expect(slotClockAfter(day3.metadata), DateTime.utc(2026, 6, 30, 18, 30));
    expect(
      slotClockAfter(tip.metadata),
      live,
      reason: 'tip after is the live clock',
    );
  });

  test('clock_backfill_done skips a second guess', () {
    final msg = _bot('Hi.', {});
    final live = DateTime.utc(2026, 6, 30, 16, 0);
    expect(backfillSlotClocks([msg], liveClock: live), isTrue);
    expect(msg.metadata?['clock_backfill_done'], isTrue);
    msg.metadata!.remove('story_clock_after');
    msg.metadata!.remove('story_clock_before');
    expect(
      backfillSlotClocks([msg], liveClock: DateTime.utc(2026, 6, 30, 18, 0)),
      isFalse,
      reason: 'marked chat is not guessed again',
    );
    expect(slotClockAfter(msg.metadata), isNull);
  });
}
