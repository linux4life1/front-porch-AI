// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The time-skip anchor: one plain fact line, outside the state zone's
// "notes may be behind" frame, saying how long the last long skip was and
// that everything before it happened back then. Without it the only new
// date sat inside notes the model was told to distrust, and the pre-skip
// "tonight" and "tomorrow" in the transcript read as now.
//
// Derived from the transcript every turn (the skip reply's
// `skip_minutes` or `long_skip_minutes` stamp and its
// `story_clock_before`), never from a counter, so regen, swipe and delete
// rewind it with the messages. A skip of [kSkipAnchorMinutes] or more is
// named, so every speaker after "eight hours later" hears it plainly too.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_skip_bridge.dart';

/// Skips at least this long get the anchor line.
const int kSkipAnchorMinutes = 3 * 60;

/// User turns after the skip's reply that still carry the anchor.
const int kTimeSkipAnchorUserTurns = 3;

/// The long skip the anchor names: [minutes] long, landing at [to].
typedef LongSkipMark = ({int minutes, DateTime to});

/// The skip this turn still answers to, or null. [pendingMinutes] is this
/// turn's own skip (the reply is not stored yet), landing at [clock].
/// Otherwise the newest reply stamped with [kSkipMinutesMeta] or
/// [kLongSkipMinutesMeta], while no more than [kTimeSkipAnchorUserTurns]
/// user lines came after it.
LongSkipMark? latestLongSkip({
  required List<ChatMessage> messages,
  required DateTime clock,
  int? pendingMinutes,
}) {
  if (pendingMinutes != null && pendingMinutes >= kSkipAnchorMinutes) {
    return (minutes: pendingMinutes, to: clock);
  }
  var userLines = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.isUser) {
      if (!m.isDirectorNarration) userLines++;
      if (userLines > kTimeSkipAnchorUserTurns) return null;
      continue;
    }
    final meta = m.activeMetadata;
    final stamp = meta?[kSkipMinutesMeta] ?? meta?[kLongSkipMinutesMeta];
    final minutes = (stamp as num?)?.toInt();
    if (minutes == null || minutes < kSkipAnchorMinutes) continue;
    final to = StoryClock.parse(knownStoryClockBefore(m));
    return to == null ? null : (minutes: minutes, to: to);
  }
  return null;
}

/// The anchor line, or '' when there is no skip to name.
String buildTimeSkipAnchor(LongSkipMark? skip) {
  if (skip == null) return '';
  final from = skip.to.subtract(Duration(minutes: skip.minutes));
  return '\n[Time skip: about ${skipSpanWords(skip.minutes)} passed between '
      'the earlier scene and now (${skipMomentWords(from)} → '
      '${skipMomentWords(skip.to)}). Everything in the conversation from '
      'before the skip happened back then, not now.]\n';
}
