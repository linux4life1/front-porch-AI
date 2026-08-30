// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Off-stage residue: a specific crumb when they leave a shift, and a rare
// permission to speak an old one. Not Chance Time. Not a daily summary.
// Journal cards of kind `episode` are the deck. Pure helpers, no I/O.

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';

/// About one in four clock-outs mints a crumb. Most shifts leave nothing.
const int kWorkCrumbEvery = 4;

/// About one in eight rhyming turns may speak an old crumb.
const int kSpeechImpulseEvery = 8;

/// Job-shaped first-person lines. `{brief}` is the authored "what the job
/// is" — never invent duties; that template is skipped when brief is empty.
const List<String> kWorkCrumbTemplates = [
  'I clocked out with a small argument from {job} still in my teeth.',
  'Someone at {job} used my name wrong and it landed oddly.',
  'I overheard a scrap of talk at {job} that was probably about me.',
  'The last hour at {job} ran long for no good reason.',
  'Something small went right at {job} and I am still a bit lit by it.',
  'A thankless {job} mess stuck to me after I left.',
  'I left {job} still turning over this: {brief}.',
];

/// They were on shift at [before] and the jump is longer than what remained
/// of that shift — so they clocked out even if they landed in a later one.
bool clockedOutOfShift({
  required String occupation,
  required String hours,
  List<int>? workDays,
  required DateTime before,
  required DateTime after,
}) {
  if (occupation.trim().isEmpty || hours.trim().isEmpty) return false;
  final elapsed = after.difference(before).inMinutes;
  if (elapsed <= 0) return false;
  final beforeMin = before.hour * 60 + before.minute;
  if (!onShift(
    hours: hours,
    clockMinutes: beforeMin,
    weekday: before.weekday,
    workDays: workDays,
  )) {
    return false;
  }
  final left = minutesLeftOnShift(beforeMin, hours);
  if (left == null || left <= 0) return false;
  return elapsed > left;
}

/// Minutes until this range ends. Null if hours do not parse. 0 if already
/// outside the range.
int? minutesLeftOnShift(int clockMinutes, String hours) {
  final range = parseWorkHoursRange(hours);
  if (range == null) return null;
  final start = range.$1;
  final end = range.$2;
  final on = start == end
      ? clockMinutes == start
      : start < end
      ? clockMinutes >= start && clockMinutes < end
      : clockMinutes >= start || clockMinutes < end;
  if (!on) return 0;
  if (start == end) return 0;
  if (start < end) return end - clockMinutes;
  if (clockMinutes >= start) return (1440 - clockMinutes) + end;
  return end - clockMinutes;
}

bool shouldMintWorkCrumb(int seed) => seed % kWorkCrumbEvery == 0;

/// Stable per session / person / story-day / shift-end, so regen remints
/// the same line instead of a new random life.
int workCrumbSeed({
  required String sessionId,
  required String characterId,
  required int storyDay,
  required int shiftEndMinutes,
}) => Object.hash(sessionId, characterId, storyDay, shiftEndMinutes);

int shiftEndMinutesOf(String hours) {
  final range = parseWorkHoursRange(hours);
  return range?.$2 ?? 0;
}

String workCrumbContent({
  required String occupation,
  required String occupationBrief,
  required int seed,
}) {
  final job = occupation.trim().isEmpty ? 'work' : occupation.trim();
  var brief = occupationBrief.trim();
  if (brief.endsWith('.')) brief = brief.substring(0, brief.length - 1);
  if (brief.length > 80) brief = '${brief.substring(0, 77)}…';
  final pool = [
    for (final t in kWorkCrumbTemplates)
      if (!t.contains('{brief}') || brief.isNotEmpty) t,
  ];
  var line = pool[seed.abs() % pool.length];
  line = line.replaceAll('{job}', job);
  line = line.replaceAll('{brief}', brief.isEmpty ? 'the shift' : brief);
  return line;
}

bool alreadyHasWorkEpisodeToday({
  required List<JournalMemoryData> cards,
  required int storyDay,
}) {
  for (final c in cards) {
    if (!JournalPhysics.isEpisodeCard(c)) continue;
    if (JournalStore.stampOf(c).$1 != storyDay) continue;
    if (JournalPhysics.episodeKindOf(c) == 'work') return true;
  }
  return false;
}

/// Fresh clock-out crumbs may be spoken; older ones only when this turn
/// rhymes and the rare roll hits. One card. Never a catchphrase.
String? speechImpulse({
  required List<JournalMemoryData> injected,
  required String lastWords,
  required int seed,
}) {
  JournalMemoryData? pick;
  for (final c in injected) {
    if (JournalPhysics.isEpisodeCard(c) && c.heat >= 0.99) {
      pick = c;
      break;
    }
  }
  // Birthday heat stays at 1.0 all day (calendar, not a cooling crumb).
  // The 0.99 auto branch would therefore fire EVERY turn. Day-of uses
  // the rare roll only; other days only if the conversation already
  // named the birthday.
  if (pick == null) {
    JournalMemoryData? dayCard;
    for (final c in injected) {
      if (JournalPhysics.isBirthdayCard(c) && c.heat >= 0.99) {
        dayCard = c;
        break;
      }
    }
    if (dayCard != null && seed.abs() % kSpeechImpulseEvery == 0) {
      pick = dayCard;
    }
  }
  if (pick == null) {
    final tokens = itemNameTokens(lastWords);
    if (tokens.isEmpty) return null;
    if (seed.abs() % kSpeechImpulseEvery != 0) return null;
    pick = _bestOverlap(injected, tokens);
  }
  if (pick == null) return null;
  final noList = JournalPhysics.isBirthdayCard(pick)
      ? ' Do not list gifts they want. Do not make the birthday the topic '
            'unless the conversation already touched it or a cake or present '
            'is being handed over.'
      : '';
  return 'On their mind — they may mention this if it fits, and must not '
      'force it or open with a stock phrase: ${pick.content}.$noList';
}

JournalMemoryData? _bestOverlap(
  List<JournalMemoryData> cards,
  Set<String> tokens,
) {
  JournalMemoryData? best;
  var bestN = 0;
  for (final c in cards) {
    final n = itemNameTokens(c.content).intersection(tokens).length;
    if (n > bestN) {
      bestN = n;
      best = c;
    }
  }
  return bestN > 0 ? best : null;
}
