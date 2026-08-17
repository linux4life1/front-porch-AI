// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// [today: …] parser: strip from visible reply; empty tag clears.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/today_line_tag.dart';

void main() {
  test('no tag keeps the reply and reports null line', () {
    const raw = 'She stacks the books and looks at the door.';
    final parsed = TodayLineTag.parse(raw);
    expect(parsed.visible, raw);
    expect(parsed.line, isNull);
  });

  test('tag is stripped and the sentence is held', () {
    const raw =
        'She stacks the books.\n[today: Finish the lighthouse log before the tide.]';
    final parsed = TodayLineTag.parse(raw);
    expect(parsed.visible, 'She stacks the books.');
    expect(parsed.line, 'Finish the lighthouse log before the tide.');
  });

  test('empty tag means abandon', () {
    final parsed = TodayLineTag.parse('Never mind.\n[today:  ]');
    expect(parsed.visible, 'Never mind.');
    expect(parsed.line, isEmpty);
  });

  test('last tag wins and whitespace collapses', () {
    final parsed = TodayLineTag.parse(
      'Hi [today: first   draft]\n[today:  Get Saturday done.  ]',
    );
    expect(parsed.visible.contains('[today'), isFalse);
    expect(parsed.line, 'Get Saturday done.');
  });
}
