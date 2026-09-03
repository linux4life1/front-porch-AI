// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Calendar birthday: full YYYY-MM-DD, no Feb 29. Age and heat come from
// the story clock. One live journal card per owner is rewritten in place.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

/// How close a birthday is to the story's current date.
enum BirthdayPhase {
  /// Cold identity. Not in the always-injected hot set.
  far,

  /// Inside two weeks. Background thought; no wishlist.
  upcoming,

  /// The story day itself.
  today,

  /// One or two story days after. Still a little warm, then cold.
  justPast,
}

/// A stored calendar date. Feb 29 is never valid.
class BirthdayDate {
  final int year;
  final int month;
  final int day;

  const BirthdayDate({
    required this.year,
    required this.month,
    required this.day,
  });

  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  String get monthDay => '${BirthdayMath.monthName(month)} $day';

  DateTime get asUtc => DateTime.utc(year, month, day);
}

/// Reading against a story "now".
class BirthdayReading {
  final BirthdayDate birth;
  final int age;
  final int daysUntil;
  final int daysSince;
  final double heat;
  final BirthdayPhase phase;

  const BirthdayReading({
    required this.birth,
    required this.age,
    required this.daysUntil,
    required this.daysSince,
    required this.heat,
    required this.phase,
  });
}

/// Pure calendar math. No I/O.
class BirthdayMath {
  BirthdayMath._();

  static const int kAnticipateDays = 14;
  static const int kAfterglowDays = 2;

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

  static String monthName(int month) =>
      (month >= 1 && month <= 12) ? _months[month - 1] : '';

  /// Days in [month] for birthday authoring. February is always 28.
  static int daysInMonth(int month) {
    if (month == 2) return 28;
    if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
    if (month >= 1 && month <= 12) return 31;
    return 0;
  }

