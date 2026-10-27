// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a skip is: how far ([minutes]), where in the day it lands
// ([until]), and whether the cast slept through it. The skip reader and
// `/skip` both produce one; the clock only ever takes [landing]. The model
// reads the words, this file does the date math.

import 'dart:convert';

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

/// Where a skip of a day or more lands when nothing names a time of day.
const int kSkipLandingHour = 9;

/// Ten years: past this a reading is garbage, not a skip.
const int kSkipMaxMinutes = 10 * 365 * 24 * 60;

class SkipVerdict {
  const SkipVerdict({this.minutes = 0, this.until = '', this.slept = false});

  /// No skip.
  static const none = SkipVerdict();

  /// Story minutes the line skips; 0 when it only names where it lands.
  final int minutes;

  /// A [StoryClock.periods] name or a 24-hour `HH:MM`; '' for none.
  final String until;

  /// The cast slept through the gap.
  final bool slept;

  bool get isSkip => minutes > 0 || _untilTime != null;

  /// The reader said "skip" but gave no amount and no landing.
  bool get isUnmeasured => minutes < 0;

  (int, int)? get _untilTime {
    final u = until.trim().toLowerCase().replaceAll(' ', '_');
    if (u.isEmpty) return null;
    if (StoryClock.periods.contains(u)) {
      final t = StoryClock.representativeTime(DateTime.utc(2000), u);
      return (t.hour, t.minute);
    }
    return StoryClock.parseHHMM(u);
  }

  /// The moment the clock lands at, or null when this is no skip.
  ///
  /// A span under a day is exact ("eight hours" from 1:40 AM is 9:40 AM,
  /// whatever the line adds about the morning). A span of a day or more
  /// lands on its calendar day at [until], else in the morning. With no
  /// span, the next [until] after [clock] (the next morning is
  /// [StoryClock.nextMorning]).
  DateTime? landing(DateTime clock) {
    final at = _untilTime;
    if (minutes <= 0) {
      if (at == null) return null;
      // "The next morning" is the clock's one morning, the one a night
      // the judge reads also lands at.
      if (until.trim().toLowerCase() == 'morning') {
        return StoryClock.nextMorning(clock);
      }
      return StoryClock.nextNamedClock(clock, at.$1, at.$2);
    }
    final span = minutes > kSkipMaxMinutes ? kSkipMaxMinutes : minutes;
    final moved = clock.add(Duration(minutes: span));
    if (span < kLongSkipMinutes) return moved;
    final (hour, minute) = at ?? (kSkipLandingHour, 0);
    return DateTime.utc(moved.year, moved.month, moved.day, hour, minute);
  }

  /// The reader's JSON (tools or text floor), or null when it is not one.
  static SkipVerdict? fromJsonText(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final skip = decoded['skip']?.toString().toLowerCase();
    if (skip != 'true' && skip != 'false') return null;
    if (skip == 'false') return none;
    final raw = decoded['minutes'];
    final minutes = raw is num ? raw.round() : int.tryParse('$raw') ?? 0;
    final verdict = SkipVerdict(
      minutes: minutes < 0 ? 0 : minutes,
      until: (decoded['until'] ?? '').toString(),
      slept: (decoded['gap'] ?? '').toString().toLowerCase() == 'slept',
    );
    return verdict.isSkip
        ? verdict
        : SkipVerdict(minutes: -1, slept: verdict.slept);
  }

  @override
  bool operator ==(Object other) =>
      other is SkipVerdict &&
      other.minutes == minutes &&
      other.until == until &&
      other.slept == slept;

  @override
  int get hashCode => Object.hash(minutes, until, slept);

  @override
  String toString() => 'SkipVerdict($minutes min, "$until", slept: $slept)';
}
