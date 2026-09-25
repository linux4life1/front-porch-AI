// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pre-reply time belongs to the MESSAGE POSITION and is shared by every
// swipe. First known `story_clock_before` is persisted at message level
// and on every existing slot (`putIfAbsent`). Null slots stay null so
// activeMetadata still falls back to message metadata.

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

/// One slot-clock resolver. Null means keep the live clock.
///
/// 1. `story_clock_after`
/// 2. else `story_clock_before` + known chip minutes
/// 3. else snap `storyClock` that is not frozen
/// 4. else null
///
/// A snap is frozen when it equals the session greeting snap, or when it
/// is earlier than the message's known before. dayCount-only snaps are
/// never a clock.
DateTime? resolveSlotClock(
  Map<String, dynamic>? slot,
  ChatMessage message, {
  DateTime? greetingClock,
}) {
  final after = StoryClock.parse(slot?['story_clock_after'] as String?);
  if (after != null) return after;

  final mins = minutesRecordedForClockRewind(slot);
  final slotBefore = StoryClock.parse(slot?['story_clock_before'] as String?);
  final before = slotBefore ?? StoryClock.parse(knownStoryClockBefore(message));
  if (before != null && mins != null && mins > 0) {
    return before.add(Duration(minutes: mins));
  }

  final raw = slot?['realism_state'];
  if (raw is Map) {
    final snap = StoryClock.parse(raw['storyClock'] as String?);
    if (snap != null &&
        !slotSnapIsFrozen(
          snap,
          greetingClock: greetingClock,
          knownBefore: before,
        )) {
      return snap;
    }
  }
  return null;
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
