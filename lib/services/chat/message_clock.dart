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
}) {
  slot['story_clock_before'] = StoryClock.serializeClock(before);
  slot['story_clock_after'] = StoryClock.serializeClock(after);
  if (clearChip) {
    slot.remove('time_passed');
  } else if (timePassed != null && timePassed.isNotEmpty) {
    slot['time_passed'] = timePassed;
  }
  if (timeNudged) slot['time_nudged'] = true;
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

DateTime _dayCountClock({
  required int dayCount,
  required DateTime liveClock,
  required DateTime startDate,
}) {
  final day = dayCount.clamp(1, 9999);
  final date = StoryClock.dateOnly(startDate).add(Duration(days: day - 1));
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
/// only when no storyClock exists on any message. Never Day 1 unless
/// [liveClock] (or that dayCount) really is Day 1. Idempotent.
bool backfillSlotClocks(
  List<ChatMessage> messages, {
  required DateTime liveClock,
  DateTime? startDate,
}) {
  final start = startDate ?? StoryClock.dateOnly(liveClock);
  DateTime? greetingClock;
  var anyStoryClock = false;
  int? dayCountOnly;
  var tipIndex = -1;
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    tipIndex = i;
    for (final slot in _messageSlots(msg)) {
      if (_snapStoryClock(slot) != null ||
          slotClockAfter(slot) != null ||
          slotClockBefore(slot) != null) {
        anyStoryClock = true;
      }
      greetingClock ??= _snapStoryClock(slot);
      dayCountOnly ??= _slotDayCount(slot);
    }
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

  final dayClock = !anyStoryClock && dayCountOnly != null
      ? _dayCountClock(
          dayCount: dayCountOnly,
          liveClock: liveClock,
          startDate: start,
        )
      : null;

  DateTime fallback(int index, {required bool tipSlot}) {
    if (dayClock != null) return dayClock;
    if (tipSlot) return liveClock;
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
      final slot = existing ?? (s == 0 ? msg.metadata : null);
      if (slotHasCompletePair(slot)) continue;
      final tipSlot = isTip && s == msg.swipeIndex;
      final after =
          slotClockAfter(slot) ??
          _realTimeOnSlot(slot, greetingClock: greetingClock) ??
          fallback(i, tipSlot: tipSlot);
      final mins = minutesRecordedForClockRewind(slot);
      final before =
          slotClockBefore(slot) ??
          (mins != null && mins > 0
              ? after.subtract(Duration(minutes: mins))
              : after);
      if (existing != null) {
        writeSlotClockPair(existing, before: before, after: after);
      } else if (s == 0) {
        msg.metadata ??= {};
        writeSlotClockPair(msg.metadata!, before: before, after: after);
      } else {
        while (msg.swipeMetadata.length <= s) {
          msg.swipeMetadata.add(null);
        }
        final created = <String, dynamic>{};
        writeSlotClockPair(created, before: before, after: after);
        msg.swipeMetadata[s] = created;
      }
      persistStoryClockBefore(msg, StoryClock.serializeClock(before));
      changed = true;
    }
    if (!slotHasCompletePair(msg.metadata) && msg.metadata != null) {
      final after =
          slotClockAfter(msg.metadata) ??
          _realTimeOnSlot(msg.metadata, greetingClock: greetingClock) ??
          fallback(i, tipSlot: isTip);
      final before = slotClockBefore(msg.metadata) ?? after;
      writeSlotClockPair(msg.metadata!, before: before, after: after);
      persistStoryClockBefore(msg, StoryClock.serializeClock(before));
      changed = true;
    }
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
