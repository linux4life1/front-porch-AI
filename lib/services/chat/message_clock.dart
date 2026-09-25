// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pre-reply time belongs to the MESSAGE POSITION and is shared by every
// swipe. First known `story_clock_before` is persisted at message level
// and on every slot (`putIfAbsent`).

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

/// Persist [iso] at message level and on every swipe slot. Existing values win.
void persistStoryClockBefore(ChatMessage msg, String iso) {
  msg.metadata ??= {};
  msg.metadata!.putIfAbsent('story_clock_before', () => iso);
  while (msg.swipeMetadata.length < msg.swipes.length) {
    msg.swipeMetadata.add(null);
  }
  for (var i = 0; i < msg.swipes.length; i++) {
    final slot = msg.swipeMetadata[i];
    if (slot == null) {
      msg.swipeMetadata[i] = {'story_clock_before': iso};
    } else {
      slot.putIfAbsent('story_clock_before', () => iso);
    }
  }
}
