// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wide net in front of the skip reader. It only decides whether a
// line is worth one model call, so it errs wide on purpose: a false alarm
// costs a call that answers "no skip", and the reader, not this list,
// decides what the line means. Do not grow it into a parser.

import 'package:front_porch_ai/utils/utils.dart' show stripQuotedSpeech;

const String _part =
    r'(?:dawn|morning|late\s+morning|noon|midday|afternoon|evening|dusk|'
    r'night|midnight|day|week|month|year)';

final RegExp _timeish = RegExp(
  r'\b(?:'
  // A span of time: "8 hours", "a few days", "weeks later".
  r'(?:min|mins|minutes?|hours?|hrs?|days|nights|weeks?|fortnights?|'
  r'months?|years?|decades?)|'
  // Asked for: "time skip", "fast forward", "skip ahead", "later".
  r'skip\w*|fast.?forward\w*|later|time\s+pass\w*|some\s+time|'
  // A night: "we sleep", "slept", "woke up", "overnight".
  r'sleep\w*|slept|asleep|naps?|napp\w+|wake|wakes|woke|waking|'
  r'awaken\w*|overnight|bedtime|tomorrow|dawn|daybreak|sunrise|'
  // Where it lands: "the next morning", "until evening", "by noon".
  r'(?:next|following|until|till|by|to|in\s+the)\s+(?:the\s+)?'
  '$_part'
  r')\b',
  caseSensitive: false,
);

final RegExp _clockTime = RegExp(
  r'\b\d{1,2}(?::\d{2})\s*(?:am|pm)?\b|\b\d{1,2}\s*(?:am|pm)\b',
  caseSensitive: false,
);

/// True when [line] says anything about time outside quoted speech.
bool mightSkipTime(String line) {
  final narration = stripQuotedSpeech(line);
  return _timeish.hasMatch(narration) || _clockTime.hasMatch(narration);
}
