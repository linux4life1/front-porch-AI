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

DateTime? _realTimeOnSlot(
  Map<String, dynamic>? slot, {
  DateTime? greetingClock,
}) {
  final after = slotClockAfter(slot);
  if (after != null) return after;
  final before = slotClockBefore(slot);
  final mins = minutesRecordedForClockRewind(slot);
  if (before != null && mins != null && mins > 0) {
    return before.add(Duration(minutes: mins));
  }
  final snap = _snapStoryClock(slot);
  if (snap != null &&
      !slotSnapIsFrozen(
        snap,
        greetingClock: greetingClock,
        knownBefore: before,
      )) {
    return snap;
  }
  return null;
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
  required DateTime liveClock,
  required DateTime startDate,
  String? timeOfDay,
}) {
  final day = dayCount.clamp(1, 9999);
  final date = StoryClock.dateOnly(startDate).add(Duration(days: day - 1));
  if (timeOfDay != null && timeOfDay.isNotEmpty) {
    return StoryClock.representativeTime(date, timeOfDay);
  }
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
    liveClock.hour,
    liveClock.minute,
  );
}

/// Fill missing before/after pairs. The only snap / dayCount reader.
///
/// Tip (last bot, active slot) takes [liveClock] unless it already has
/// after. History takes the nearest real, non-frozen time. Frozen
/// greeting snaps (any hour) are not a clock. dayCount-only is a clock
/// only when no storyClock exists on any message — nearest from the
/// tip backward, at that stamp's timeOfDay. Never overwrites an
/// existing before or after. Guess runs once per chat
/// ([_kClockBackfillDone]). [floorUnstampedToDay1] is test-only.
bool backfillSlotClocks(
  List<ChatMessage> messages, {
  required DateTime liveClock,
  DateTime? startDate,
  bool floorUnstampedToDay1 = false,
}) {
  final start = startDate ?? StoryClock.dateOnly(liveClock);
  final alreadyDone = _firstBotBackfillDone(messages);
  DateTime? greetingClock;
  if (messages.isNotEmpty &&
      !messages.first.isUser &&
      messages.first.sender != 'System') {
    for (final slot in _messageSlots(messages.first)) {
      greetingClock = _snapStoryClock(slot);
      if (greetingClock != null) break;
    }
  }
  var anyStoryClock = false;
  int? dayCountOnly;
  String? dayCountTod;
  var tipIndex = -1;
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    tipIndex = i;
    for (final slot in _messageSlots(msg)) {
      if (_snapStoryClock(slot) != null ||
          (slotHasCompletePair(slot) &&
              slot?['clock_from_day_count'] != true)) {
        anyStoryClock = true;
      }
    }
  }
  for (var i = messages.length - 1; i >= 0; i--) {
    final msg = messages[i];
    var found = false;
    for (final slot in _messageSlots(msg)) {
      final dc = _slotDayCount(slot);
      // Day 1 is the greeting-era leftover, not a clock (Carmen).
      if (dc == null || dc <= 1) continue;
      dayCountOnly = dc;
      dayCountTod = _slotTimeOfDay(slot);
      found = true;
      break;
    }
    if (found) break;
  }

  final realByIndex = <int, DateTime>{};
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    for (final slot in _messageSlots(msg)) {
      final real = _realTimeOnSlot(slot, greetingClock: greetingClock);
      if (real != null) {
        realByIndex[i] = real;
        break;
      }
    }
  }

  DateTime? nearestReal(int index) {
    DateTime? found;
    var best = 1 << 30;
    for (final entry in realByIndex.entries) {
      final dist = (entry.key - index).abs();
      if (dist < best) {
        best = dist;
        found = entry.value;
      }
    }
    return found;
  }

  final dayClock =
      !alreadyDone &&
          !anyStoryClock &&
          (dayCountOnly != null || floorUnstampedToDay1)
      ? _dayCountClock(
          dayCount: dayCountOnly ?? 1,
          liveClock: liveClock,
          startDate: start,
          timeOfDay: dayCountTod,
        )
      : null;

  DateTime fallback(int index, {required bool tipSlot}) {
    if (tipSlot) return liveClock;
    if (dayClock != null) return dayClock;
    return nearestReal(index) ?? liveClock;
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
        if (!derived || dayClock == null || slotClockAfter(slot) == dayClock) {
          continue;
        }
      }
      final tipSlot = isTip && s == msg.swipeIndex;
      final keptAfter = slotClockAfter(slot);
      final keptBefore = slotClockBefore(slot);
      final after =
          keptAfter ??
          _realTimeOnSlot(slot, greetingClock: greetingClock) ??
          fallback(i, tipSlot: tipSlot);
      final mins = minutesRecordedForClockRewind(slot);
      final before =
          keptBefore ??
          (mins != null && mins > 0
              ? after.subtract(Duration(minutes: mins))
              : after);
      void write(Map<String, dynamic> dest) {
        writeSlotClockPair(
          dest,
          before: before,
          after: after,
          fromDayCount: dayClock != null && keptAfter == null,
        );
      }

      if (existing != null) {
        write(existing);
      } else {
        msg.metadata ??= {};
        write(msg.metadata!);
      }
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
      final staleDerived =
          derived && dayClock != null && slotClockAfter(meta) != dayClock;
      if (slotHasCompletePair(meta) && !staleDerived) {
        continue;
      }
      final keptAfter = slotClockAfter(meta);
      final keptBefore = slotClockBefore(meta);
      final after =
          keptAfter ??
          _realTimeOnSlot(meta, greetingClock: greetingClock) ??
          fallback(i, tipSlot: isTip);
      final before = keptBefore ?? after;
      writeSlotClockPair(
        meta,
        before: before,
        after: after,
        fromDayCount: dayClock != null && keptAfter == null,
      );
      persistStoryClockBefore(msg, StoryClock.serializeClock(before));
      changed = true;
    }
  }
  if (!_firstBotBackfillDone(messages)) {
    _markClockBackfillDone(messages);
    changed = true;
  }
  return changed;
}

