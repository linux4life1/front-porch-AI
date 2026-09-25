// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pre-reply time belongs to the MESSAGE POSITION and is shared by every
// swipe. First known `story_clock_before` is persisted at message level
// and on every existing slot (`putIfAbsent`). Null slots stay null so
// activeMetadata still falls back to message metadata.

import 'package:front_porch_ai/models/models.dart';
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

/// Greeting-era snap (Day 1 09:00) on a chat whose live clock has moved on.
bool snapIsFrozenGreeting(Map<String, dynamic>? snap, DateTime liveClock) {
  if (snap == null) return true;
  final clock = StoryClock.parse(snap['storyClock'] as String?);
  if (clock == null) return true;
  final start = StoryClock.parse(snap['storyStartDate'] as String?);
  final anchor = start != null
      ? StoryClock.dateOnly(start)
      : StoryClock.dateOnly(clock);
  final greeting = StoryClock.representativeTime(anchor, 'morning');
  return clock == greeting && liveClock.isAfter(clock);
}

/// Slide every clock stamp by [delta] (calendar re-anchor).
void shiftMessageClockStamps(List<ChatMessage> messages, Duration delta) {
  if (delta == Duration.zero) return;
  for (final msg in messages) {
    _shiftClockMap(msg.metadata, delta);
    for (final slot in msg.swipeMetadata) {
      _shiftClockMap(slot, delta);
    }
  }
}

void _shiftClockMap(Map<String, dynamic>? map, Duration delta) {
  if (map == null) return;
  String? shift(Object? raw) {
    final t = StoryClock.parse(raw is String ? raw : null);
    if (t == null) return raw is String ? raw : null;
    return StoryClock.serializeClock(t.add(delta));
  }

  if (map['story_clock_before'] is String) {
    map['story_clock_before'] = shift(map['story_clock_before']);
  }
  if (map['story_clock_after'] is String) {
    map['story_clock_after'] = shift(map['story_clock_after']);
  }
  final rs = map['realism_state'];
  if (rs is! Map) return;
  if (rs['storyClock'] is String) {
    rs['storyClock'] = shift(rs['storyClock']);
  }
  if (rs['storyStartDate'] is String) {
    final d = StoryClock.parse(rs['storyStartDate'] as String?);
    if (d != null) {
      rs['storyStartDate'] = StoryClock.serializeDate(d.add(delta));
    }
  }
}
