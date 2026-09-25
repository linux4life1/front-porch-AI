// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every bot reply slot carries exactly one clock pair:
// story_clock_before + story_clock_after (after == before when nothing
// ticked), plus chip data. That pair is the only runtime source of
// truth. Legacy snaps / dayCount / timeOfDay are read once, here.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

export 'clock_shift.dart';

/// First known `story_clock_before` on the message or any swipe slot.
String? knownStoryClockBefore(ChatMessage msg) {
  final fromMsg = StoryClock.parse(
    msg.metadata?['story_clock_before'] as String?,
  );
  if (fromMsg != null) return StoryClock.serializeClock(fromMsg);
  for (final slot in msg.swipeMetadata) {
    final parsed = StoryClock.parse(slot?['story_clock_before'] as String?);
    if (parsed != null) return StoryClock.serializeClock(parsed);
  }
  return null;
}

/// Persist [iso] at message level and on every existing swipe slot.
/// Never creates a bare `{story_clock_before}` map — a null slot must
/// keep falling back to [ChatMessage.metadata].
void persistStoryClockBefore(ChatMessage msg, String iso) {
  msg.metadata ??= {};
  msg.metadata!.putIfAbsent('story_clock_before', () => iso);
  for (final slot in msg.swipeMetadata) {
    slot?.putIfAbsent('story_clock_before', () => iso);
  }
}

DateTime? slotClockAfter(Map<String, dynamic>? slot) =>
    StoryClock.parse(slot?['story_clock_after'] as String?);

DateTime? slotClockBefore(Map<String, dynamic>? slot) =>
    StoryClock.parse(slot?['story_clock_before'] as String?);

bool slotHasCompletePair(Map<String, dynamic>? slot) =>
    slotClockBefore(slot) != null && slotClockAfter(slot) != null;

/// Authored clock on this slot — snap, chip, nudge, or a stored day
/// past Day 1. A load-backfill pair painted from the parent live
/// clock is not authored.
bool slotHasAuthoredClock(Map<String, dynamic>? slot) {
  if (_snapStoryClock(slot) != null) return true;
  if ((slot?['time_passed'] as String?)?.isNotEmpty == true) return true;
  if (slot?['time_nudged'] == true) return true;
  if (slot?['clock_from_day_count'] == true) return true;
  final dc = _slotDayCount(slot);
  return dc != null && dc > 1;
}

/// Write the pair (and optional chip / nudge mark) onto [slot].
void writeSlotClockPair(
  Map<String, dynamic> slot, {
  required DateTime before,
  required DateTime after,
  String? timePassed,
  bool clearChip = false,
  bool timeNudged = false,
  bool fromDayCount = false,
}) {
  slot['story_clock_before'] = StoryClock.serializeClock(before);
  slot['story_clock_after'] = StoryClock.serializeClock(after);
  if (clearChip) {
    slot.remove('time_passed');
  } else if (timePassed != null && timePassed.isNotEmpty) {
    slot['time_passed'] = timePassed;
  }
  if (timeNudged) slot['time_nudged'] = true;
  if (fromDayCount) {
    slot['clock_from_day_count'] = true;
  } else {
    slot.remove('clock_from_day_count');
  }
}

/// Greeting-era snap, or a snap that predates this message's before.
bool slotSnapIsFrozen(
  DateTime clock, {
  DateTime? greetingClock,
  DateTime? knownBefore,
}) {
  if (greetingClock != null && clock == greetingClock) return true;
  if (knownBefore != null && clock.isBefore(knownBefore)) return true;
  return false;
}

DateTime? _snapStoryClock(Map<String, dynamic>? slot) {
  final raw = slot?['realism_state'];
  if (raw is! Map) return null;
  return StoryClock.parse(raw['storyClock'] as String?);
}

int? _slotDayCount(Map<String, dynamic>? slot) {
  if (slot == null) return null;
  final rs = slot['realism_state'];
  if (rs is Map && rs['dayCount'] is num) {
    return (rs['dayCount'] as num).toInt();
  }
  final top = slot['story_day'];
  if (top is num) return top.toInt();
  return null;
}

