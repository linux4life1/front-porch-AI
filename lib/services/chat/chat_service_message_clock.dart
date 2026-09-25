// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// One clock contract: message-level before, per-slot after, captured
/// live clock on regen fail/cancel/abort. Never a realism_state snap.
extension ChatServiceMessageClock on ChatService {
  bool _clockWasNudged(ChatMessage msg) {
    final state = msg.activeMetadata?['realism_state'];
    return state is Map && state['time_nudged'] == true;
  }

  /// First known before for this message position. Persist on the message
  /// and every slot so later regen/delete never subtract another swipe.
  void _discoverAndPersistMessageBefore(ChatMessage msg) {
    var before = knownStoryClockBefore(msg);
    if (before == null) {
      final mins = minutesRecordedForClockRewind(msg.activeMetadata);
      if (mins != null && mins > 0) {
        before = StoryClock.serializeClock(
          _timeService.clock.subtract(Duration(minutes: mins)),
        );
      } else {
        before = _timeService.storyClockIso;
      }
    }
    persistStoryClockBefore(msg, before);
  }

  /// Pre-reply clock for regen/delete. Never a realism_state snap.
  void _rewindClockToPreReply(ChatMessage lastMsg, {required bool wasNudged}) {
    if (!_clockRunning || wasNudged) return;
    _discoverAndPersistMessageBefore(lastMsg);
    _timeService.rewindToBeforeIso(knownStoryClockBefore(lastMsg));
  }

  void _applySwipeSlotClock(ChatMessage msg) {
    if (!_clockRunning || _clockWasNudged(msg)) return;
    _timeService.applySelectedSlotClock(
      after: msg.activeMetadata?['story_clock_after'] as String?,
      before: knownStoryClockBefore(msg),
      minutes: minutesRecordedForClockRewind(msg.activeMetadata),
    );
  }

  void _stampStoryClockAfter(ChatMessage? target) {
    if (target == null || target.isUser) return;
    final existing = Map<String, dynamic>.from(target.activeMetadata ?? {});
    existing['story_clock_after'] = _timeService.storyClockIso;
    target.activeMetadata = existing;
  }

  void _putBackCapturedClock() {
    _timeService.restoreCapturedClock();
    _timeService.clearCapturedClock();
  }
}
