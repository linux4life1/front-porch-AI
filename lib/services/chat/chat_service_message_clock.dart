// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// One clock contract: message-level before, per-slot after, captured
/// live clock+start on regen fail/cancel/abort. Swipe/fork use
/// [resolveSlotClock]. Snap is last-resort and never a dayCount-only.
extension ChatServiceMessageClock on ChatService {
  bool _clockWasNudged(ChatMessage msg) {
    final meta = msg.activeMetadata;
    if (meta?['time_nudged'] == true) return true;
    final state = meta?['realism_state'];
    return state is Map && state['time_nudged'] == true;
  }

  DateTime? _sessionGreetingClock() {
    for (final m in _messages) {
      if (m.isUser || m.sender == 'System') continue;
      final raw =
          m.metadata?['realism_state'] ?? m.activeMetadata?['realism_state'];
      if (raw is Map) {
        final clock = StoryClock.parse(raw['storyClock'] as String?);
        if (clock != null) return clock;
      }
      break;
    }
    return null;
  }

  DateTime? _resolveMessageSlot(ChatMessage msg, {Map<String, dynamic>? slot}) {
    return resolveSlotClock(
      slot ?? msg.activeMetadata,
      msg,
      greetingClock: _sessionGreetingClock(),
    );
  }

  /// First known before for this message position. Persist on the message
  /// and every existing slot so later regen/delete never subtract another
  /// swipe. Chip inference uses the ACTIVE slot only.
  void _discoverAndPersistMessageBefore(ChatMessage msg) {
    var before = knownStoryClockBefore(msg);
    if (before == null) {
      final mins = minutesRecordedForClockRewind(msg.activeMetadata);
      if (mins != null && mins > 0) {
        final from = _resolveMessageSlot(msg) ?? _timeService.clock;
        before = StoryClock.serializeClock(
          from.subtract(Duration(minutes: mins)),
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

  void _applySwipeSlotClock(
    ChatMessage msg, {
    DateTime? previousResolved,
    bool guestsBelow = false,
  }) {
    if (!_clockRunning) return;
    final next = _resolveMessageSlot(msg);
    if (guestsBelow) {
      if (previousResolved != null && next != null) {
        _timeService.applySlotClock(
          resolved: _timeService.clock.add(next.difference(previousResolved)),
        );
      }
      return;
    }
    _timeService.applySlotClock(resolved: next);
  }

  void _stampStoryClockAfter(ChatMessage? target) {
    if (target == null || target.isUser) return;
    final existing = Map<String, dynamic>.from(target.activeMetadata ?? {});
    existing['story_clock_after'] = _timeService.storyClockIso;
    target.activeMetadata = existing;
  }

  void _stampFinalClockOnMessage(ChatMessage? target) {
    if (target == null || target.isUser || !_clockRunning) return;
    _stampStoryClockAfter(target);
    final existing = Map<String, dynamic>.from(target.activeMetadata ?? {});
    if ((existing['time_skip_to'] as String? ?? '').isNotEmpty) {
      return;
    }
    final beat = _timeService.bodyTimeLabel;
    if (beat != null && beat.isNotEmpty) {
      existing['time_passed'] = beat;
      target.activeMetadata = existing;
      return;
    }
    final before = StoryClock.parse(knownStoryClockBefore(target));
    if (before == null) {
      _stampTimePassedChip(target);
      return;
    }
    final mins = _timeService.clock.difference(before).inMinutes;
    if (mins == 0) return;
    final label = timePassedLabel(
      minutes: mins < 0 ? 0 : mins,
      nextMorning: false,
      isSkip: false,
    );
    if (label != null && label.isNotEmpty) {
      existing['time_passed'] = label;
      target.activeMetadata = existing;
    }
  }

  /// Abort after B is visible: clock = before, after = before, no chip.
  void _abortVisibleSlotClock(ChatMessage? target, String? clockBeforeIso) {
    final beforeIso = target == null
        ? clockBeforeIso
        : (knownStoryClockBefore(target) ?? clockBeforeIso);
    _timeService.rewindToBeforeIso(beforeIso);
    if (target == null || target.isUser) return;
    final existing = Map<String, dynamic>.from(target.activeMetadata ?? {});
    existing['story_clock_after'] = _timeService.storyClockIso;
    existing.remove('time_passed');
    target.activeMetadata = existing;
  }

  /// Nudge / calendar-set: one writer. Clock stamps + time_nudged.
  /// Never inserts a full realism snapshot. Never touches user messages.
  void _syncActiveSlotClockAfterManualSet() {
    for (final msg in _messages.reversed) {
      if (msg.isUser) continue;
      if (msg.activeMetadata?['is_dream'] == true ||
          msg.activeMetadata?['is_chance_time_narration'] == true) {
        continue;
      }
      final iso = _timeService.storyClockIso;
      msg.metadata ??= {};
      msg.metadata!['story_clock_before'] = iso;
      msg.metadata!['story_clock_after'] = iso;
      msg.metadata!['time_nudged'] = true;
      final existing = Map<String, dynamic>.from(msg.activeMetadata ?? {});
      existing['story_clock_before'] = iso;
      existing['story_clock_after'] = iso;
      existing['time_nudged'] = true;
      final rs = existing['realism_state'];
      if (rs is Map) {
        rs['storyClock'] = iso;
        rs['timeOfDay'] = _timeService.timeOfDay;
        rs['dayCount'] = _timeService.dayCount;
        rs['storyStartDate'] = _timeService.storyStartDateIso;
        rs['time_nudged'] = true;
      }
      msg.activeMetadata = existing;
      break;
    }
  }

  void _applyResolvedImportClock(ChatMessage m) {
    _timeService.applySlotClock(resolved: _resolveMessageSlot(m));
  }

  void _putBackCapturedClock() {
    _timeService.restoreCapturedClock(sessionId: _currentSessionId);
    _timeService.clearCapturedClock();
  }
}
