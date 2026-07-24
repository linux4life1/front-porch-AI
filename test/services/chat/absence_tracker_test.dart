// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/absence_tracker.dart';

void main() {
  group('AbsenceTracker.bucketPhrase', () {
    test('below threshold → null (no banner, no ack)', () {
      expect(AbsenceTracker.bucketPhrase(const Duration(hours: 3)), isNull);
      expect(AbsenceTracker.bucketPhrase(const Duration(hours: 23)), isNull);
      expect(AbsenceTracker.bucketPhrase(Duration.zero), isNull);
    });

    test('coarse buckets in words', () {
      expect(
        AbsenceTracker.bucketPhrase(const Duration(hours: 25)),
        'a day',
      );
      expect(
        AbsenceTracker.bucketPhrase(const Duration(hours: 60)),
        'a few days',
      );
      expect(
        AbsenceTracker.bucketPhrase(const Duration(days: 8)),
        'about a week',
      );
      expect(
        AbsenceTracker.bucketPhrase(const Duration(days: 20)),
        'a couple of weeks',
      );
      expect(
        AbsenceTracker.bucketPhrase(const Duration(days: 45)),
        'a long while',
      );
    });

    test('custom threshold gates the first buckets', () {
      expect(
        AbsenceTracker.bucketPhrase(
          const Duration(hours: 60),
          thresholdHours: 72,
        ),
        isNull,
      );
      expect(
        AbsenceTracker.bucketPhrase(
          const Duration(hours: 80),
          thresholdHours: 72,
        ),
        'a few days',
      );
      // 12h threshold: a sub-day gap still reads as "a day" at minimum? No —
      // 12-23h with a 12h threshold falls before the 48h bucket ladder's
      // first rung, so it reads as 'a day'.
      expect(
        AbsenceTracker.bucketPhrase(
          const Duration(hours: 14),
          thresholdHours: 12,
        ),
        'a day',
      );
    });

    test('never contains digits (privacy: coarse words only)', () {
      for (final h in [12, 25, 60, 24 * 8, 24 * 20, 24 * 100]) {
        final p = AbsenceTracker.bucketPhrase(
          Duration(hours: h),
          thresholdHours: 12,
        );
        if (p != null) {
          expect(p, isNot(matches(RegExp(r'\d'))), reason: '$h hours → "$p"');
        }
      }
    });
  });

  group('AbsenceTracker.ackNote', () {
    test('contains the phrase, forbids speculation, stays one-shot-worded',
        () {
      final note = AbsenceTracker.ackNote('a few days');
      expect(note, contains('a few days'));
      expect(note, contains('never guess'));
      expect(note, contains('do not mention it again'));
      expect(note, contains('{{user}}'));
      expect(note, isNot(matches(RegExp(r'\d'))));
    });
  });
}
