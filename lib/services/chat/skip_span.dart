// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Counted spans in skip narration: "6 hours", "two weeks", "a few days",
// "3 months", "a year". [lower] is quote-stripped lowercase, as everywhere
// in the skip path.
//
// Before 2026-10-13 any "weeks later" counted as one week, and days only
// moved the clock with an OOC marker, so "two weeks later" landed seven
// days on and "a few days later" did not move it at all.

/// The span a counted skip names, and where it lands.
class SkipSpan {
  SkipSpan._();

  static const _numbers = {
    'a': 1,
    'an': 1,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
  };

  /// Vague counts read as a number only for days and longer. "A few hours"
  /// keeps its own +2h bucket in StoryClock.
  static const _vague = {
    'a couple of': 2,
    'a couple': 2,
    'a few': 3,
    'several': 3,
  };

  static const _count =
      r'(\d+|a couple of|a couple|a few|several|an?|one|two|three|four|'
      r'five|six|seven|eight|nine|ten|eleven|twelve)';

  /// A long span said as narration: "two weeks later", "3 days pass",
  /// "a few months went by". Backstory is not a skip: "for two weeks",
  /// "three years had passed", "a year passed since the accident".
  static final _narrated = RegExp(
    '\\b$_count\\s*(days?|weeks?|months?|years?)\\s+'
    r'(?:later|pass(?:es|ed)?|go(?:es)? by|went by)\b(?!\s+since\b)',
  );

  /// Or asked for: "skip ahead two weeks", "fast forward 3 months". A bare
  /// skip or jump needs a direction: "I skip a day of school" is not one.
  static final _asked = RegExp(
    r'\b(?:(?:time.?skip|fast.?forward)(?:\s+(?:ahead|forward))?'
    r'|(?:skip|jump)\s+(?:ahead|forward|by|to))'
    r'(?:\s+(?:by|to))?\s+'
    '$_count\\s*(days?|weeks?|months?|years?)\\b',
  );

  static final _shortDigit = RegExp(r'\b(\d+)\s*(minutes?|hours?|days?)\b');
  static final _shortWord = RegExp(
    r'\b(an?|one|two|three|four|five|six|seven|eight|nine|ten|'
    r'eleven|twelve)\s*(minutes?|hours?|days?)\b',
  );

  /// True when [lower] narrates or asks for a skip of a day or more.
  static bool namesLongSkip(String lower) =>
      _narrated.hasMatch(lower) || _asked.hasMatch(lower);

  /// Landing for a day-plus skip, or null when [lower] names none.
  static DateTime? longLanding(DateTime clock, String lower) {
    final m = _narrated.firstMatch(lower) ?? _asked.firstMatch(lower);
    if (m == null) return null;
    final n = _countOf(m.group(1)!);
    if (n <= 0) return null;
    return _add(clock, n, m.group(2)!);
  }

  /// Digit or word duration in minutes, hours or days ("6 hours", "six
  /// hours", "10 days" under an OOC marker). Null if none.
  static DateTime? shortLanding(DateTime clock, String lower) {
    final digit = _shortDigit.firstMatch(lower);
    if (digit != null) {
      return _add(clock, int.tryParse(digit.group(1)!) ?? 0, digit.group(2)!);
    }
    final word = _shortWord.firstMatch(lower);
    if (word == null) return null;
    return _add(clock, _numbers[word.group(1)!] ?? 0, word.group(2)!);
  }

  static int _countOf(String raw) =>
      int.tryParse(raw) ?? _numbers[raw] ?? _vague[raw] ?? 0;

  static DateTime? _add(DateTime clock, int n, String unit) {
    if (n <= 0) return null;
    if (unit.startsWith('year')) return _addMonths(clock, 12 * n.clamp(1, 10));
    if (unit.startsWith('month')) return _addMonths(clock, n.clamp(1, 24));
    if (unit.startsWith('week')) {
      return clock.add(Duration(days: 7 * n.clamp(1, 52)));
    }
    if (unit.startsWith('day')) {
      return clock.add(Duration(days: n.clamp(1, 365)));
    }
    if (unit.startsWith('hour')) {
      return clock.add(Duration(hours: n.clamp(1, 72)));
    }
    return clock.add(Duration(minutes: n.clamp(1, 24 * 60)));
  }

  /// Same day of the month and time of day, pulled back to the month's last
  /// day when it is shorter (31 Jan + 1 month is 28 or 29 Feb, not 3 Mar).
  static DateTime _addMonths(DateTime clock, int months) {
    final first = DateTime.utc(clock.year, clock.month + months, 1);
    final last = DateTime.utc(first.year, first.month + 1, 0).day;
    return DateTime.utc(
      first.year,
      first.month,
      clock.day > last ? last : clock.day,
      clock.hour,
      clock.minute,
    );
  }
}