String? _slotTimeOfDay(Map<String, dynamic>? slot) {
  if (slot == null) return null;
  final rs = slot['realism_state'];
  if (rs is Map && rs['timeOfDay'] is String) {
    final tod = rs['timeOfDay'] as String;
    if (tod.isNotEmpty) return tod;
  }
  final top = slot['timeOfDay'] ?? slot['time_of_day'];
  if (top is String && top.isNotEmpty) return top;
  return null;
}

Iterable<Map<String, dynamic>?> _messageSlots(ChatMessage msg) sync* {
  yield msg.metadata;
  for (final slot in msg.swipeMetadata) {
    yield slot;
  }
}

const _kClockBackfillDone = 'clock_backfill_done';

/// v1.4 / stamp-less greeting: later snap was treated as the greeting
/// and the pair was copied from a neighbour. Snap survives; no chip.
bool _shouldRepairWrongGreetingPair(
  Map<String, dynamic>? slot, {
  DateTime? greetingClock,
}) {
  if (greetingClock != null || !slotHasCompletePair(slot)) return false;
  final snap = _snapStoryClock(slot);
  if (snap == null) return false;
  final after = slotClockAfter(slot)!;
  final before = slotClockBefore(slot)!;
  if (after == snap || after == before) return false;
  if ((slot?['time_passed'] as String?)?.isNotEmpty == true) return false;
  if (slot?['time_nudged'] == true) return false;
  if (slot?['clock_from_day_count'] == true) return false;
  final mins = minutesRecordedForClockRewind(slot);
  return mins == null || mins <= 0;
}

bool _firstBotBackfillDone(List<ChatMessage> messages) {
  for (final msg in messages) {
    if (msg.isUser || msg.sender == 'System') continue;
    return msg.metadata?[_kClockBackfillDone] == true;
  }
  return false;
}

void _markClockBackfillDone(List<ChatMessage> messages) {
  for (final msg in messages) {
    if (msg.isUser || msg.sender == 'System') continue;
    msg.metadata ??= {};
    msg.metadata![_kClockBackfillDone] = true;
    return;
  }
}

DateTime _dayCountClock({
  required int dayCount,
  required DateTime startDate,
  String? timeOfDay,
  DateTime? liveClock,
}) {
  final day = dayCount.clamp(1, 9999);
  final date = StoryClock.dateOnly(startDate).add(Duration(days: day - 1));
  if (timeOfDay != null && timeOfDay.isNotEmpty) {
    return StoryClock.representativeTime(date, timeOfDay);
  }
  if (liveClock != null) {
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      liveClock.hour,
      liveClock.minute,
    );
  }
  return StoryClock.representativeTime(date, 'morning');
}

/// Own stored after → non-frozen snap → dayCount>1 → before →
/// [neighbourStamp]. Live only when [isTip] and nothing is stored.
/// History never takes [liveClock] as a first-class fallback.
DateTime? resolveSlotAfter(
  Map<String, dynamic>? slot, {
  required bool isTip,
  required DateTime liveClock,
  DateTime? startDate,
  DateTime? greetingClock,
  DateTime? neighbourStamp,
}) {
  final keptAfter = slotClockAfter(slot);
  if (keptAfter != null) return keptAfter;
  final before = slotClockBefore(slot);
  final snap = _snapStoryClock(slot);
  if (snap != null &&
      !slotSnapIsFrozen(
        snap,
        greetingClock: greetingClock,
        knownBefore: before,
      )) {
    return snap;
  }
  final dc = _slotDayCount(slot);
  if (dc != null && dc > 1) {
    return _dayCountClock(
      dayCount: dc,
      startDate: startDate ?? StoryClock.dateOnly(liveClock),
      timeOfDay: _slotTimeOfDay(slot),
      liveClock: liveClock,
    );
  }
  if (before != null) {
    final mins = minutesRecordedForClockRewind(slot);
    if (mins != null && mins > 0) {
      return before.add(Duration(minutes: mins));
    }
    return before;
  }
  if (neighbourStamp != null) return neighbourStamp;
  if (isTip) return liveClock;
  return null;
}

