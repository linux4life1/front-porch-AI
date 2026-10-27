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
import 'package:front_porch_ai/services/chat/story_clock.dart';

/// Marks a narrator card the time-skip bridge wrote (beside the director
/// narration marker, so it renders and reads as narration everywhere).
const String kTimeSkipBridgeMeta = 'is_time_skip_bridge';

/// How much of each card's description the bridge narrator reads.
const int kBridgeCastNoteChars = 240;

/// "8 hours", "3 days", "2 weeks", "4 months", "a year": the span in the
/// words a narrator would use.
String skipSpanWords(int minutes) {
  if (minutes < 23 * 60) {
    final hours = (minutes / 60).round();
    return hours <= 1 ? 'an hour' : '$hours hours';
  }
  final days = (minutes / (24 * 60)).round();
  String unit(int n, String one) => n == 1 ? 'a $one' : '$n ${one}s';
  if (days < 14) return unit(days < 1 ? 1 : days, 'day');
  if (days < 60) return unit((days / 7).round(), 'week');
  if (days < 730) return unit((days / 30.44).round(), 'month');
  return unit((days / 365.25).round(), 'year');
}

/// "Tue, Mar 3, night": one story moment as the anchor and the bridge
/// both name it, so the two never describe the same skip two ways.
String skipMomentWords(DateTime d) =>
    '${StoryClock.formatShortDate(d)}, '
    '${StoryClock.periodForHour(d.hour).replaceAll('_', ' ')}';

final _lastComma = RegExp(r', (?=[^,]*$)');

/// What the narrator knows beyond the last raw lines. An empty field drops
/// its line from the prompt.
class TimeSkipBridgeContext {
  const TimeSkipBridgeContext({
    this.castNotes = const [],
    this.place = '',
    this.recap = '',
    this.openThreads = const [],
  });

  /// One line per cast member, from [bridgeCastNote].
  final List<String> castNotes;
  final String place;
  final String recap;
  final List<String> openThreads;
}

/// "Mae (close friends with Sam): a carpenter who…" — the card's own short
/// description, clipped, plus the bond with the user when one is tracked.
String bridgeCastNote(CharacterCard card, {String tone = ''}) {
  var about = card.description.trim();
  if (about.isEmpty) about = card.personality.trim();
  about = about.replaceAll(RegExp(r'\s+'), ' ');
  if (about.length > kBridgeCastNoteChars) {
    about = '${about.substring(0, kBridgeCastNoteChars).trimRight()}…';
  }
  final bond = tone.trim().isEmpty ? '' : ' (${tone.trim()})';
  return about.isEmpty ? '${card.name}$bond' : '${card.name}$bond: $about';
}

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
  TimeSkipBridgeContext context = const TimeSkipBridgeContext(),
}) {
  final span = skipSpanWords(minutes);
  final most = (minutes / (24 * 60)).round() >= 14 ? 'six' : 'five';
  final place = context.place.trim();
  final recap = context.recap.trim();
  final b = StringBuffer(
    'You are the narrator of a roleplay scene. The characters are '
    '${[...castNames, userName].join(', ').replaceFirst(_lastComma, ' and ')}.'
    '\n\n',
  );
  if (context.castNotes.isNotEmpty) {
    b.write('Who they are:\n');
    for (final note in context.castNotes) {
      b.write('- $note\n');
    }
    b.write('\n');
  }
  if (recap.isNotEmpty) b.write('The story so far: $recap\n\n');
  b.write('Recent scene:\n${recentLines.join('\n')}\n\n');
  if (place.isNotEmpty) b.write('Where the scene was: $place\n');
  if (context.openThreads.isNotEmpty) {
    b.write('Left open: ${context.openThreads.join('; ')}\n');
  }
  if (place.isNotEmpty || context.openThreads.isNotEmpty) b.write('\n');
  b.write(
    'The story now skips ahead $span, from $from to $to. '
    '$userName moved it on with: ${skipLine.trim()}\n\n'
    'Write ONE short bridge of three to $most sentences, in the third person '
    'and the past tense, about how those $span went. $userName\'s line is '
    'what they want: if it names a place, a time of day or something that '
    'happened, the bridge agrees with it and ends there. Carry the loose ends '
    'of the scene above forward plausibly (how a quarrel cooled, whether a '
    'plan got done or not), and give each character the ordinary days '
    'someone like them would have lived: their work, their habits, the '
    'people around them. Call the span "$span" and do not name a longer one '
    'or a different weekday. Stay consistent with the story so far and do '
    'not invent big events. Keep what $userName did vague and do not decide '
    'anything important for them. End by setting the new moment at $to, in '
    'its setting, so the next reply can pick up from there. Do NOT write any '
    'dialogue. Reply with the narration only, no label and no quotes.',
  );
  return b.toString();
}

const _countWords = {
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

const _unitMinutes = {
  'day': 24 * 60,
  'week': 7 * 24 * 60,
  'month': 30 * 24 * 60,
  'year': 365 * 24 * 60,
};

final _namedSpan = RegExp(
  r'\b(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|'
  r'twelve)\s+(day|week|month|year)s?\s+'
  r'(later|on|passed|had passed|went by|had gone by|slipped by)\b',
  caseSensitive: false,
);

/// True when [bridge] says more time went by than the clock moved
/// ([minutes]): "a month later" on a two-week skip. A shorter span inside
/// the gap ("a week later the porch was done") is fine.
bool bridgeOverstatesSpan(String bridge, int minutes) {
  for (final m in _namedSpan.allMatches(bridge)) {
    final word = m.group(1)!.toLowerCase();
    final n = int.tryParse(word) ?? _countWords[word] ?? 1;
    final named = n * _unitMinutes[m.group(2)!.toLowerCase()]!;
    if (named > minutes * 3 ~/ 2) return true;
  }
  return false;
}

/// A narrator card the time-skip bridge wrote.
bool isTimeSkipBridge(ChatMessage m) =>
    m.activeMetadata?[kTimeSkipBridgeMeta] == true;

/// Prompt order for history lines. A bridge card is stored before the
/// user's skip line (the passes that look for the user's turn need that),
/// but reads after it: the skip, then the gap, then the reply. [lines] runs
/// parallel to [messages].
List<String> bridgesAfterSkipLines(
  List<ChatMessage> messages,
  List<String> lines,
) {
  final out = [...lines];
  for (var i = 0; i + 1 < messages.length && i + 1 < out.length; i++) {
    final next = messages[i + 1];
    if (!isTimeSkipBridge(messages[i]) ||
        !next.isUser ||
        next.isDirectorNarration) {
      continue;
    }
    final bridge = out[i];
    out[i] = out[i + 1];
    out[i + 1] = bridge;
    i++;
  }
  return out;
}

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
