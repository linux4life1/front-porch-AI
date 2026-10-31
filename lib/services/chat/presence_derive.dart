// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// At work is occupation + hours + weekday + the clock. Fail closed on
// hours. Missing workDays is Mon–Fri. Written [] is never at work.
// With you / Away is last. Never a yes/no switch.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/member_origin_resolver.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';
export 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart'
    show PresenceWhere;

/// DateTime.weekday values (1=Mon … 7=Sun). Missing card field resolves here.
const List<int> kDefaultWorkDays = [
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
];

/// Missing/null → Mon–Fri. Written [] stays empty (never at work).
List<int> resolveWorkDays(List<int>? workDays) {
  if (workDays == null) return List<int>.from(kDefaultWorkDays);
  return sanitizeWorkDays(workDays);
}

/// Ints 1–7 only, unique, sorted. Junk dropped.
List<int> sanitizeWorkDays(Iterable<Object?> raw) {
  final days = <int>{};
  for (final e in raw) {
    final n = e is int
        ? e
        : e is num
        ? e.toInt()
        : e is String
        ? int.tryParse(e.trim())
        : null;
    if (n != null && n >= DateTime.monday && n <= DateTime.sunday) {
      days.add(n);
    }
  }
  final list = days.toList()..sort();
  return list;
}

/// Card JSON: key missing → null (Mon–Fri at derive). `[]` → never at work.
/// Present but all junk → null, not an accidental empty week.
List<int>? parseWorkDaysField(Object? raw, {required bool present}) {
  if (!present) return null;
  if (raw is! List) return null;
  if (raw.isEmpty) return const [];
  final out = sanitizeWorkDays(raw);
  return out.isEmpty ? null : out;
}

/// Group copies often drop occupation/hours/brief (fromJson only reads
/// realism_engine.*). Blank copy fields fall back to the origin library card.
({String occupation, String hours, String occupationBrief, List<int>? workDays})
workFieldsForGroupMember({
  required String copyOccupation,
  required String copyHours,
  String copyOccupationBrief = '',
  List<int>? copyWorkDays,
  String? libraryOccupation,
  String? libraryHours,
  String? libraryOccupationBrief,
  List<int>? libraryWorkDays,
}) {
  final occ = copyOccupation.trim();
  final hrs = copyHours.trim();
  final brief = copyOccupationBrief.trim();
  return (
    occupation: occ.isNotEmpty ? occ : (libraryOccupation ?? '').trim(),
    hours: hrs.isNotEmpty ? hrs : (libraryHours ?? '').trim(),
    occupationBrief: brief.isNotEmpty
        ? brief
        : (libraryOccupationBrief ?? '').trim(),
    workDays: copyWorkDays ?? (hrs.isNotEmpty ? null : libraryWorkDays),
  );
}

/// [member]'s work fields, the one read behind the member card's "at work"
/// word, the turn skip, the web cast and the prompt, so they cannot disagree.
/// The member's own copy first; blank fields fall back to the library card
/// [MemberOriginResolver.resolveForCard] finds (identity first, a name only
/// when exactly one library card has it). Two members who share a name, or a
/// renamed one, are never matched to a library card by name alone.
({String occupation, String hours, String occupationBrief, List<int>? workDays})
workFieldsForMember(CharacterCard member, Iterable<CharacterCard> library) {
  final ext = member.frontPorchExtensions;
  final origin = MemberOriginResolver.resolveForCard(
    member,
    library,
  )?.frontPorchExtensions;
  return workFieldsForGroupMember(
    copyOccupation: ext?.occupation ?? '',
    copyHours: ext?.hours ?? '',
    copyOccupationBrief: ext?.occupationBrief ?? '',
    copyWorkDays: ext?.workDays,
    libraryOccupation: origin?.occupation,
    libraryHours: origin?.hours,
    libraryOccupationBrief: origin?.occupationBrief,
    libraryWorkDays: origin?.workDays,
  );
}

