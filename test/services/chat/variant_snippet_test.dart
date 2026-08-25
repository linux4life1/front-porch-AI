// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  group('variantSnippet', () {
    test('returns the full text when it is under the word cap', () {
      expect(variantSnippet('Hello there friend'), 'Hello there friend');
    });

    test('takes the first 15 words and ellipsizes the rest', () {
      const text =
          'one two three four five six seven eight nine ten '
          'eleven twelve thirteen fourteen fifteen sixteen seventeen';
      expect(
        variantSnippet(text),
        'one two three four five six seven eight nine ten '
        'eleven twelve thirteen fourteen fifteen…',
      );
    });

    test('strips think tags and collapses whitespace', () {
      expect(
        variantSnippet('<think>plan</think>\nHello   there'),
        'Hello there',
      );
    });

    test('empty input is empty', () {
      expect(variantSnippet('   '), '');
    });
  });

  group('buildVariantOptions', () {
    test('marks the current variant and reports character counts', () {
      final rows = buildVariantOptions(['Hi there', 'Hey you'], 1);
      expect(rows, hasLength(2));
      expect(rows[0].isCurrent, isFalse);
      expect(rows[1].isCurrent, isTrue);
      expect(rows[0].charCount, 'Hi there'.length);
      expect(rows[1].snippet, 'Hey you');
    });

    test('clamps a stale current index', () {
      final rows = buildVariantOptions(['only'], 99);
      expect(rows.single.isCurrent, isTrue);
    });
  });

  group('shouldReadRoomForGreeting', () {
    test('first greet keeps starting emotion (no reading-the-room)', () {
      expect(shouldReadRoomForGreeting(0), isFalse);
    });

    test('alternative greets get reading-the-room', () {
      expect(shouldReadRoomForGreeting(1), isTrue);
      expect(shouldReadRoomForGreeting(8), isTrue);
    });

    test('an authored overlay skips reading-the-room', () {
      expect(shouldReadRoomForGreeting(1, hasAuthoredSeed: true), isFalse);
    });

    test('empty first_mes: displayed 0 Reads the Room when unauthored', () {
      expect(shouldReadRoomForGreeting(0, firstMesEmpty: true), isTrue);
      expect(
        shouldReadRoomForGreeting(
          0,
          hasAuthoredSeed: true,
          firstMesEmpty: true,
        ),
        isFalse,
      );
    });
  });
}
