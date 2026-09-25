// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

enum _SlotClockWrite { tick, nudge, abort, seed, resolved, beforeOnly }

/// THE writer. Every slot mutation lands here, then [_applyTipClock].
extension ChatServiceMessageClockWrite on ChatService {
  void _writeSlotClock(
    ChatMessage? target, {
    required _SlotClockWrite kind,
    DateTime? after,
    DateTime? before,
  }) {
    if (target == null || target.isUser) return;
    if (!_clockRunning) return;

    if (kind == _SlotClockWrite.seed) {
      if (slotHasCompletePair(target.activeMetadata)) {
        _applyTipClock();
        return;
      }
      final clock = _timeService.clock;
      writeSlotClockPair(_clockWriteSlot(target), before: clock, after: clock);
      persistStoryClockBefore(target, StoryClock.serializeClock(clock));
      _applyTipClock();
      return;
    }

    if (kind == _SlotClockWrite.resolved) {
      final resolved = after;
      if (resolved == null) return;
      final storedBefore = slotClockBefore(target.activeMetadata) ?? resolved;
      writeSlotClockPair(
        _clockWriteSlot(target),
        before: storedBefore,
        after: resolved,
      );
      persistStoryClockBefore(target, StoryClock.serializeClock(storedBefore));
      _applyTipClock();
      return;
    }

    if (kind == _SlotClockWrite.beforeOnly) {
      final stamp = before;
      if (stamp == null) return;
      persistStoryClockBefore(target, StoryClock.serializeClock(stamp));
      _applyTipClock();
      return;
    }

    final known = StoryClock.parse(knownStoryClockBefore(target));
    final slotBefore = switch (kind) {
      _SlotClockWrite.nudge => _timeService.clock,
      _ => known ?? _timeService.clock,
    };
    final slotAfter = switch (kind) {
      _SlotClockWrite.abort => slotBefore,
      _ => _timeService.clock,
    };

    String? chip;
    var clearChip = false;
    if (kind == _SlotClockWrite.abort) {
      clearChip = true;
    } else if (kind == _SlotClockWrite.tick) {
      final existing = target.activeMetadata;
      if ((existing?['time_passed'] as String?) == 'Next morning') {
        chip = 'Next morning';
      } else if ((existing?['time_skip_to'] as String? ?? '').isNotEmpty) {
        chip = null;
      } else if (_timeService.bodyTimeLabel == 'Next morning') {
        chip = 'Next morning';
      } else {
        chip = timePassedLabel(
          minutes: slotAfter.difference(slotBefore).inMinutes,
          nextMorning: false,
          isSkip: false,
        );
      }
    }

    if (kind == _SlotClockWrite.tick || kind == _SlotClockWrite.nudge) {
      persistStoryClockBefore(target, StoryClock.serializeClock(slotBefore));
    }
    final slot = _clockWriteSlot(target);
    writeSlotClockPair(
      slot,
      before: slotBefore,
      after: slotAfter,
      timePassed: chip,
      clearChip: clearChip,
      timeNudged: kind == _SlotClockWrite.nudge,
    );
    if (kind == _SlotClockWrite.nudge && _pendingNudgeBefore != null) {
      final from = StoryClock.serializeClock(_pendingNudgeBefore!);
      slot['nudge_from'] = from;
      if (target.metadata != null && !identical(target.metadata, slot)) {
        target.metadata!['nudge_from'] = from;
      }
    }
    _pendingNudgeBefore = null;
    if (kind == _SlotClockWrite.nudge &&
        target.metadata != null &&
        !identical(target.metadata, target.activeMetadata)) {
      writeSlotClockPair(
        target.metadata!,
        before: slotBefore,
        after: slotAfter,
        timeNudged: true,
      );
    }
    _applyTipClock();
  }

  /// No-tip Day-1 fork / empty-pre-user share this live write.
  /// The only [applySlotClock] outside the tip reader and regen rewind.
  void _applyDay1Clock({DateTime? startDate}) {
    if (!_clockRunning) return;
    _timeService.applySlotClock(
      resolved: _day1OfStoryStart(startDate: startDate),
    );
  }

  /// Regen rewind: persist the slot before, then move live to it.
  void _rewindLiveToSlotBefore(ChatMessage lastMsg) {
    _discoverAndPersistMessageBefore(lastMsg);
    final before = StoryClock.parse(knownStoryClockBefore(lastMsg));
    if (before == null) return;
    _timeService.applySlotClock(resolved: before);
  }

  void _restoreCapturedThroughReader({String? sessionId}) {
    _timeService.restoreCapturedClock(sessionId: sessionId);
    _applyTipClock();
  }
}
