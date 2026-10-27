// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A second, plain read of a skip line: the one span it counts out ("eight
// hours", "2 weeks"). It never moves the clock. When it disagrees with the
// skip reader, the pop-up asks which one the player meant (#629: "slept
// eight hours and woke up" read as "the next morning"). Do not grow it into
// a parser: a line it cannot count is simply not checked.

import 'package:front_porch_ai/utils/utils.dart' show stripQuotedSpeech;

const Map<String, int> _numberWords = {
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
  'fifteen': 15,
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'forty-five': 45,
  'fifty': 50,
  'ninety': 90,
};

const Map<String, int> _unitMinutes = {
  'minute': 1,
  'hour': 60,
  'day': 24 * 60,
  'week': 7 * 24 * 60,
  'fortnight': 14 * 24 * 60,
  'month': 30 * 24 * 60,
  'year': 365 * 24 * 60,
};

final RegExp _span = RegExp(
  r'\b(\d+|' +
      _numberWords.keys.join('|') +
      r')\s+(minute|hour|day|week|fortnight|month|year)s?\b',
  caseSensitive: false,
);

/// The minutes [line] counts out in narration, or null when it names no
/// span or more than one.
int? countedSkipMinutes(String line) {
  final spans = _span.allMatches(stripQuotedSpeech(line)).toList();
  if (spans.length != 1) return null;
  final m = spans.single;
  final word = m.group(1)!.toLowerCase();
  final n = int.tryParse(word) ?? _numberWords[word];
  final unit = _unitMinutes[m.group(2)!.toLowerCase()];
  if (n == null || unit == null || n <= 0) return null;
  return n * unit;
}
