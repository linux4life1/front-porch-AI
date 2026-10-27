// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A jump of time the reply itself narrates ("A week later, she…", "Six
// hours later, the rain stops"), as the scene-time judge reports it in
// `days_elapsed` / `hours_elapsed`. The judge's word counts only when the
// exchange names that kind of span (hours: counted, in narration), the
// same hallucination guard `newDayCorroboration` is for `new_day`. Jumps
// no longer than an ordinary turn are left to `minutes_elapsed`.

import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/utils/quoted_speech.dart';

final _daysNamed = RegExp(
  r'\b(?:days?|weeks?|months?|years?|fortnights?)\b',
  caseSensitive: false,
);

/// A counted span of hours in the narration ("six hours later", "a few
/// hours pass") or a night ("overnight"). Bare "later" or "until" is too
/// common in ordinary talk to let the judge move the clock hours.
final _hoursNamed = RegExp(
  r'\b(?:\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|'
  r'twelve|few|several|some|many)\s+(?:more\s+|long\s+)?hours?\b|'
  r'\bhours\s+(?:later|pass(?:ed)?|went\s+by)\b|\bovernight\b',
  caseSensitive: false,
);

int _judgedInt(String text, String key) {
  final m = RegExp('"$key"\\s*:\\s*"?(\\d+)').firstMatch(text);
  return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
}

/// Flat-JSON string field of a judge answer; missing or malformed is null.
String? judgedStringField(String text, String key) =>
    RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(text)?.group(1);

class ReplyJump {
  const ReplyJump._({required this.minutes, this.landsAt = ''});

  /// Minutes the reply skipped. Whole days when the judge counted days.
  final int minutes;

  /// The judge's `lands_at` for a jump of days: a time of day, or blank
  /// for the morning.
  final String landsAt;

  /// The jump in [judged] for the exchange [recent], or null when the
  /// reply jumped no further than a turn's own minutes.
  static ReplyJump? read(String judged, String recent) {
    final days = _judgedInt(judged, 'days_elapsed');
    if (days > 0 && _daysNamed.hasMatch(recent)) {
      return ReplyJump._(
        minutes: days.clamp(1, 365) * kLongSkipMinutes,
        landsAt: judgedStringField(judged, 'lands_at') ?? '',
      );
    }
    final minutes = _judgedInt(judged, 'hours_elapsed').clamp(0, 23) * 60;
    if (minutes > StoryClock.maxMinutesPerTurn &&
        _hoursNamed.hasMatch(stripQuotedSpeech(recent))) {
      return ReplyJump._(minutes: minutes);
    }
    return null;
  }
}
