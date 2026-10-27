// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The skip reader's answers for scripted LLMs. A line that talks about time
// costs one reader call before the reply; suites that send a skip line give
// the reader a fixed reading here, so they test what the clock, the bodies
// and the bridge do with a reading, not the reading itself (the live phrase
// test, skip_reader_live_test.dart, asks a real model).

/// Words only the skip reader's prompt carries.
const String kSkipReaderMark = 'You keep the story clock for a roleplay';

const String kNoSkipReading =
    '{"skip": false, "minutes": 0, "until": "", "gap": "none"}';

String skipReading(int minutes, {String until = '', bool slept = false}) =>
    '{"skip": true, "minutes": $minutes, "until": "$until", '
    '"gap": "${slept ? 'slept' : 'other'}"}';

/// What a model reads in the skip lines the suites send, by a lower-case
/// piece of the line.
final Map<String, String> kSuiteSkipReadings = {
  'two weeks later': skipReading(14 * 24 * 60),
  'three weeks pass': skipReading(21 * 24 * 60),
  'a few days later': skipReading(3 * 24 * 60),
  'two days later': skipReading(2 * 24 * 60),
  'next morning': skipReading(0, until: 'morning', slept: true),
  'six hours pass': skipReading(6 * 60),
  'two hours later': skipReading(2 * 60),
  'skip ahead two hours': skipReading(2 * 60),
};

/// The player's line in a skip-reader [prompt], or null for any other
/// prompt.
String? skipReaderLine(String prompt) {
  if (!prompt.contains(kSkipReaderMark)) return null;
  const head = 'The player just wrote:\n';
  final start = prompt.indexOf(head);
  if (start < 0) return '';
  final rest = prompt.substring(start + head.length);
  final end = rest.indexOf('\n\nDoes this line');
  return end < 0 ? rest : rest.substring(0, end);
}

/// The reader's answer to [prompt], or null when [prompt] is not the
/// reader's. The first of [readings] the line holds, else no skip.
String? skipReaderReply(String prompt, {Map<String, String>? readings}) {
  final line = skipReaderLine(prompt)?.toLowerCase();
  if (line == null) return null;
  for (final MapEntry(:key, :value)
      in (readings ?? kSuiteSkipReadings).entries) {
    if (line.contains(key)) return value;
  }
  return kNoSkipReading;
}
