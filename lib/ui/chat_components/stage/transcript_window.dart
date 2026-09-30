// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/chat/session_open_window.dart';

/// How many older rows to mount when the reader reaches the top.
const kTranscriptRevealPage = 24;

/// The rows [ChatMessageList] actually builds.
///
/// The service list can hold an entire long chat. Mounting that list
/// paints from the oldest line and the scrollbar thumb tracks a guess.
/// This span stays on the latest [kSessionOpenWindow] rows when a chat
/// opens or older rows arrive behind the reader, and grows upward only
/// when they are already at the top.
class TranscriptWindow {
  int start = 0;
  int end = 0;

  int get length => end > start ? end - start : 0;

  void apply({
    required int previousLength,
    required int nextLength,
    required bool opened,
    required bool prepended,
    required bool nearTop,
  }) {
    if (nextLength <= 0) {
      start = 0;
      end = 0;
      return;
    }
    if (opened || previousLength <= 0) {
      end = nextLength;
      start = nextLength > kSessionOpenWindow
          ? nextLength - kSessionOpenWindow
          : 0;
      return;
    }
    if (nextLength > previousLength && prepended) {
      final added = nextLength - previousLength;
      if (nearTop) {
        end += added;
      } else {
        start += added;
        end += added;
      }
    } else if (nextLength > previousLength) {
      final wasAtTip = end >= previousLength;
      if (wasAtTip) end = nextLength;
    } else if (nextLength < previousLength && end >= previousLength) {
      end = nextLength;
    }
    _clamp(nextLength);
  }

  /// Include older rows already in memory. False when none are hidden.
  bool revealOlder(int fullLength, {int page = kTranscriptRevealPage}) {
    if (start <= 0 || fullLength <= 0) return false;
    start = start > page ? start - page : 0;
    _clamp(fullLength);
    return true;
  }

  /// Put [index] inside the mounted span. Used by journal jump.
  void revealAround(int index, int fullLength) {
    if (fullLength <= 0) return;
    final i = index < 0 ? 0 : (index >= fullLength ? fullLength - 1 : index);
    if (i >= start && i < end) return;
    var nextEnd = i + (kSessionOpenWindow ~/ 2);
    if (nextEnd < i + 1) nextEnd = i + 1;
    if (nextEnd > fullLength) nextEnd = fullLength;
    var nextStart = nextEnd - kSessionOpenWindow;
    if (nextStart < 0) nextStart = 0;
    if (i < nextStart) nextStart = i;
    if (i >= nextEnd) nextEnd = i + 1;
    start = nextStart;
    end = nextEnd;
    _clamp(fullLength);
  }

  void _clamp(int fullLength) {
    if (fullLength <= 0) {
      start = 0;
      end = 0;
      return;
    }
    if (end > fullLength) end = fullLength;
    if (end < 0) end = 0;
    if (start < 0) start = 0;
    if (start > end) start = end;
    if (start == end && end > 0) start = end - 1;
  }
}