/// Slide every clock stamp by [delta] (calendar re-anchor).
/// Each map (top-level and inner `realism_state`) moves once.
void shiftMessageClockStamps(List<ChatMessage> messages, Duration delta) {
  if (delta == Duration.zero) return;
  final seen = Set<Map>.identity();
  for (final msg in messages) {
    shiftClockFields(msg.metadata, delta, seen);
    for (final slot in msg.swipeMetadata) {
      shiftClockFields(slot, delta, seen);
    }
  }
}

/// Shift clock keys on [map]. Returns whether anything changed.
bool shiftClockFields(
  Map<String, dynamic>? map,
  Duration delta,
  Set<Map> seen,
) {
  if (map == null || !seen.add(map)) return false;
  var changed = false;
  String? shift(Object? raw) {
    final t = StoryClock.parse(raw is String ? raw : null);
    if (t == null) return raw is String ? raw : null;
    changed = true;
    return StoryClock.serializeClock(t.add(delta));
  }

  if (map['story_clock_before'] is String) {
    map['story_clock_before'] = shift(map['story_clock_before']);
  }
  if (map['story_clock_after'] is String) {
    map['story_clock_after'] = shift(map['story_clock_after']);
  }
  final rs = map['realism_state'];
  if (rs is! Map) return changed;
  if (!seen.add(rs)) return changed;
  if (rs['storyClock'] is String) {
    rs['storyClock'] = shift(rs['storyClock']);
  }
  if (rs['storyStartDate'] is String) {
    final d = StoryClock.parse(rs['storyStartDate'] as String?);
    if (d != null) {
      rs['storyStartDate'] = StoryClock.serializeDate(d.add(delta));
      changed = true;
    }
  }
  return changed;
}
