// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// C: the clamp is global and applied last. A legacy stored inverted
// pair still resolves to after >= own before, even when tagged as a
// writer pair (clock_from_writer / time_passed / time_nudged /
// time_skip_to). The 05700072 writer-pair skip must go.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show resolveSlotAfter, slotClockBefore;

const _beforeIso = '2026-06-28T16:00:00.000Z';
const _afterIso = '2026-06-28T09:00:00.000Z';
final _before = DateTime.utc(2026, 6, 28, 16, 0);
final _live = DateTime.utc(2026, 9, 25, 22, 30);

Map<String, dynamic> _inverted([Map<String, dynamic>? extra]) => {
  'story_clock_before': _beforeIso,
  'story_clock_after': _afterIso,
  ...?extra,
};

void main() {
  for (final tag in [
    {'clock_from_writer': true},
    {'time_passed': '30 min'},
    {'time_nudged': true},
    {'time_skip_to': 'Sun, Jun 28 · 9:00 AM'},
  ]) {
    final label = tag.keys.single;
    test('legacy inverted pair tagged $label still clamps to own before', () {
      final slot = _inverted(tag);
      final hit = resolveSlotAfter(slot, isTip: true, liveClock: _live);
      expect(slotClockBefore(slot), _before);
      expect(
        hit,
        _before,
        reason:
            'clamp is last and global; writer tag $label must not skip '
            'it. expected after >= own before ($_before), not the '
            'stored inverted after 09:00',
      );
      expect(hit!.isBefore(_before), isFalse);
    });
  }

  test('legacy inverted pair with every writer tag still clamps', () {
    final slot = _inverted({
      'clock_from_writer': true,
      'time_passed': '30 min',
      'time_nudged': true,
      'time_skip_to': 'Sun, Jun 28 · 9:00 AM',
    });
    final hit = resolveSlotAfter(slot, isTip: true, liveClock: _live);
    expect(
      hit,
      _before,
      reason:
          'each of clock_from_writer, time_passed, time_nudged and '
          'time_skip_to still resolves to after >= own before',
    );
  });
}