/// Derive the glance word.
///
/// Order: at work (occupation + hours + weekday contain the live clock)
/// → Away (not in this scene) → With you. 1:1 may be Away or At work.
/// Skip is group-only. [inScene] fails toward true. Missing [workDays]
/// is Mon–Fri.
PresenceWhere derivePresence({
  required String occupation,
  required String hours,
  required int clockMinutes,
  required bool inScene,
  required int weekday,
  List<int>? workDays,
}) {
  if (occupation.trim().isNotEmpty &&
      hours.trim().isNotEmpty &&
      onShift(
        hours: hours,
        clockMinutes: clockMinutes,
        weekday: weekday,
        workDays: workDays,
      )) {
    return PresenceWhere.atWork;
  }
  if (!inScene) return PresenceWhere.away;
  return PresenceWhere.withYou;
}

/// Group Away / At work: no user-action reply. Clock still runs.
/// 1:1 never uses this — they stay in the turn.
bool groupTurnSkips(PresenceWhere where) =>
    where == PresenceWhere.away || where == PresenceWhere.atWork;

String presenceGlanceLabel(PresenceWhere where) => switch (where) {
  PresenceWhere.withYou => 'With you',
  PresenceWhere.away => 'Away',
  PresenceWhere.atWork => 'At work',
};

/// At-work prompt line. Title stays `as a $occupation`. [occupationBrief]
/// is its own sentence — never stuffed into the title. Empty brief is
/// today's line. Do not invent the job from the title.
String atWorkPromptLine({
  required String occupation,
  String occupationBrief = '',
}) {
  final job = occupation.trim();
  final brief = occupationBrief.trim();
  final head = 'At work${job.isEmpty ? '' : ' as a $job'}.';
  if (brief.isEmpty) return '$head Write from there.';
  final duties = brief.endsWith('.') ? brief : '$brief.';
  return '$head $duties Write from there.';
}

/// Off-shift identity only. Never stages the workplace.
///
/// When they have hours/days, say **why** they are not at work — a Sunday
/// loan officer must not be invented onto a shift. Day-off / not-yet /
/// already-done is the last sentence so it wins over the job title.
String offShiftWorkIdentityLine({
  required String occupation,
  String occupationBrief = '',
  String hours = '',
  int weekday = DateTime.tuesday,
  List<int>? workDays,
  int clockMinutes = 0,
}) {
  final job = occupation.trim();
  final brief = occupationBrief.trim();
  if (job.isEmpty && brief.isEmpty) return '';
  final duties = brief.isEmpty ? '' : (brief.endsWith('.') ? brief : '$brief.');
  final head = job.isEmpty
      ? duties
      : 'Works as a $job.${duties.isEmpty ? '' : ' $duties'}';
  final why = _offShiftWhy(
    hours: hours,
    weekday: weekday,
    workDays: workDays,
    clockMinutes: clockMinutes,
  );
  if (why.isEmpty) return head;
  return '$head $why';
}

String _offShiftWhy({
  required String hours,
  required int weekday,
  List<int>? workDays,
  required int clockMinutes,
}) {
  if (hours.trim().isEmpty) return '';
  final days = resolveWorkDays(workDays);
  final dayName = _weekdayWord(weekday);
  if (days.isNotEmpty && !days.contains(weekday)) {
    return 'Today is $dayName — not a work day. Do not send them to work.';
  }
  final range = parseWorkHoursRange(hours);
  if (range == null) return '';
  if (clockMinutes < range.$1) {
    return 'Shift starts at ${_clockWord(range.$1)} — not at work yet.';
  }
  return 'Off the clock. Do not send them to work.';
}

String _weekdayWord(int weekday) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (weekday < 1 || weekday > 7) return 'today';
  return names[weekday - 1];
}

String _clockWord(int minutes) => _fmtMin(minutes);

/// Judge bit wins when present. Else the stance keyword sniff.
/// Missing [withUser] fails toward [inScene] / keyword so old chats
/// keep today's glance.
bool inSceneForPresence({
  required String stance,
  bool? withUser,
  bool inScene = true,
}) {
  if (withUser != null) return withUser;
  if (stanceSaysAway(stance)) return false;
  return inScene;
}

/// Empty stance fails toward in-scene. Away-words mean they left.
bool stanceSaysAway(String spatialStance) {
  final s = spatialStance.toLowerCase().trim();
  if (s.isEmpty) return false;
  const marks = [
    'left the',
    'has left',
    'walked off',
    'walked away',
    'gone from',
    'not here',
    'elsewhere',
    'in another',
    'next room',
    'other room',
    'down the hall',
    'out of the room',
    'out of sight',
  ];
  return marks.any(s.contains);
}

