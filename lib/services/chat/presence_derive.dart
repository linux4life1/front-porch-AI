// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// At work is occupation + hours + the clock. Fail closed on hours.
// With you / Away is last. Never a yes/no switch.

import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/character_state/presence_word.dart';

/// Group copies often drop occupation/hours (fromJson only reads
/// realism_engine.*). Blank copy fields fall back to the origin library card.
({String occupation, String hours}) workFieldsForGroupMember({
  required String copyOccupation,
  required String copyHours,
  String? libraryOccupation,
  String? libraryHours,
}) {
  final occ = copyOccupation.trim();
  final hrs = copyHours.trim();
  return (
    occupation: occ.isNotEmpty ? occ : (libraryOccupation ?? '').trim(),
    hours: hrs.isNotEmpty ? hrs : (libraryHours ?? '').trim(),
  );
}

/// Derive the glance word.
///
/// Order: at work (occupation + hours match the period) → Away (not
/// in this scene) → With you. 1:1 may be Away or At work. Skip is
/// group-only. [inScene] fails toward true.
PresenceWhere derivePresence({
  required String occupation,
  required String hours,
  required String timeOfDay,
  required bool inScene,
}) {
  if (occupation.trim().isNotEmpty &&
      hours.trim().isNotEmpty &&
      hoursMatch(hours, timeOfDay)) {
    return PresenceWhere.atWork;
  }
  if (!inScene) return PresenceWhere.away;
  return PresenceWhere.withYou;
}

/// Group Away / At work: no user-action reply. Clock still runs.
/// 1:1 never uses this — they stay in the turn.
bool groupTurnSkips(PresenceWhere where) =>
    where == PresenceWhere.away || where == PresenceWhere.atWork;

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

/// Fail-closed: period words, or a parseable h-h / hh:mm–hh:mm range
/// that contains the period's default hour. Unparseable → false.
bool hoursMatch(String hours, String timeOfDay) {
  final h = hours.toLowerCase().trim();
  if (h.isEmpty) return false;
  if (_periodWordMatch(h, timeOfDay)) return true;
  final range = _parseHoursRange(h);
  if (range == null) return false;
  final hour = StoryClock.representativeTime(
    DateTime.utc(2000, 1, 1),
    timeOfDay,
  ).hour;
  return _hourInRange(hour, range.$1, range.$2);
}

bool _periodWordMatch(String hours, String timeOfDay) {
  final period = timeOfDay.toLowerCase().trim();
  // late_morning counts as morning for word matching.
  final key = period == 'late_morning' ? 'morning' : period;
  const words = ['dawn', 'morning', 'afternoon', 'evening', 'night'];
  for (final w in words) {
    if (hours.contains(w) && w == key) return true;
  }
  return false;
}

final _rangeRe = RegExp(
  r'(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?'
  r'\s*(?:[-–—]|\s+to\s+)\s*'
  r'(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?',
);

(int, int)? _parseHoursRange(String hours) {
  final m = _rangeRe.firstMatch(hours);
  if (m == null) return null;
  final start = _toHour(int.tryParse(m.group(1) ?? ''), m.group(3));
  final end = _toHour(int.tryParse(m.group(4) ?? ''), m.group(6));
  if (start == null || end == null) return null;
  var s = start;
  var e = end;
  final startAmPm = m.group(3);
  final endAmPm = m.group(6);
  // 9-5 → 9-17. Overnight 22-6 stays a wrap.
  if (startAmPm == null && endAmPm == null && e <= s && e <= 12 && s <= 12) {
    e += 12;
  }
  return (s, e);
}

int? _toHour(int? h, String? ampm) {
  if (h == null || h < 0 || h > 24) return null;
  if (h == 24) return 0;
  if (ampm == null) return h > 23 ? null : h;
  final pm = ampm.startsWith('p');
  if (h == 12) return pm ? 12 : 0;
  if (h > 12) return null;
  return pm ? h + 12 : h;
}

bool _hourInRange(int hour, int start, int end) {
  if (start == end) return hour == start;
  if (start < end) return hour >= start && hour < end;
  return hour >= start || hour < end;
}
