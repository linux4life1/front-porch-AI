// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One resolver for every slot, tip included. Own after → non-frozen
// snap → dayCount>1 → before → neighbour. Live only for an empty tip.

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
      liveClock: before ?? liveClock,
    );
    if (before != null && fromDay.isBefore(before)) return before;
    return fromDay;
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