/// Fail-closed: a parseable clock range that contains [clockMinutes]
/// (minutes from midnight on the live story clock). Period words
/// ("mornings") and other free text are not hours — they return false.
bool hoursMatch(String hours, int clockMinutes) {
  final range = parseWorkHoursRange(hours);
  if (range == null) return false;
  return _minutesInRange(clockMinutes, range.$1, range.$2);
}

/// Hours plus weekday. Overnight hours after midnight belong to
/// yesterday's shift, so a Friday 10pm–2am bartender is still at work
/// Saturday 1am, and a Saturday-only night shift is not.
bool onShift({
  required String hours,
  required int clockMinutes,
  required int weekday,
  List<int>? workDays,
}) {
  final range = parseWorkHoursRange(hours);
  if (range == null) return false;
  final days = resolveWorkDays(workDays);
  if (days.isEmpty) return false;
  final start = range.$1;
  final end = range.$2;
  final overnightEarly = start > end && clockMinutes < end;
  final day = overnightEarly
      ? (weekday == DateTime.monday ? DateTime.sunday : weekday - 1)
      : weekday;
  return days.contains(day) && _minutesInRange(clockMinutes, start, end);
}

final _rangeRe = RegExp(
  r'(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?'
  r'\s*(?:[-–—]|\s+to\s+)\s*'
  r'(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?',
);

/// Start/end as minutes from midnight. Null for empty, period words
/// ("mornings"), or anything else that is not a clock range.
(int, int)? parseWorkHoursRange(String hours) {
  final h = hours.toLowerCase().trim();
  if (h.isEmpty) return null;
  final m = _rangeRe.firstMatch(h);
  if (m == null) return null;
  final start = _toMinutes(
    int.tryParse(m.group(1) ?? ''),
    m.group(2),
    m.group(3),
  );
  final end = _toMinutes(
    int.tryParse(m.group(4) ?? ''),
    m.group(5),
    m.group(6),
  );
  if (start == null || end == null) return null;
  var s = start;
  var e = end;
  // 9-5 → 9:00–17:00. Overnight 22-6 stays a wrap.
  if (m.group(3) == null &&
      m.group(6) == null &&
      e <= s &&
      (e ~/ 60) <= 12 &&
      (s ~/ 60) <= 12) {
    e += 12 * 60;
  }
  return (s, e);
}

/// Card `hours` from two minute-of-day values: "9am–5pm" / "9:30am–5:15pm".
/// The pickers write this; [parseWorkHoursRange] reads it back.
String formatWorkHoursRange(int startMin, int endMin) =>
    '${_fmtMin(startMin)}–${_fmtMin(endMin)}';

int? _toMinutes(int? h, String? minuteStr, String? ampm) {
  if (h == null || h < 0 || h > 24) return null;
  if (h == 24) {
    if (minuteStr != null && minuteStr != '00') return null;
    return 0;
  }
  final minute = minuteStr == null || minuteStr.isEmpty
      ? 0
      : int.tryParse(minuteStr);
  if (minute == null || minute < 0 || minute > 59) return null;
  var hour = h;
  if (ampm != null) {
    final pm = ampm.startsWith('p');
    if (h == 12) {
      hour = pm ? 12 : 0;
    } else if (h > 12) {
      return null;
    } else {
      hour = pm ? h + 12 : h;
    }
  } else if (h > 23) {
    return null;
  }
  return hour * 60 + minute;
}

String _fmtMin(int minutes) {
  final clamped = ((minutes % 1440) + 1440) % 1440;
  final h = clamped ~/ 60;
  final m = clamped % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final suffix = h < 12 ? 'am' : 'pm';
  if (m == 0) return '$h12$suffix';
  return '$h12:${m.toString().padLeft(2, '0')}$suffix';
}

bool _minutesInRange(int minutes, int start, int end) {
  if (start == end) return minutes == start;
  if (start < end) return minutes >= start && minutes < end;
  return minutes >= start || minutes < end;
}
