// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Table-driven pin of the per-slot clock resolver ladder. Each row
// hits exactly one rung through backfill + slotClockAfter — the same
// door open, swipe and fork use.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';

const _d1_0900 = '2026-06-28T09:00:00.000Z';
const _d1_1600 = '2026-06-28T16:00:00.000Z';
const _d1_1830 = '2026-06-28T18:30:00.000Z';
const _d2_0800 = '2026-06-29T08:00:00.000Z';
const _d3_2340 = '2026-06-30T23:40:00.000Z';

final _june28 = DateTime.utc(2026, 6, 28);
final _sept1 = DateTime.utc(2026, 9, 1);
final _live = DateTime.utc(2026, 9, 25, 22, 30);
final _at0930 = DateTime.utc(2026, 6, 28, 9, 30);
final _at1600 = DateTime.utc(2026, 6, 28, 16, 0);
final _at1830 = DateTime.utc(2026, 6, 28, 18, 30);
final _day5Live = DateTime.utc(2026, 9, 5, 22, 30);
final _day5Morning = DateTime.utc(2026, 9, 5, 9, 0);
final _day5Evening = DateTime.utc(2026, 7, 2, 18, 30);
final _day3Before = DateTime.utc(2026, 6, 30, 23, 40);

ChatMessage _bot(String text, Map<String, dynamic> meta) {
  return ChatMessage(
    text: text,
    sender: 'Nia',
    isUser: false,
    metadata: Map<String, dynamic>.from(meta),
    swipeIndex: 0,
    swipes: [text],
  );
}

Map<String, dynamic> _pair(String iso) => {
  'story_clock_before': iso,
  'story_clock_after': iso,
};

Map<String, dynamic> _snap(String iso, {String? before, String? chip}) {
  final m = <String, dynamic>{
    'realism_state': {'storyClock': iso},
  };
  if (before != null) m['story_clock_before'] = before;
  if (chip != null) m['time_passed'] = chip;
  return m;
}

class _Row {
  _Row({
    required this.name,
    required this.build,
    required this.read,
    required this.expected,
    DateTime? live,
    DateTime? start,
  }) : live = live ?? _live,
       start = start ?? _june28;

  final String name;
  final List<ChatMessage> Function() build;
  final int read;
  final DateTime? expected;
  final DateTime live;
  final DateTime start;
}

final _rows = <_Row>[
  _Row(
    name: 'rung 1 own after',
    build: () => [
      _bot('kept.', {
        ..._pair(_d1_1830),
        ..._snap(_d1_1600, chip: '30 min'),
        'story_day': 9,
      }),
    ],
    read: 0,
    expected: _at1830,
  ),
  _Row(
    name: 'rung 2 before plus chip minutes',
    build: () => [
      _bot('chip.', {'story_clock_before': _d1_0900, 'time_passed': '30 min'}),
    ],
    read: 0,
    expected: _at0930,
  ),
  _Row(
    name: 'rung 2 outranks rung 3',
    build: () => [
      _bot(
        'chip-over-snap.',
        _snap(_d1_1600, before: _d1_0900, chip: '30 min'),
      ),
    ],
    read: 0,
    expected: _at0930,
  ),
  _Row(
    name: 'rung 3 frozen skip -> own before',
    build: () => [
      _bot('greet.', _snap(_d1_0900)),
      _bot('later.', _snap(_d1_0900, before: _d1_1600)),
    ],
    read: 1,
    expected: _at1600,
  ),
  _Row(
    name: 'rung 3 snap later than before wins',
    build: () => [
      _bot('greet.', _snap(_d1_0900)),
      _bot('v1.4.', _snap(_d1_1600, before: _d1_0900)),
    ],
    read: 1,
    expected: _at1600,
  ),
  _Row(
    name: 'rung 4 neighbour TOD',
    build: () => [
      _bot('stamp.', _pair(_d1_1830)),
      _bot('day five.', {'story_day': 5}),
    ],
    read: 1,
    expected: _day5Evening,
  ),
  _Row(
    name: 'rung 4 tip no neighbour -> live TOD',
    build: () => [
      _bot('day five.', {'story_day': 5}),
    ],
    read: 0,
    expected: _day5Live,
    start: _sept1,
  ),
  _Row(
    name: 'rung 4 history no neighbour -> 09:00',
    build: () => [
      _bot('day five.', {'story_day': 5}),
      _bot('empty tip.', {}),
    ],
    read: 0,
    expected: _day5Morning,
    start: _sept1,
  ),
  _Row(
    name: 'rung 5 own before',
    build: () => [
      _bot('before only.', {'story_clock_before': _d1_1600}),
    ],
    read: 0,
    expected: _at1600,
  ),
  _Row(
    name: 'rung 6 tip live',
    build: () => [_bot('empty tip.', {})],
    read: 0,
    expected: _live,
  ),
  _Row(
    name: 'rung 6 tip live above neighbour',
    build: () => [_bot('stamp.', _pair(_d1_0900)), _bot('empty tip.', {})],
    read: 1,
    expected: _live,
  ),
  _Row(
    name: 'rung 7 history neighbour',
    build: () => [_bot('empty history.', {}), _bot('stamp.', _pair(_d1_1600))],
    read: 0,
    expected: _at1600,
  ),
  _Row(
    name: 'rung 8 history nothing -> null',
    build: () => [_bot('empty history.', {}), _bot('empty tip.', {})],
    read: 0,
    expected: null,
  ),
  _Row(
    name: 'clamp neighbour TOD before own before',
    build: () => [
      _bot('early neighbour.', _pair(_d2_0800)),
      _bot('day three.', {'story_day': 3, 'story_clock_before': _d3_2340}),
    ],
    read: 1,
    expected: _day3Before,
  ),
  _Row(
    name: 'clamp rung 1 own after earlier than own before -> own before',
    build: () => [
      _bot('rewound.', {
        'story_clock_before': _d1_1600,
        'story_clock_after': _d1_0900,
      }),
    ],
    read: 0,
    expected: _at1600,
  ),
];

void main() {
  for (final row in _rows) {
    test(row.name, () {
      final messages = row.build();
      backfillSlotClocks(messages, liveClock: row.live, startDate: row.start);
      expect(
        slotClockAfter(messages[row.read].activeMetadata),
        row.expected,
        reason: row.name,
      );
    });
  }
}
