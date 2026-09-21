// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Continue must not inherit a cancelled regen's pending realism_state / chips.
// 1:1 regen cancel and group dance cancel put the old swipe back and must
// null `_pendingRealismMetadata` so a later Continue cannot stamp it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Continue does not merge pending realism metadata onto the bubble', () {
    final src = File('lib/services/chat/chat_service_generation_stream.dart')
        .readAsStringSync();
    final start = src.indexOf('if (t.mode == GenerationMode.continue_)');
    expect(start, greaterThanOrEqualTo(0));
    final end = src.indexOf('} else {', start);
    expect(end, greaterThan(start));
    final cont = src.substring(start, end);
    expect(
      cont.contains('addAll(_pendingRealismMetadata'),
      isFalse,
      reason:
          'Continue does not re-eval; leftover pending is a cancelled regen',
    );
  });

  test('1:1 regen cancel nulls pending before putting the swipe back', () {
    final src = File('lib/services/chat/chat_service_reprocess.dart')
        .readAsStringSync();
    final first = src.indexOf('Evaluation cancelled during regenerate');
    expect(first, greaterThanOrEqualTo(0));
    final firstReturn = src.indexOf('return;', first);
    final firstNull = src.indexOf('_pendingRealismMetadata = null', first);
    expect(
      firstNull,
      inInclusiveRange(first, firstReturn),
      reason:
          'the overlay-cancel bail must drop pending or Continue inherits it',
    );

    final second = src.indexOf(
      'Same put-back contract as the cancel point above',
    );
    expect(second, greaterThan(first));
    final secondReturn = src.indexOf('return;', second);
    final secondNull = src.indexOf('_pendingRealismMetadata = null', second);
    expect(secondNull, inInclusiveRange(second, secondReturn));
  });

  test('group dance cancel nulls pending', () {
    final src = File('lib/services/chat/chat_service_generation.dart')
        .readAsStringSync();
    final dance = src.indexOf('await _evaluateRealismForUpcomingSpeaker');
    expect(dance, greaterThanOrEqualTo(0));
    final cancelled = src.indexOf('if (_realismEvalCancelled)', dance);
    final ret = src.indexOf('return;', cancelled);
    final nulled = src.indexOf('_pendingRealismMetadata = null', cancelled);
    expect(
      nulled,
      inInclusiveRange(cancelled, ret),
      reason: 'group dance cancel put the turn down without dropping pending',
    );
  });
}
