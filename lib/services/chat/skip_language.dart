// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Quote-stripped lowercase. Completed-night language is a skip (land
// morning first). "Let's go to bed" is a scene, not a skip.

/// Existing skip phrases plus a finished night. Callers still strip quotes.
final _skipPhrase = RegExp(
  r'\b(time.?skip|fast.?forward|skip ahead|several hours|a few hours|hours? later|'
  r'the next (morning|day|evening|afternoon|night|dawn)|'
  r'next (morning|day|evening|afternoon|night|dawn)|'
  r'hours? pass(?:ed)?|time passes|the following (morning|day)|'
  r'wake up the next|woke up|the next day|'
  r'(a|one) week (later|passes)|next week|weeks? later|'
  r'(a|one) month (later|passes)|next month|'
  r'(?:sleep|slept|sleeping) through (?:the )?night|'
  r'(?:sleep|slept|sleeping) through (?:till|until|to) (?:dawn|morning)|'
  r'(?:sleep|slept|sleeping) (?:till|until) (?:dawn|morning)|'
  r'through the night (?:till|until|to) (?:dawn|morning))\b',
  caseSensitive: false,
);

final _nightSkip = RegExp(
  r'\b(?:'
  r'(?:sleep|slept|sleeping) through (?:the )?night|'
  r'(?:sleep|slept|sleeping) through (?:till|until|to) (?:dawn|morning)|'
  r'(?:sleep|slept|sleeping) (?:till|until) (?:dawn|morning)|'
  r'through the night (?:till|until|to) (?:dawn|morning)|'
  r'next morning|the following morning|wake up|woke up|overnight|'
  r'the next day|the following day'
  r')\b',
  caseSensitive: false,
);

final _oocMarker = RegExp(
  r'\(ooc[:\s]|\[ooc|\*ooc\b|ooc:',
  caseSensitive: false,
);

final _durationHint = RegExp(
  r'\b(an? hour|half an hour|\d+\s*(minutes?|hours?|days?|weeks?)|'
  r'a while|some ?time|later|skip|fast.?forward|advance|pass(es|ing)?)\b',
  caseSensitive: false,
);

bool hasSkipPhrase(String lower) => _skipPhrase.hasMatch(lower);

/// Clock lands at next morning AND the body may restore. Not "hours later".
bool isNightSkip(String lower) => _nightSkip.hasMatch(lower);

/// Same gate detectOocTimeSkip used: a skip phrase, or OOC plus a duration.
bool shouldDetectTimeSkip(String lower) {
  final skip = hasSkipPhrase(lower);
  if (skip) return true;
  if (!_oocMarker.hasMatch(lower)) return false;
  return _durationHint.hasMatch(lower);
}