/// After / non-frozen snap / dayCount>1 / before. Frozen Day-1 snaps
/// are not stored clock data.
bool slotHasStoredClockData(
  Map<String, dynamic>? slot, {
  DateTime? greetingClock,
}) {
  return resolveSlotAfter(
        slot,
        isTip: false,
        liveClock: DateTime.utc(1970),
        greetingClock: greetingClock,
      ) !=
      null;
}

/// Message-level clock view. A guessed backfill pair (after, not authored)
/// is not stored data — [story_day] / snap on [ChatMessage.metadata] still
/// are. Fork and delete resolve this map, then write the visible slot.
Map<String, dynamic>? clockSlotForResolve(ChatMessage msg) {
  final active = msg.activeMetadata;
  if (slotHasAuthoredClock(active)) return active;
  final meta = msg.metadata;
  if (meta != null &&
      (slotHasAuthoredClock(meta) ||
          slotHasStoredClockData(meta) && !slotHasCompletePair(active))) {
    return meta;
  }
  if (slotHasCompletePair(active) && !slotHasAuthoredClock(active)) {
    final copy = Map<String, dynamic>.from(active!);
    copy.remove('story_clock_after');
    copy.remove('story_clock_before');
    if (meta != null) {
      if (meta['story_day'] != null) copy['story_day'] = meta['story_day'];
      if (meta['realism_state'] is Map && copy['realism_state'] is! Map) {
        copy['realism_state'] = meta['realism_state'];
      }
    }
    return copy;
  }
  return active ?? meta;
}

