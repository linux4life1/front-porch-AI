// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The time-skip bridge: when a message skips a day or more, a narrator card
// fills in the gap between the last scene and the new moment, then the
// character replies. Without it a "two weeks later" landed the reply in the
// same room, mood and posture the scene left, with nothing said about the
// days in between.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/director/director_note.dart';

/// Marks a narrator card the time-skip bridge wrote (beside the director
/// narration marker, so it renders and reads as narration everywhere).
const String kTimeSkipBridgeMeta = 'is_time_skip_bridge';

/// "3 days", "2 weeks", "4 months", "a year": the span in the words a
/// narrator would use.
String skipSpanWords(int minutes) {
  final days = (minutes / (24 * 60)).round();
  String unit(int n, String one) => n == 1 ? 'a $one' : '$n ${one}s';
  if (days < 14) return unit(days < 1 ? 1 : days, 'day');
  if (days < 60) return unit((days / 7).round(), 'week');
  if (days < 730) return unit((days / 30.44).round(), 'month');
  return unit((days / 365.25).round(), 'year');
}

final _lastComma = RegExp(r', (?=[^,]*$)');

/// The bridge narrator's prompt. [skipLine] is the user's message that
/// skipped; [from] and [to] are the story moments either side of the gap.
String timeSkipBridgePrompt({
  required List<String> recentLines,
  required List<String> castNames,
  required String userName,
  required String skipLine,
  required String from,
  required String to,
  required int minutes,
}) =>
    'You are the narrator of a roleplay scene. The characters are '
    '${[...castNames, userName].join(', ').replaceFirst(_lastComma, ' and ')}.'
    '\n\n'
    'Recent scene:\n${recentLines.join('\n')}\n\n'
    'The story now skips ahead ${skipSpanWords(minutes)}, from $from to $to. '
    '$userName moved it on with: ${skipLine.trim()}\n\n'
    'Write ONE short bridge of three to five sentences, in the third person '
    'and the past tense, about how those ${skipSpanWords(minutes)} went: the '
    'days passing, the ordinary life in between, and anything the scene '
    'above left unresolved settling or carrying on. Stay consistent with '
    'the story so far and do not invent big events. Keep what $userName did '
    'vague and do not decide anything important for them. End by setting '
    'the new moment at $to, where the next scene begins. Do NOT write any '
    'dialogue. Reply with the narration only, no label and no quotes.';

/// The bridge as it lands in the transcript: a narrator card, so Journal,
/// Growth, stats and impersonation skip it the way they skip `/narrate`,
/// and the reply reads it as `[Narration: …]`.
ChatMessage timeSkipBridgeMessage(String text) => ChatMessage(
  text: text,
  sender: 'Narrator',
  isUser: true,
  characterId: kDirectorCharacterId,
  metadata: {kDirectorNarrationMeta: true, kTimeSkipBridgeMeta: true},
);
