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

/// The Story Clock — pure calendar/clock math for the passage-of-time
/// subsystem (design: docs/design/story-calendar.md). No I/O, no state,
/// fully deterministic: TimeService owns the mutable clock; every
/// conversion, snap, synthesis, and formatting rule lives here (the
/// journal_physics.dart analog for time).
///
/// All DateTimes in and out are UTC. Story time has no timezone — UTC is
/// used purely so `Duration` day math can never be skewed by DST.
class StoryClock {
  StoryClock._();

  // ── Tuning constants (design §2 guardrails) ───────────────────────────────

  /// Hard per-turn clamp on LLM-reported elapsed minutes. The model paces
  /// scenes; it never teleports the timeline (bigger jumps are new_day / OOC).
  static const int maxMinutesPerTurn = 180;

  /// Deterministic drift applied when the per-turn eval fails or returns
  /// garbage — a flaky local model degrades to gentle creep, never a freeze.
  static const int failureDriftMinutes = 5;

  /// If the clock has not moved for this many turns, snap to the next
  /// period — preserves the old system's "time can never freeze forever"
  /// guarantee without its 6-turn gate.
  static const int stallBackstopTurns = 12;

  /// The six narrative periods, in day order. This exact list (and order) is
  /// a wire format: V2 card extensions, session rows, and realism_state
  /// snapshots all carry these strings.
  static const List<String> periods = [
    'dawn',
    'morning',
    'late_morning',
    'afternoon',
    'evening',
    'night',
  ];

  /// Representative wall-clock time for each period — where the clock lands
  /// when a period is all we know (legacy synthesis, nudges, AFK steps,
  /// stall backstop).
  static const Map<String, (int, int)> _representative = {
    'dawn': (6, 0),
    'morning': (9, 0),
    'late_morning': (11, 30),
    'afternoon': (14, 30),
    'evening': (18, 30),
    'night': (22, 30),
  };

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  // ── Conversions ───────────────────────────────────────────────────────────

  /// hour (0-23) → period. Boundaries per design §2: dawn 05-08,
  /// morning 08-11, late_morning 11-13, afternoon 13-17, evening 17-21,
  /// night 21-05.
  static String periodForHour(int hour) {
    if (hour >= 5 && hour < 8) return 'dawn';
    if (hour >= 8 && hour < 11) return 'morning';
    if (hour >= 11 && hour < 13) return 'late_morning';
    if (hour >= 13 && hour < 17) return 'afternoon';
    if (hour >= 17 && hour < 21) return 'evening';
    return 'night';
  }

  /// The given calendar date at [period]'s representative time. Unknown
  /// period strings fall back to morning (forgiving wire-format floor).
  static DateTime representativeTime(DateTime date, String period) {
    final (h, m) = _representative[period] ?? _representative['morning']!;
    return DateTime.utc(date.year, date.month, date.day, h, m);
  }

  /// Truncate to the UTC calendar date (midnight).
  static DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The user's local calendar date as a UTC-normalized anchor. The ONE
  /// wall-clock read in the subsystem — "today" for fresh chats and legacy
  /// synthesis follows the user's local date, not UTC's.
  static DateTime todayAnchor() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// 08:00 on the story's next morning: same calendar day when the clock is
  /// in the small hours (01:00 → 08:00 today), otherwise tomorrow. Used by
  /// new_day transitions and the OOC "next morning" skip.
  static DateTime nextMorning(DateTime clock) {
    final d = dateOnly(clock);
    final morning = DateTime.utc(d.year, d.month, d.day, 8);
    return clock.hour < 8
        ? morning
        : DateTime.utc(d.year, d.month, d.day + 1, 8);
  }

  /// Day 1-based story day for [clock] against [startDate].
  /// Clamped to ≥ 1 so a clock nudged before the anchor never yields Day 0.
  static int dayCountFor(DateTime clock, DateTime startDate) {
    final days = dateOnly(clock).difference(dateOnly(startDate)).inDays + 1;
    return days < 1 ? 1 : days;
  }

  // ── Snaps (nudges, AFK steps, stall backstop) ─────────────────────────────

  /// The next period's representative time strictly after [clock]
  /// (dawn of the next day after night's 22:30).
  static DateTime snapToNextPeriod(DateTime clock) {
    final date = dateOnly(clock);
    for (final p in periods) {
      final t = representativeTime(date, p);
      if (t.isAfter(clock)) return t;
    }
    return representativeTime(date.add(const Duration(days: 1)), 'dawn');
  }

