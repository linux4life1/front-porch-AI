// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('preserved thinking keeps the tail, not a 60k draft', () {
    final draft =
        'HEAD_DRAFT${'x' * (kWaifuPreserveThinkMaxChars + 200)}TAIL_PLAN';
    final clipped = waifuClipPreservedThinking(draft);
    expect(clipped.length, lessThan(draft.length));
    expect(clipped, contains('TAIL_PLAN'));
    expect(clipped, startsWith('…'));
    expect(clipped, isNot(contains('HEAD_DRAFT')));
  });
}
