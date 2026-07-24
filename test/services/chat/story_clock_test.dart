// Tests for the pure Story Clock leaf (design: docs/design/story-calendar.md).
// Everything here is deterministic — fixed UTC dates, no wall clock.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

void main() {
  group('StoryClock conversions', () {
    test('periodForHour boundaries', () {
      expect(StoryClock.periodForHour(4), 'night');
      expect(StoryClock.periodForHour(5), 'dawn');
      expect(StoryClock.periodForHour(7), 'dawn');
      expect(StoryClock.periodForHour(8), 'morning');
      expect(StoryClock.periodForHour(10), 'morning');
      expect(StoryClock.periodForHour(11), 'late_morning');
      expect(StoryClock.periodForHour(12), 'late_morning');
      expect(StoryClock.periodForHour(13), 'afternoon');
      expect(StoryClock.periodForHour(16), 'afternoon');
      expect(StoryClock.periodForHour(17), 'evening');
      expect(StoryClock.periodForHour(20), 'evening');
      expect(StoryClock.periodForHour(21), 'night');
      expect(StoryClock.periodForHour(23), 'night');
      expect(StoryClock.periodForHour(0), 'night');
    });

    test('representativeTime maps periods to their canonical clock', () {
      final d = DateTime.utc(2026, 3, 3);
      expect(
        StoryClock.representativeTime(d, 'dawn'),
        DateTime.utc(2026, 3, 3, 6, 0),
      );
      expect(
        StoryClock.representativeTime(d, 'late_morning'),
        DateTime.utc(2026, 3, 3, 11, 30),
      );
      expect(
        StoryClock.representativeTime(d, 'night'),
        DateTime.utc(2026, 3, 3, 22, 30),
      );
      // Unknown period → morning floor, never a throw (wire-format tolerance).
      expect(
        StoryClock.representativeTime(d, 'garbage'),
        DateTime.utc(2026, 3, 3, 9, 0),
      );
    });

    test('every period round-trips through periodForHour', () {
      final d = DateTime.utc(2026, 3, 3);
      for (final p in StoryClock.periods) {
        final t = StoryClock.representativeTime(d, p);
        expect(StoryClock.periodForHour(t.hour), p);
      }
    });

    test('dayCountFor counts calendar days, clamped to ≥ 1', () {
      final start = DateTime.utc(2026, 3, 1);
      expect(StoryClock.dayCountFor(DateTime.utc(2026, 3, 1, 9), start), 1);
      expect(
        StoryClock.dayCountFor(DateTime.utc(2026, 3, 1, 23, 59), start),
        1,
      );
      expect(StoryClock.dayCountFor(DateTime.utc(2026, 3, 2, 0, 10), start), 2);
      expect(StoryClock.dayCountFor(DateTime.utc(2026, 3, 5, 6), start), 5);
      // Clock before the anchor never yields Day 0 or negative.
      expect(StoryClock.dayCountFor(DateTime.utc(2026, 2, 27), start), 1);
    });

    test('dayCountFor spans a leap day correctly', () {
      final start = DateTime.utc(2028, 2, 28); // 2028 is a leap year
      expect(StoryClock.dayCountFor(DateTime.utc(2028, 2, 29, 9), start), 2);
      expect(StoryClock.dayCountFor(DateTime.utc(2028, 3, 1, 9), start), 3);
    });
  });

  group('StoryClock snaps', () {
    test('snapToNextPeriod walks the day and rolls into tomorrow', () {
      expect(
        StoryClock.snapToNextPeriod(DateTime.utc(2026, 3, 3, 9, 0)),
        DateTime.utc(2026, 3, 3, 11, 30),
      );
      // After night's 22:30 → dawn tomorrow.
      expect(
        StoryClock.snapToNextPeriod(DateTime.utc(2026, 3, 3, 22, 30)),
        DateTime.utc(2026, 3, 4, 6, 0),
      );
      // Small-hours night (01:00) → dawn the SAME calendar day.
      expect(
        StoryClock.snapToNextPeriod(DateTime.utc(2026, 3, 3, 1, 0)),
        DateTime.utc(2026, 3, 3, 6, 0),
      );
    });

    test('snapToPreviousPeriod walks back and rolls into yesterday', () {
      expect(
        StoryClock.snapToPreviousPeriod(DateTime.utc(2026, 3, 3, 11, 30)),
        DateTime.utc(2026, 3, 3, 9, 0),
      );
      // Before dawn's 06:00 → night the previous calendar day.
      expect(
        StoryClock.snapToPreviousPeriod(DateTime.utc(2026, 3, 3, 5, 0)),
        DateTime.utc(2026, 3, 2, 22, 30),
      );
    });

    test('snaps are inverse-ish across a month boundary', () {
      final endOfMonth = DateTime.utc(2026, 3, 31, 22, 30);
      final next = StoryClock.snapToNextPeriod(endOfMonth);
      expect(next, DateTime.utc(2026, 4, 1, 6, 0));
      expect(StoryClock.snapToPreviousPeriod(next), endOfMonth);
    });
  });

  group('StoryClock legacy synthesis', () {
    test('unset anchor (0): Day N lands on today at the period time', () {
      final today = DateTime.utc(2026, 3, 3); // a Tuesday
      final r = StoryClock.fromLegacy(
        timeOfDay: 'evening',
        dayCount: 5,
        startDayOfWeek: 0,
        today: today,
      );
      expect(r.clock, DateTime.utc(2026, 3, 3, 18, 30));
      expect(r.startDate, DateTime.utc(2026, 2, 27));
      expect(StoryClock.dayCountFor(r.clock, r.startDate), 5);
    });

    test('set anchor: the legacy displayed weekday is preserved', () {
      // Legacy: startDayOfWeek=1 (Mon), Day 5 → the old modulo-7 math showed
      // Friday. Today is Tuesday 2026-03-03, so current must slide back to
      // the most recent Friday (2026-02-27).
      final r = StoryClock.fromLegacy(
        timeOfDay: 'morning',
        dayCount: 5,
        startDayOfWeek: 1,
        today: DateTime.utc(2026, 3, 3),
      );
      expect(StoryClock.weekdayName(r.clock), 'Friday');
      expect(r.clock, DateTime.utc(2026, 2, 27, 9, 0));
      // And Day 1 falls on the anchor weekday (Monday).
      expect(r.startDate.weekday, 1);
      expect(StoryClock.dayCountFor(r.clock, r.startDate), 5);
    });

    test('anchor agreeing with today needs no slide', () {
      // Today Tuesday; startDayOfWeek=2 (Tue), Day 1 → Tuesday. No shift.
      final r = StoryClock.fromLegacy(
        timeOfDay: 'night',
        dayCount: 1,
        startDayOfWeek: 2,
        today: DateTime.utc(2026, 3, 3),
      );
      expect(r.clock, DateTime.utc(2026, 3, 3, 22, 30));
      expect(r.startDate, DateTime.utc(2026, 3, 3));
    });

    test('dayCount below 1 is clamped', () {
      final r = StoryClock.fromLegacy(
        timeOfDay: 'morning',
        dayCount: 0,
        startDayOfWeek: 0,
        today: DateTime.utc(2026, 3, 3),
      );
      expect(StoryClock.dayCountFor(r.clock, r.startDate), 1);
    });
  });

  group('StoryClock serialization', () {
    test('clock round-trips at minute precision', () {
      final c = DateTime.utc(2026, 3, 3, 21, 40, 55, 123);
      final iso = StoryClock.serializeClock(c);
      expect(StoryClock.parse(iso), DateTime.utc(2026, 3, 3, 21, 40));
    });

    test('date-only round-trips', () {
      expect(StoryClock.serializeDate(DateTime.utc(1887, 6, 1)), '1887-06-01');
      expect(StoryClock.parse('1887-06-01'), DateTime.utc(1887, 6, 1));
    });

    test('garbage and null parse to null', () {
      expect(StoryClock.parse(null), isNull);
      expect(StoryClock.parse(''), isNull);
      expect(StoryClock.parse('not-a-date'), isNull);
    });
  });

  group('StoryClock formatting', () {
    test('formatClock covers 12-hour edges', () {
      expect(
        StoryClock.formatClock(DateTime.utc(2026, 3, 3, 0, 5)),
        '12:05 AM',
      );
      expect(
        StoryClock.formatClock(DateTime.utc(2026, 3, 3, 12, 0)),
        '12:00 PM',
      );
      expect(
        StoryClock.formatClock(DateTime.utc(2026, 3, 3, 21, 40)),
        '9:40 PM',
      );
    });

    test('formatDate ordinals and conditional year', () {
      expect(
        StoryClock.formatDate(DateTime.utc(2026, 3, 3), realYear: 2026),
        'Tuesday, March 3rd',
      );
      expect(
        StoryClock.formatDate(DateTime.utc(2026, 3, 1), realYear: 2026),
        'Sunday, March 1st',
      );
      expect(
        StoryClock.formatDate(DateTime.utc(2026, 3, 22), realYear: 2026),
        'Sunday, March 22nd',
      );
      expect(
        StoryClock.formatDate(DateTime.utc(2026, 3, 13), realYear: 2026),
        'Friday, March 13th',
      );
      expect(
        StoryClock.formatDate(DateTime.utc(1887, 6, 1), realYear: 2026),
        'Wednesday, June 1st, 1887',
      );
    });

    test('formatShortDate + clockPhrase + periodLabel', () {
      final c = DateTime.utc(2026, 3, 3, 21, 40);
      expect(StoryClock.formatShortDate(c), 'Tue, Mar 3');
      expect(StoryClock.clockPhrase(c), '9:40 at night');
      expect(
        StoryClock.clockPhrase(DateTime.utc(2026, 3, 3, 11, 45)),
        '11:45 in the late morning',
      );
      expect(StoryClock.periodLabel('late_morning'), 'Late Morning');
    });
  });
}
