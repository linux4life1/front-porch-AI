// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// `/skip` at the end of a message: the exact skip, no model asked.
// "We turn in for the night. /skip 8h" sends the line without the tag and
// jumps the clock eight hours before the reply. A message that is only
// `/skip 8h` moves the clock and sends nothing.

import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_skip/skip_verdict.dart';

/// Shown when `/skip` has nothing it can read.
const String kSkipTagUsage =
    'Say how far to skip, like /skip 8h, /skip 2d, /skip morning or '
    '/skip 07:30.';

/// Shown when `/skip` ends a command such as `/narrate`.
const String kSkipAfterCommand =
    '/skip goes at the end of a line you send, not after a command.';

/// Shown when `/skip` is used while the story clock is off.
const String kSkipNeedsClock =
    'Turn on Passage of Time in Settings → Porch Life to use /skip.';

final RegExp _tag = RegExp(r'(?:^|\s)/skip\b(.*)$', caseSensitive: false);

final RegExp _span = RegExp(
  r'^(\d+(?:\.\d+)?)\s*(minutes?|mins?|m|hours?|hrs?|h|days?|d|weeks?|wks?|w|'
  r'months?|mo|years?|yrs?|y)$',
);

const Map<String, int> _unitMinutes = {
  'm': 1,
  'min': 1,
  'h': 60,
  'hr': 60,
  'hour': 60,
  'd': 24 * 60,
  'day': 24 * 60,
  'w': 7 * 24 * 60,
  'wk': 7 * 24 * 60,
  'week': 7 * 24 * 60,
  'mo': 30 * 24 * 60,
  'month': 30 * 24 * 60,
  'y': 365 * 24 * 60,
  'yr': 365 * 24 * 60,
  'year': 365 * 24 * 60,
};

final RegExp _clock = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$');

/// A message split from its trailing `/skip`.
class SkipTag {
  const SkipTag._({required this.body, this.verdict, this.error});

  /// The message with no `/skip` in it.
  const SkipTag.none(String text) : this._(body: text);

  /// The line to send, without the tag. Empty when the message was only
  /// the tag.
  final String body;

  /// The skip the tag asks for. Null when there is no tag, or it is bad.
  final SkipVerdict? verdict;

  /// Why the tag cannot be read ([kSkipTagUsage]), else null.
  final String? error;

  bool get present => verdict != null || error != null;

  static SkipTag parse(String text) {
    final match = _tag.firstMatch(text);
    if (match == null) return SkipTag.none(text);
    final body = text.substring(0, match.start).trimRight();
    final args = match.group(1)!.trim().toLowerCase();
    // "I tap /skip on the ad." is prose: a tag is the whole message, or
    // words that start like an amount or a landing.
    if (args.isEmpty ? body.isNotEmpty : !_tagShaped(args)) {
      return SkipTag.none(text);
    }
    final verdict = _read(args);
    return verdict == null
        ? SkipTag._(body: body, error: kSkipTagUsage)
        : SkipTag._(body: body, verdict: verdict);
  }

  static final RegExp _tagStart = RegExp(
    r'^(?:\d|late\b|noon\b|midday\b|midnight\b|'
    r'(?:dawn|morning|late_morning|afternoon|evening|night)\b)',
  );

  static bool _tagShaped(String args) => _tagStart.hasMatch(args);

  /// "8h", "1d 6h", "90 min", "2 weeks morning", "night", "7:30", "7am".
  static SkipVerdict? _read(String args) {
    if (args.isEmpty) return null;
    final words = args.split(RegExp(r'\s+'));
    var minutes = 0;
    var until = '';
    for (var i = 0; i < words.length; i++) {
      var word = words[i];
      // "8 hours": a number and its unit as two words.
      if (RegExp(r'^\d+(\.\d+)?$').hasMatch(word) && i + 1 < words.length) {
        final joined = '$word${words[i + 1]}';
        if (_span.hasMatch(joined)) {
          word = joined;
          i++;
        }
      }
      final span = _span.firstMatch(word);
      if (span != null) {
        final unit = _unitMinutes[_singular(span.group(2)!)];
        if (unit == null) return null;
        minutes += (double.parse(span.group(1)!) * unit).round();
        continue;
      }
      if (until.isNotEmpty) return null;
      final landing = _landing(word, i + 1 < words.length ? words[i + 1] : '');
      if (landing == null) return null;
      if (landing.$2) i++;
      until = landing.$1;
    }
    final verdict = SkipVerdict(minutes: minutes, until: until);
    return verdict.isSkip ? verdict : null;
  }

  static String _singular(String unit) {
    if (unit == 'm' ||
        unit == 'mins' ||
        unit == 'minute' ||
        unit == 'minutes') {
      return 'min';
    }
    if (unit == 'hrs') return 'hr';
    if (unit == 'wks') return 'wk';
    if (unit == 'yrs') return 'yr';
    return unit.endsWith('s') && unit.length > 2
        ? unit.substring(0, unit.length - 1)
        : unit;
  }

  /// A landing word (and whether it used [next] too): a period, "late
  /// morning", "noon", or a clock time.
  static (String, bool)? _landing(String word, String next) {
    if (word == 'late' && next == 'morning') return ('late_morning', true);
    if (word == 'noon' || word == 'midday') return ('12:00', false);
    if (word == 'midnight') return ('00:00', false);
    final period = word == 'late_morning' ? word : word.replaceAll('-', '_');
    if (StoryClock.periods.contains(period)) return (period, false);
    final ampm = next == 'am' || next == 'pm';
    final clock = _clock.firstMatch(ampm ? '$word$next' : word);
    if (clock == null) return null;
    var hour = int.parse(clock.group(1)!);
    final minute = int.tryParse(clock.group(2) ?? '') ?? 0;
    final suffix = clock.group(3);
    if (suffix == null && clock.group(2) == null) return null;
    if (suffix != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (suffix == 'pm' ? 12 : 0);
    }
    if (hour > 23 || minute > 59) return null;
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return ('$hh:$mm', ampm);
  }
}