/// Fill missing before/after pairs. The only snap / dayCount reader.
///
/// One resolver for every slot, tip included. Frozen greeting snaps
/// are not a clock. dayCount-only is a clock only when THAT message
/// stored dayCount > 1. Never invents Day 1. [floorUnstampedToDay1]
/// is accepted and does not floor. Never overwrites an existing
/// before or after. Guess runs once per chat ([_kClockBackfillDone]);
/// derived `clock_from_day_count` pairs still refresh when start moves.
bool backfillSlotClocks(
  List<ChatMessage> messages, {
  required DateTime liveClock,
  DateTime? startDate,
  bool floorUnstampedToDay1 = false,
}) {
  final alreadyGuessed = _firstBotBackfillDone(messages);
  final start = startDate ?? StoryClock.dateOnly(liveClock);
  DateTime? greetingClock;
  if (messages.isNotEmpty &&
      !messages.first.isUser &&
      messages.first.sender != 'System') {
    for (final slot in _messageSlots(messages.first)) {
      greetingClock = _snapStoryClock(slot);
      if (greetingClock != null) break;
    }
  }
  var tipIndex = -1;
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    tipIndex = i;
  }

  final realByIndex = <int, DateTime>{};
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    DateTime? stored;
    for (final slot in _messageSlots(msg)) {
      stored = resolveSlotAfter(
        slot,
        isTip: false,
        liveClock: liveClock,
        startDate: start,
        greetingClock: greetingClock,
      );
      if (stored != null) break;
    }
    if (stored != null) {
      realByIndex[i] = stored;
    } else if (i == tipIndex) {
      realByIndex[i] = liveClock;
    }
  }

  DateTime? nearestReal(int index) {
    DateTime? earlier;
    var earlierDist = 1 << 30;
    DateTime? later;
    var laterDist = 1 << 30;
    for (final entry in realByIndex.entries) {
      final dist = (entry.key - index).abs();
      if (entry.key <= index) {
        if (dist < earlierDist) {
          earlierDist = dist;
          earlier = entry.value;
        }
      } else if (dist < laterDist) {
        laterDist = dist;
        later = entry.value;
      }
    }
    return earlier ?? later;
  }

  DateTime? ownDay(Map<String, dynamic>? slot) {
    final dc = _slotDayCount(slot);
    if (dc == null || dc <= 1) return null;
    return _dayCountClock(
      dayCount: dc,
      startDate: start,
      timeOfDay: _slotTimeOfDay(slot),
      liveClock: liveClock,
    );
  }

  DateTime? resolveAfter(
    int index,
    Map<String, dynamic>? slot, {
    required bool tipSlot,
  }) {
    return resolveSlotAfter(
      slot,
      isTip: tipSlot,
      liveClock: liveClock,
      startDate: start,
      greetingClock: greetingClock,
      neighbourStamp: nearestReal(index),
    );
  }

  var changed = false;
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    final isTip = i == tipIndex;
    final slotCount = msg.swipes.isEmpty ? 1 : msg.swipes.length;
    for (var s = 0; s < slotCount; s++) {
      final existing = s < msg.swipeMetadata.length
          ? msg.swipeMetadata[s]
          : null;
      if (existing == null && s > 0) continue;
      final slot = existing ?? (s == 0 ? msg.metadata : null);
      if (_shouldRepairWrongGreetingPair(slot, greetingClock: greetingClock)) {
        final snap = _snapStoryClock(slot)!;
        final dest = existing ?? msg.metadata!;
        writeSlotClockPair(
          dest,
          before: slotClockBefore(slot) ?? snap,
          after: snap,
        );
        persistStoryClockBefore(msg, StoryClock.serializeClock(snap));
        changed = true;
        continue;
      }
      if (slotHasCompletePair(slot)) {
        final derived = slot?['clock_from_day_count'] == true;
        final day = ownDay(slot);
        if (derived && day != null && slotClockAfter(slot) != day) {
          final dest = existing ?? msg.metadata!;
          writeSlotClockPair(dest, before: day, after: day, fromDayCount: true);
          persistStoryClockBefore(msg, StoryClock.serializeClock(day));
          changed = true;
        }
        continue;
      }
      if (alreadyGuessed) continue;
      final tipSlot = isTip && s == msg.swipeIndex;
      final after = resolveAfter(i, slot, tipSlot: tipSlot);
      if (after == null) continue;
      final keptAfter = slotClockAfter(slot);
      final keptBefore = slotClockBefore(slot);
      final mins = minutesRecordedForClockRewind(slot);
      final before =
          keptBefore ??
          (mins != null && mins > 0
              ? after.subtract(Duration(minutes: mins))
              : after);
      final dest = existing ?? (msg.metadata ??= {});
      writeSlotClockPair(
        dest,
        before: before,
        after: after,
        fromDayCount:
            ownDay(slot) != null && keptAfter == null && after == ownDay(slot),
      );
      persistStoryClockBefore(msg, StoryClock.serializeClock(before));
      changed = true;
    }
    if (msg.metadata != null) {
      final meta = msg.metadata!;
      if (_shouldRepairWrongGreetingPair(meta, greetingClock: greetingClock)) {
        final snap = _snapStoryClock(meta)!;
        writeSlotClockPair(
          meta,
          before: slotClockBefore(meta) ?? snap,
          after: snap,
        );
        persistStoryClockBefore(msg, StoryClock.serializeClock(snap));
        changed = true;
        continue;
      }
      final derived = meta['clock_from_day_count'] == true;
      final day = ownDay(meta);
      if (derived && day != null && slotClockAfter(meta) != day) {
        writeSlotClockPair(meta, before: day, after: day, fromDayCount: true);
        persistStoryClockBefore(msg, StoryClock.serializeClock(day));
        changed = true;
        continue;
      }
      if (slotHasCompletePair(meta)) {
        continue;
      }
      if (alreadyGuessed) continue;
      final after = resolveAfter(i, meta, tipSlot: isTip);
      if (after == null) continue;
      final keptAfter = slotClockAfter(meta);
      final before = slotClockBefore(meta) ?? after;
      writeSlotClockPair(
        meta,
        before: before,
        after: after,
        fromDayCount: day != null && keptAfter == null && after == day,
      );
      persistStoryClockBefore(msg, StoryClock.serializeClock(before));
      changed = true;
    }
  }
  if (!alreadyGuessed) _markClockBackfillDone(messages);
  return changed;
}
