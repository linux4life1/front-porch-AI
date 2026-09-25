// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One resolver for every slot, tip included. Own after → chip →
// non-frozen snap → dayCount>1 → before. An empty tip is live —
// a neighbour stamp does not paint it. History with nothing stored
// takes the neighbour, else null. History never takes live.
// Day-without-TOD: own day, neighbour TOD, else tip = live TOD /
// history = 09:00.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

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
  if (slotSnapClock(slot) != null) return true;
  if ((slot?['time_passed'] as String?)?.isNotEmpty == true) return true;
  if (slot?['time_nudged'] == true) return true;
  if (slot?['clock_from_day_count'] == true) return true;
  final dc = slotDayCount(slot);
  return dc != null && dc > 1;
}

DateTime? slotSnapClock(Map<String, dynamic>? slot) {
  final raw = slot?['realism_state'];
  if (raw is! Map) return null;
  return StoryClock.parse(raw['storyClock'] as String?);
}

int? slotDayCount(Map<String, dynamic>? slot) {
  if (slot == null) return null;
  final rs = slot['realism_state'];
  if (rs is Map && rs['dayCount'] is num) {
    return (rs['dayCount'] as num).toInt();
  }
  final top = slot['story_day'];
  if (top is num) return top.toInt();
  return null;
}

String? slotTimeOfDay(Map<String, dynamic>? slot) {
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

/// Neighbour stamp's TOD, else the tip's live clock, else null (09:00).
DateTime? dayCountTodClock({
  required bool isTip,
  required DateTime liveClock,
  DateTime? neighbourStamp,
}) {
  if (neighbourStamp != null) return neighbourStamp;
  if (isTip) return liveClock;
  return null;
}

DateTime dayCountClock({
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

/// A derived day pair is stale when start moved: the stored after's
/// calendar day no longer equals start + (dayCount-1). Chip / nudge /
/// snap pairs are real stamps and are not rewritten. Live TOD changing
/// alone is not stale — only the date vs start.
bool slotDerivedAfterIsStale(
  Map<String, dynamic>? slot,
  DateTime keptAfter, {
  DateTime? startDate,
}) {
  if (startDate == null) return false;
  final dc = slotDayCount(slot);
  if (dc == null || dc <= 1) return false;
  final expected = StoryClock.dateOnly(startDate).add(Duration(days: dc - 1));
  if (StoryClock.dateOnly(keptAfter) == expected) return false;
  if (slot?['clock_from_day_count'] == true) return true;
  if (slot?['time_nudged'] == true) return false;
  if ((slot?['time_passed'] as String?)?.isNotEmpty == true) return false;
  if (slotSnapClock(slot) != null) return false;
  return true;
}

/// Greeting-era snap, or a snap that predates this message's before.
/// A snap later than this slot's own before is this reply's clock
/// (v1.4 before + snap, no after) even when that wall-clock equals
/// the greeting snap on a Day-1 open.
bool slotSnapIsFrozen(
  DateTime clock, {
  DateTime? greetingClock,
  DateTime? knownBefore,
}) {
  if (knownBefore != null && clock.isBefore(knownBefore)) return true;
  if (greetingClock != null && clock == greetingClock) {
    if (knownBefore != null && clock.isAfter(knownBefore)) return false;
    return true;
  }
  return false;
}

/// Own stored after → chip → non-frozen snap → dayCount>1 → before.
/// An empty tip is [liveClock] even when [neighbourStamp] exists.
/// History with nothing stored takes [neighbourStamp], else null.
/// A derived day after whose calendar day does not match [startDate]
/// is stale (start moved) and is recomputed. Day-without-TOD takes
/// [neighbourStamp]'s TOD; if none, the tip uses [liveClock] and
/// history uses 09:00. History never takes [liveClock].
DateTime? resolveSlotAfter(
  Map<String, dynamic>? slot, {
  required bool isTip,
  required DateTime liveClock,
  DateTime? startDate,
  DateTime? greetingClock,
  DateTime? neighbourStamp,
}) {
  final keptAfter = slotClockAfter(slot);
  if (keptAfter != null &&
      !slotDerivedAfterIsStale(slot, keptAfter, startDate: startDate)) {
    return keptAfter;
  }
  final before = slotClockBefore(slot);
  final mins = minutesRecordedForClockRewind(slot);
  if (before != null && mins != null && mins > 0) {
    return before.add(Duration(minutes: mins));
  }
  final snap = slotSnapClock(slot);
  if (snap != null &&
      !slotSnapIsFrozen(
        snap,
        greetingClock: greetingClock,
        knownBefore: before,
      )) {
    return snap;
  }
  final dc = slotDayCount(slot);
  if (dc != null && dc > 1) {
    final fromDay = dayCountClock(
      dayCount: dc,
      startDate: startDate ?? StoryClock.dateOnly(liveClock),
      timeOfDay: slotTimeOfDay(slot),
      liveClock: dayCountTodClock(
        isTip: isTip,
        liveClock: liveClock,
        neighbourStamp: neighbourStamp,
      ),
    );
    if (before != null && fromDay.isBefore(before)) return before;
    return fromDay;
  }
  if (before != null) return before;
  if (isTip) return liveClock;
  if (neighbourStamp != null) return neighbourStamp;
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
