// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every bot reply slot carries exactly one clock pair:
// story_clock_before + story_clock_after (after == before when nothing
// ticked), plus chip data. That pair is the only runtime source of
// truth. Legacy snaps / dayCount / timeOfDay are read once, here.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/clock_resolve.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

export 'clock_resolve.dart';
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
  final snap = slotSnapClock(slot);
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

/// Rewrite a derived day pair only when start moved (calendar day
/// changed). Live TOD changing — a fork re-seeding the card clock —
/// must not clobber the stored after. [alreadyGuessed] does not
/// block this: the marker means don't re-guess, not don't rewrite
/// a pair measured against an old start.
bool _refreshDerivedDayPair(
  Map<String, dynamic>? slot,
  Map<String, dynamic> dest,
  ChatMessage msg,
  DateTime start,
  DateTime? Function(Map<String, dynamic>?) ownDay,
) {
  final stored = slotClockAfter(slot);
  if (stored == null) return false;
  if (!slotDerivedAfterIsStale(slot, stored, startDate: start)) return false;
  final day = ownDay(slot);
  if (day == null) return false;
  writeSlotClockPair(dest, before: day, after: day, fromDayCount: true);
  persistStoryClockBefore(msg, StoryClock.serializeClock(day));
  return true;
}

/// Fill missing before/after pairs. The only snap / dayCount reader.
///
/// One resolver for every slot, tip included. Frozen greeting snaps
/// are not a clock. dayCount-only is a clock only when THAT message
/// stored dayCount > 1. Day-without-TOD takes the neighbour stamp's
/// TOD; if none, the tip uses [liveClock] and history uses 09:00.
/// Never invents Day 1. [floorUnstampedToDay1] is accepted and does
/// not floor. Never overwrites an existing before or after. Guess
/// runs once per chat ([_kClockBackfillDone]) — the marker must not
/// block a writer from refreshing a derived pair when start moved.
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
      greetingClock = slotSnapClock(slot);
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
    if (msg.sender == 'System') continue;
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
    if (stored == null && msg.metadata != null) {
      stored = resolveSlotAfter(
        msg.metadata,
        isTip: false,
        liveClock: liveClock,
        startDate: start,
        greetingClock: greetingClock,
      );
    }
    if (stored != null) realByIndex[i] = stored;
  }

  DateTime? nearestReal(int index) {
    DateTime? earlier;
    var earlierDist = 1 << 30;
    DateTime? later;
    var laterDist = 1 << 30;
    for (final entry in realByIndex.entries) {
      if (entry.key == index) continue;
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

  DateTime? ownDay(
    int index,
    Map<String, dynamic>? slot, {
    required bool tipSlot,
  }) {
    final dc = slotDayCount(slot);
    if (dc == null || dc <= 1) return null;
    return dayCountClock(
      dayCount: dc,
      startDate: start,
      timeOfDay: slotTimeOfDay(slot),
      liveClock: dayCountTodClock(
        isTip: tipSlot,
        liveClock: liveClock,
        neighbourStamp: nearestReal(index),
      ),
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
      neighbourStamp:
          nearestReal(index) ?? (tipSlot ? null : realByIndex[index]),
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
        final snap = slotSnapClock(slot)!;
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
      final tipSlot = isTip && s == msg.swipeIndex;
      DateTime? dayOf(Map<String, dynamic>? s) =>
          ownDay(i, s, tipSlot: tipSlot);
      if (slotHasCompletePair(slot)) {
        if (_refreshDerivedDayPair(
          slot,
          existing ?? msg.metadata!,
          msg,
          start,
          dayOf,
        )) {
          changed = true;
        }
        continue;
      }
      if (alreadyGuessed) continue;
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
      final day = dayOf(slot);
      writeSlotClockPair(
        dest,
        before: before,
        after: after,
        fromDayCount: day != null && keptAfter == null && after == day,
      );
      persistStoryClockBefore(msg, StoryClock.serializeClock(before));
      changed = true;
    }
    if (msg.metadata != null) {
      final meta = msg.metadata!;
      if (_shouldRepairWrongGreetingPair(meta, greetingClock: greetingClock)) {
        final snap = slotSnapClock(meta)!;
        writeSlotClockPair(
          meta,
          before: slotClockBefore(meta) ?? snap,
          after: snap,
        );
        persistStoryClockBefore(msg, StoryClock.serializeClock(snap));
        changed = true;
        continue;
      }
      DateTime? dayOf(Map<String, dynamic>? s) => ownDay(i, s, tipSlot: isTip);
      if (_refreshDerivedDayPair(meta, meta, msg, start, dayOf)) {
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
      final day = dayOf(meta);
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