  /// Parse `YYYY-MM-DD`. Rejects Feb 29, junk, and out-of-range days.
  static BirthdayDate? parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (year < 1800 || year > 2200) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > daysInMonth(month)) return null;
    return BirthdayDate(year: year, month: month, day: day);
  }

  static BirthdayReading? read(String? iso, DateTime storyNow) {
    final birth = parse(iso);
    if (birth == null) return null;
    final now = StoryClock.dateOnly(storyNow);
    if (birth.asUtc.isAfter(now)) return null;

    var age = now.year - birth.year;
    final occurred =
        now.month > birth.month ||
        (now.month == birth.month && now.day >= birth.day);
    if (!occurred) age--;
    if (age < 0) return null;

    var next = DateTime.utc(now.year, birth.month, birth.day);
    if (next.isBefore(now)) {
      next = DateTime.utc(now.year + 1, birth.month, birth.day);
    }
    final daysUntil = next.difference(now).inDays;

    final last = daysUntil == 0
        ? now
        : DateTime.utc(
            occurred ? now.year : now.year - 1,
            birth.month,
            birth.day,
          );
    final daysSince = now.difference(last).inDays;

    final phase = daysUntil == 0
        ? BirthdayPhase.today
        : (daysUntil > 0 && daysUntil <= kAnticipateDays)
        ? BirthdayPhase.upcoming
        : (daysSince > 0 && daysSince <= kAfterglowDays)
        ? BirthdayPhase.justPast
        : BirthdayPhase.far;

    return BirthdayReading(
      birth: birth,
      age: age,
      daysUntil: daysUntil,
      daysSince: daysSince,
      heat: heatFor(daysUntil, daysSince),
      phase: phase,
    );
  }

  /// Whether diary cards need a rewrite for this clock.
  ///
  /// Same story day → no. Far from every birthday → no, even across days.
  /// Heat and the diary line only move once a date is inside the two-week
  /// window, on the day, or in the two-day afterglow — or when age/phase
  /// would change (time skip into the window, birthday happening).
  static bool needsRefresh({
    required DateTime? lastSyncDay,
    required String lastIdentityKey,
    required String identityKey,
    required DateTime now,
    required List<String> isos,
  }) {
    if (identityKey != lastIdentityKey) return true;
    if (lastSyncDay == null) return true;
    final today = StoryClock.dateOnly(now);
    final last = StoryClock.dateOnly(lastSyncDay);
    if (last == today) return false;
    for (final iso in isos) {
      final before = read(iso, last);
      final after = read(iso, today);
      if (before == null && after == null) continue;
      if (before == null || after == null) return true;
      if (before.phase != after.phase || before.age != after.age) {
        return true;
      }
      if (after.phase == BirthdayPhase.upcoming ||
          after.phase == BirthdayPhase.today ||
          after.phase == BirthdayPhase.justPast) {
        return true;
      }
    }
    return false;
  }

  static double heatFor(int daysUntil, int daysSince) {
    if (daysUntil == 0) return 1.0;
    if (daysUntil > 0 && daysUntil <= kAnticipateDays) {
      return 0.35 + (kAnticipateDays - daysUntil) / kAnticipateDays * 0.60;
    }
    if (daysSince > 0 && daysSince <= kAfterglowDays) {
      return 0.50 - (daysSince - 1) * 0.10;
    }
    return 0.12;
  }

  /// First-person diary line. No wishlist. No "ask for presents".
  static String diaryLine({
    required BirthdayReading reading,
    required bool self,
    required String userName,
  }) {
    final date = reading.birth.monthDay;
    final they = userName.trim().isEmpty ? '{{user}}' : userName.trim();
    switch (reading.phase) {
      case BirthdayPhase.today:
        return self
            ? 'Today I turn ${reading.age}.'
            : "Today is $they's birthday. They turn ${reading.age}.";
      case BirthdayPhase.upcoming:
        final nextAge = reading.age + 1;
        return self
            ? 'My birthday is $date. I\'ll be $nextAge.'
            : "$they's birthday is $date. They'll be $nextAge.";
      case BirthdayPhase.justPast:
      case BirthdayPhase.far:
        return self
            ? 'I am ${reading.age}. Birthday $date.'
            : '$they is ${reading.age}. Birthday $date.';
    }
  }

  static String objectiveTitleFor({
    required String monthDay,
    required int year,
    required bool self,
    required String userName,
  }) {
    final they = userName.trim().isEmpty ? '{{user}}' : userName.trim();
    final goal = self
        ? 'have a good birthday with $they'
        : "make $they's birthday special";
    return 'Birthday ($monthDay, $year): $goal';
  }

  static bool isBirthdayObjective(String text, {int? year, String? monthDay}) {
    final t = text.trim();
    if (!t.startsWith('Birthday (')) return false;
    if (year != null && !t.contains(', $year)')) return false;
    if (monthDay != null && monthDay.isNotEmpty && !t.contains('$monthDay,')) {
      return false;
    }
    return true;
  }

  /// Last year's outing occupies the cap of 4 until we retire it.
  /// Afterglow keeps this year. Far retires any leftover. Upcoming
  /// and today retire other years only. Plant-guard still uses
  /// [isBirthdayObjective] with [year] and does not evict others.
  static bool outingShouldRetire(
    String text, {
    required BirthdayPhase phase,
    required int occurrenceYear,
    required String monthDay,
  }) {
    if (!isBirthdayObjective(text, monthDay: monthDay)) return false;
    switch (phase) {
      case BirthdayPhase.justPast:
        return false;
      case BirthdayPhase.far:
        return true;
      case BirthdayPhase.upcoming:
      case BirthdayPhase.today:
        return !isBirthdayObjective(
          text,
          year: occurrenceYear,
          monthDay: monthDay,
        );
    }
  }

  /// Editor age line. Authored ISO story date, else the calendar
  /// day the chat starts.
  static DateTime ageAsOfStory(String? iso) {
    final s = (iso ?? '').trim();
    if (s.isEmpty) return StoryClock.todayAnchor();
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return StoryClock.todayAnchor();
    return StoryClock.dateOnly(parsed);
  }

  /// Year of the upcoming (or today's) birthday against [storyNow].
  static int occurrenceYear(BirthdayReading reading, DateTime storyNow) {
    final now = StoryClock.dateOnly(storyNow);
    if (reading.daysUntil == 0) return now.year;
    var next = DateTime.utc(now.year, reading.birth.month, reading.birth.day);
    if (next.isBefore(now)) {
      next = DateTime.utc(now.year + 1, next.month, next.day);
    }
    return next.year;
  }

  static List<String> outingTasks({
    required CharacterCard card,
    required bool self,
    required String userName,
  }) {
    final they = userName.trim().isEmpty ? '{{user}}' : userName.trim();
    final likes = card.frontPorchExtensions?.likes ?? const <String>[];
    final fromLikes = [
      for (final like in likes.take(3))
        if (like.trim().isNotEmpty)
          self
              ? 'Do something involving ${like.trim()} with $they'
              : 'Share ${like.trim()} with $they',
    ];
    if (fromLikes.isNotEmpty) return fromLikes;
    return self
        ? ['Spend the day with $they', 'Eat something special']
        : ['Plan something $they would like', 'Spend the day together'];
  }
}
