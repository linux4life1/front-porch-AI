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

/// Message 0's snap only. A stamp-less greeting is null even when
/// later replies carry Day-1 leftovers — repair uses this, frozen
/// detection does not.
DateTime? openingGreetingSnap(List<ChatMessage> messages) {
  if (messages.isEmpty) return null;
  final first = messages.first;
  if (first.isUser || first.sender == 'System') return null;
  for (final slot in _messageSlots(first)) {
    final snap = slotSnapClock(slot);
    if (snap != null) return snap;
  }
  return null;
}

/// Earliest `storyClock` on a reply after message 0.
DateTime? earliestReplySnap(List<ChatMessage> messages) {
  DateTime? earliest;
  for (var i = 1; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    for (final slot in _messageSlots(msg)) {
      final snap = slotSnapClock(slot);
      if (snap == null) continue;
      if (earliest == null || snap.isBefore(earliest)) earliest = snap;
    }
  }
  return earliest;
}

/// Frozen-detection greeting clock: message 0's snap, else the
/// earliest reply snap when message 0 is a stamp-less bot greeting.
/// A leading user turn is not a greeting — do not freeze the first
/// reply's own snap (lived-in .fpchat head clock).
DateTime? frozenDetectionGreetingClock(List<ChatMessage> messages) {
  if (messages.isEmpty) return null;
  final first = messages.first;
  if (first.isUser || first.sender == 'System') return null;
  return openingGreetingSnap(messages) ?? earliestReplySnap(messages);
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
/// changed). History [ownDay] never reads live TOD — a fork that
/// re-seeds the card clock must not rewrite a history slot with a
/// new live time of day. [alreadyGuessed] does not block this.
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
/// A greeting with nothing stored takes the next neighbour's before,
/// else Day 1. [floorUnstampedToDay1] is accepted and does not floor
/// history. Never overwrites an existing before or after. Guess
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
  final openingSnap = openingGreetingSnap(messages);
  final greetingClock = frozenDetectionGreetingClock(messages);
  var tipIndex = -1;
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.isUser || msg.sender == 'System') continue;
    tipIndex = i;
  }

  // Stored-data stamps only. isTip:false / isGreeting:false so live
  // and Day 1 never enter this set. Later neighbours donate BEFORE;
  // earlier neighbours donate AFTER.
  final earlierAfter = <int, DateTime>{};
  final laterBefore = <int, DateTime>{};
  for (var i = 0; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.sender == 'System') continue;
    DateTime? storedAfter;
    DateTime? storedBefore = StoryClock.parse(knownStoryClockBefore(msg));
    for (final slot in _messageSlots(msg)) {
      storedAfter ??= resolveSlotAfter(
        slot,
        isTip: false,
        liveClock: liveClock,
        startDate: start,
        greetingClock: greetingClock,
      );
      storedBefore ??= slotClockBefore(slot);
    }
    if (storedAfter == null && msg.metadata != null) {
      storedAfter = resolveSlotAfter(
        msg.metadata,
        isTip: false,
        liveClock: liveClock,
        startDate: start,
        greetingClock: greetingClock,
      );
    }
    if (storedAfter != null) earlierAfter[i] = storedAfter;
    if (storedBefore != null) laterBefore[i] = storedBefore;
  }

  DateTime? nearestReal(int index) => directionalNeighbourStamp(
    index: index,
    earlierAfter: earlierAfter,
    laterBefore: laterBefore,
  );

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
    final greetingSlot =
        index == 0 &&
        !messages[index].isUser &&
        messages[index].sender != 'System';
    return resolveSlotAfter(
      slot,
      isTip: tipSlot,
      liveClock: liveClock,
      startDate: start,
      greetingClock: greetingClock,
      neighbourStamp: nearestReal(index),
      answeredUserBefore: answeredUserClock(
        messages,
        index,
        liveClock: liveClock,
        startDate: start,
        greetingClock: greetingClock,
        neighbourStamp: nearestReal(index - 1),
      ),
      isGreeting: greetingSlot,
      greetingIsTip: greetingSlot && index == tipIndex,
    );
  }

  bool repairInvertedPair(
    Map<String, dynamic>? slot,
    Map<String, dynamic> dest,
    ChatMessage msg,
  ) {
    if (!slotPairIsInverted(slot)) return false;
    final before = slotClockBefore(slot)!;
    writeSlotClockPair(dest, before: before, after: before);
    persistStoryClockBefore(msg, StoryClock.serializeClock(before));
    return true;
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
      if (_shouldRepairWrongGreetingPair(slot, greetingClock: openingSnap)) {
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
      final dest = existing ?? (msg.metadata ??= {});
      if (repairInvertedPair(slot, dest, msg)) {
        changed = true;
        continue;
      }
      if (slotHasCompletePair(slot)) {
        if (_refreshDerivedDayPair(slot, dest, msg, start, dayOf)) {
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
      if (_shouldRepairWrongGreetingPair(meta, greetingClock: openingSnap)) {
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
      if (repairInvertedPair(meta, meta, msg)) {
        changed = true;
        continue;
      }
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
