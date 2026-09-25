// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// One clock contract: message-level before, per-slot after, captured
/// live clock+start on regen fail/cancel/abort. Snap is swipe/fork
/// fallback only when after and chip minutes are missing.
extension ChatServiceMessageClock on ChatService {
  bool _clockWasNudged(ChatMessage msg) {
    final state = msg.activeMetadata?['realism_state'];
    return state is Map && state['time_nudged'] == true;
  }

  Map<String, dynamic>? _slotSnap(ChatMessage msg) {
    final raw = msg.activeMetadata?['realism_state'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  DateTime? _resolvedSlotClock(ChatMessage msg) {
    final after = StoryClock.parse(
      msg.activeMetadata?['story_clock_after'] as String?,
    );
    if (after != null) return after;
    final mins = minutesRecordedForClockRewind(msg.activeMetadata);
    final before = StoryClock.parse(knownStoryClockBefore(msg));
    if (before != null && mins != null && mins > 0) {
      return before.add(Duration(minutes: mins));
    }
    final snap = StoryClock.parse(_slotSnap(msg)?['storyClock'] as String?);
    if (snap != null) return snap;
    return before;
  }

  /// First known before for this message position. Persist on the message
  /// and every existing slot so later regen/delete never subtract another
  /// swipe. Chip inference uses the ACTIVE slot only.
  void _discoverAndPersistMessageBefore(ChatMessage msg) {
    var before = knownStoryClockBefore(msg);
    if (before == null) {
      final mins = minutesRecordedForClockRewind(msg.activeMetadata);
      if (mins != null && mins > 0) {
        final after = StoryClock.parse(
          msg.activeMetadata?['story_clock_after'] as String?,
        );
        final snap = StoryClock.parse(_slotSnap(msg)?['storyClock'] as String?);
        final from = after ?? snap ?? _timeService.clock;
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
    if (guestsBelow && previousResolved != null) {
      final next = _resolvedSlotClock(msg);
      if (next != null) {
        _timeService.applySlotClock(
          after: StoryClock.serializeClock(
            _timeService.clock.add(next.difference(previousResolved)),
          ),
        );
      }
      return;
    }
    _timeService.applySlotClock(
      after: msg.activeMetadata?['story_clock_after'] as String?,
      before: knownStoryClockBefore(msg),
      minutes: minutesRecordedForClockRewind(msg.activeMetadata),
      snap: _slotSnap(msg),
    );
  }

  void _stampStoryClockAfter(ChatMessage? target) {
    if (target == null || target.isUser) return;
    final existing = Map<String, dynamic>.from(target.activeMetadata ?? {});
    existing['story_clock_after'] = _timeService.storyClockIso;
    target.activeMetadata = existing;
  }

  void _stampFinalClockOnMessage(ChatMessage? target) {
    if (target == null || target.isUser) return;
    _stampStoryClockAfter(target);
    final before = StoryClock.parse(knownStoryClockBefore(target));
    if (before != null) {
      final mins = _timeService.clock.difference(before).inMinutes;
      final label = timePassedLabel(
        minutes: mins < 0 ? 0 : mins,
        nextMorning: false,
        isSkip: false,
      );
      if (label != null && label.isNotEmpty) {
        final existing = Map<String, dynamic>.from(target.activeMetadata ?? {});
        if ((existing['time_skip_to'] as String? ?? '').isEmpty) {
          existing['time_passed'] = label;
          target.activeMetadata = existing;
        }
      }
    } else {
      _stampTimePassedChip(target);
    }
  }

  void _discardStampedAfter(ChatMessage? target) {
    if (target == null) return;
    final existing = target.activeMetadata;
    if (existing == null) return;
    existing.remove('story_clock_after');
    existing.remove('time_passed');
  }

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
      final existing = Map<String, dynamic>.from(msg.activeMetadata ?? {});
      existing['story_clock_before'] = iso;
      existing['story_clock_after'] = iso;
      final rs = existing['realism_state'];
      if (rs is Map) {
        rs['storyClock'] = iso;
        rs['timeOfDay'] = _timeService.timeOfDay;
        rs['dayCount'] = _timeService.dayCount;
        rs['storyStartDate'] = _timeService.storyStartDateIso;
        rs['time_nudged'] = true;
      } else {
        existing['realism_state'] = _captureRealismState();
        existing['realism_state']['time_nudged'] = true;
      }
      msg.activeMetadata = existing;
      break;
    }
  }

  bool _importedClockShouldApply(ChatMessage m) {
    if (m.activeMetadata?['story_clock_after'] is String) return true;
    if (knownStoryClockBefore(m) != null) return true;
    final rs = m.activeMetadata?['realism_state'];
    if (rs is! Map) return false;
    if (snapIsFrozenGreeting(
      Map<String, dynamic>.from(rs),
      _timeService.clock,
    )) {
      return false;
    }
    return StoryClock.parse(rs['storyClock'] as String?) != null;
  }

  void _putBackCapturedClock() {
    _timeService.restoreCapturedClock(sessionId: _currentSessionId);
    _timeService.clearCapturedClock();
  }
}
