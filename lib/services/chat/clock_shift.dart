// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';

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