  /// The previous period's representative time strictly before [clock]
  /// (night of the previous day before dawn's 06:00).
  static DateTime snapToPreviousPeriod(DateTime clock) {
    final date = dateOnly(clock);
    for (final p in periods.reversed) {
      final t = representativeTime(date, p);
      if (t.isBefore(clock)) return t;
    }
    return representativeTime(date.subtract(const Duration(days: 1)), 'night');
  }

  // ── Legacy synthesis (design §3) ──────────────────────────────────────────

  /// Build a full clock + anchor from period-and-day-only data (legacy
  /// session rows, old realism_state snapshots, V2 cards from older apps,
  /// the creators' friendly pickers).
  ///
  /// The current story date lands on [today] — slid back 0-6 days when a
  /// set [startDayOfWeek] (1=Mon..7=Sun) disagrees, so the weekday the old
  /// modulo-7 math displayed for Day [dayCount] is preserved and the visible
  /// "Tue · Day 5" never jumps across the upgrade. Pass 0 (legacy/unset)
  /// to anchor on [today] directly.
  static ({DateTime clock, DateTime startDate}) fromLegacy({
    required String timeOfDay,
    required int dayCount,
    required int startDayOfWeek,
    required DateTime today,
  }) {
    final safeDay = dayCount < 1 ? 1 : dayCount;
    var current = dateOnly(today);
    if (startDayOfWeek >= 1 && startDayOfWeek <= 7) {
      final legacyWeekday = ((startDayOfWeek - 1 + (safeDay - 1)) % 7) + 1;
      final shift = (current.weekday - legacyWeekday + 7) % 7;
      current = current.subtract(Duration(days: shift));
    }
    return (
      clock: representativeTime(current, timeOfDay),
      startDate: current.subtract(Duration(days: safeDay - 1)),
    );
  }

  // ── Serialization (session columns, snapshots, card extensions) ───────────

  /// Minute-precision ISO-8601 UTC ("2026-03-03T21:40:00.000Z" round-trips
  /// through [parseClock]).
  static String serializeClock(DateTime clock) => DateTime.utc(
    clock.year,
    clock.month,
    clock.day,
    clock.hour,
    clock.minute,
  ).toIso8601String();

  /// Date-only ISO-8601 ("2026-03-03") for the Day 1 anchor.
  static String serializeDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Forgiving "HH:MM" parse for card start-time extensions (null/garbage →
  /// null). 24-hour, both zero-padded and bare hours accepted.
  static (int, int)? parseHHMM(String? hhmm) {
    if (hhmm == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return (h, min);
  }

  /// Forgiving parse of either serialization (null/garbage → null). The
  /// result is normalized to UTC regardless of the stored form's zone.
  static DateTime? parse(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return null;
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
    );
  }

  // ── Formatting (UI + prompt) ──────────────────────────────────────────────

  static String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

  static String monthName(DateTime d) => _months[d.month - 1];

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    switch (day % 10) {
      case 1:
        return '${day}st';
      case 2:
        return '${day}nd';
      case 3:
        return '${day}rd';
      default:
        return '${day}th';
    }
  }

  /// "9:40 PM" — the UI clock.
  static String formatClock(DateTime clock) {
    final h12 = clock.hour % 12 == 0 ? 12 : clock.hour % 12;
    final mm = clock.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${clock.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Tuesday, March 3rd" — with ", 1887" appended only when the story's
  /// year differs from [realYear] (design §7: modern chats don't pay tokens
  /// for a redundant year; period chats get the year that defines them).
  static String formatDate(DateTime clock, {required int realYear}) {
    final base =
        '${weekdayName(clock)}, ${monthName(clock)} ${_ordinal(clock.day)}';
    return clock.year == realYear ? base : '$base, ${clock.year}';
  }

  /// "Tue, Mar 3" — compact strip/chip form.
  static String formatShortDate(DateTime clock) =>
      '${weekdayName(clock).substring(0, 3)}, '
      '${monthName(clock).substring(0, 3)} ${clock.day}';

  /// "9:40 at night" — the words-only injection form (clock digits plus the
  /// period phrase, so the model gets both fidelity and atmosphere).
  static String clockPhrase(DateTime clock) {
    const phrases = {
      'dawn': 'at dawn',
      'morning': 'in the morning',
      'late_morning': 'in the late morning',
      'afternoon': 'in the afternoon',
      'evening': 'in the evening',
      'night': 'at night',
    };
    final h12 = clock.hour % 12 == 0 ? 12 : clock.hour % 12;
    final mm = clock.minute.toString().padLeft(2, '0');
    return '$h12:$mm ${phrases[periodForHour(clock.hour)]}';
  }

  /// Title-case display label for a period string ("late_morning" →
  /// "Late Morning") — chips, dropdowns, skip labels.
  static String periodLabel(String period) => period
      .split('_')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
