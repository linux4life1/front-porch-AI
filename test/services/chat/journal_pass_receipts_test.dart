// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pass-authored Journal/Growth adds with no msgs= still need a receipt so
// regen/swipe/delete can retire them. Manual plants keep an empty list.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/journal_ops.dart';

void main() {
  test('empty cites fall back to the last window position', () {
    expect(passAuthoredReceipts(const [], windowStart: 10, windowLength: 4), [
      13,
    ]);
  });

  test('model-supplied cites are kept', () {
    expect(
      passAuthoredReceipts(const [10, 12], windowStart: 10, windowLength: 4),
      [10, 12],
    );
  });

  test('empty window stays empty (manual plant)', () {
    expect(
      passAuthoredReceipts(const [], windowStart: 0, windowLength: 0),
      isEmpty,
    );
  });
}
