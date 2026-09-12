// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure: pull a PRESENT story-clock time out of a reply. Used after
// generation so the sidebar matches what they just said (the Senjumaru
// 8:05-vs-6am class). Think-blocks are stripped — those quote the
// injection, not the fiction.

/// How far a named time may sit from the live clock before we refuse it.
/// 8:05 AM vs "six in the morning" is ~2h; a 2pm scene saying "midnight"
/// is a different day and stays put.
const int kNamedClockMaxDeltaHours = 6;

const Map<String, int> _kSpokenHour = {
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

/// If [reply] names a present wall-clock time close to [current], return
/// that instant on the story calendar. Null = no claim, or too far to trust.
DateTime? clockNamedInReply(String reply, DateTime current) {
  final text = _stripThink(reply);
  if (text.isEmpty) return null;

  final claims = <({int hour, int minute, int index})>[];

  for (final m in _ampm.allMatches(text)) {
    if (_boundIsNotPresent(text, m.start)) continue;
    final hourRaw = int.tryParse(m.group(1)!);
    if (hourRaw == null || hourRaw < 1 || hourRaw > 12) continue;
    final minute = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (minute > 59) continue;
    final pm = m.group(3)!.toLowerCase().startsWith('p');
    claims.add((hour: _to24(hourRaw, pm: pm), minute: minute, index: m.start));
  }

  for (final m in _spokenInPeriod.allMatches(text)) {
    if (_boundIsNotPresent(text, m.start)) continue;
    final hourRaw =
        int.tryParse(m.group(1) ?? '') ??
        _kSpokenHour[m.group(2)!.toLowerCase()];
    if (hourRaw == null || hourRaw < 1 || hourRaw > 12) continue;
    final minute = int.tryParse(m.group(3) ?? '0') ?? 0;
    if (minute > 59) continue;
    final period = m.group(4)!.toLowerCase();
    claims.add((
      hour: _hourInPeriod(hourRaw, period),
      minute: minute,
      index: m.start,
    ));
  }

  if (claims.isEmpty) {
    final dawn = _bareDawn.firstMatch(text);
    if (dawn != null && !_boundIsNotPresent(text, dawn.start)) {
      return _namedTimeToday(current, 6, 0);
    }
    return null;
  }

  claims.sort((a, b) => a.index.compareTo(b.index));
  final last = claims.last;
  return _namedTimeToday(current, last.hour, last.minute);
}

final _ampm = RegExp(
  r"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)\b",
  caseSensitive: false,
);

final _spokenInPeriod = RegExp(
  r"\b(?:at|it's|it is|now)\s+"
  r"(?:(\d{1,2})|(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve))"
  r"(?::(\d{2}))?\s+in the (morning|afternoon|evening|night)\b",
  caseSensitive: false,
);

final _bareDawn = RegExp(
  r"\b(?:at|it's|it is|in the)\s+dawn\b",
  caseSensitive: false,
);

/// Leads that mean the named hour is an appointment, a plan or a memory —
/// NOT the present moment. "at" is the one that mattered: "I'll pick you up
/// at 5 p.m." / "they remembered the call at 9 a.m." were read as clock claims
/// and teleported the story clock up to ±6h off one line of ordinary
/// dialogue. The `(?:^|\W)` boundary is load-bearing, not tidiness: without
/// it "footpath " ends in "at " and would reject the very Senjumaru
/// "at six in the morning" claim this file was written for.
final _notPresent = RegExp(
  // `was`/`were` (1.3 sweep, independent review): "It was 5 a.m. when we
  // left" is a memory, not the present moment — it teleported the clock just
  // like the appointment leads did.
  r'(?:^|\W)(until|by|before|after|past|around|about|tomorrow|tonight|'
  r'another|for|in|at|till|til|since|from|toward|towards|was|were)\s+$',
  caseSensitive: false,
);

bool _boundIsNotPresent(String text, int start) {
  final lead = text.substring(start > 24 ? start - 24 : 0, start);
  if (_notPresent.hasMatch(lead)) return true;
  final trimmed = lead.trimRight().toLowerCase();
  if (trimmed.endsWith('it is')) return false;
  return trimmed.endsWith(' is') || trimmed.endsWith("'s");
}

int _to24(int hour12, {required bool pm}) {
  if (hour12 == 12) return pm ? 12 : 0;
  return pm ? hour12 + 12 : hour12;
}

int _hourInPeriod(int hour12, String period) {
  return switch (period) {
    'afternoon' || 'evening' => hour12 == 12 ? 12 : hour12 + 12,
    'night' =>
      hour12 >= 6 && hour12 < 12 ? hour12 + 12 : (hour12 == 12 ? 0 : hour12),
    _ => hour12 == 12 ? 0 : hour12,
  };
}

/// The named hour placed on the CURRENT story day only. Neighbouring days
/// are deliberately not candidates: a 12:45 AM scene whose reply says
/// "11 p.m." would otherwise be pulled back onto yesterday, dropping the
/// sidebar's Day N by one (and re-firing the day rollover when the next
/// turn crosses midnight again). A claim that only fits another calendar
/// day stays put — same rule the 6h window states for a 2pm/midnight reply.
DateTime? _namedTimeToday(DateTime current, int hour, int minute) {
  final today = DateTime.utc(
    current.year,
    current.month,
    current.day,
    hour,
    minute,
  );
  final abs = today.difference(current).inMinutes.abs();
  if (abs > kNamedClockMaxDeltaHours * 60) return null;
  if (abs == 0) return null; // already agrees
  return today;
}

String _stripThink(String raw) => raw.replaceAll(
  RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
  '',
);
