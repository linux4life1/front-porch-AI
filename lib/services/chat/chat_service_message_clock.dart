// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../chat_service.dart';

/// One clock path: backfill pairs at load/import, live = tip.after,
/// every mutation goes through [_writeSlotClock] then [_applyTipClock].
extension ChatServiceMessageClock on ChatService {
  /// Last non-user, non-system bot — guests below a host are the tip.
  ChatMessage? _visibleTipMessage() {
    for (final msg in _messages.reversed) {
      if (msg.isUser || msg.sender == 'System') continue;
      return msg;
    }
    return null;
  }

  /// THE reader. Live clock = the visible tip slot's after.
  void _applyTipClock() {
    final after = slotClockAfter(_visibleTipMessage()?.activeMetadata);
    if (after != null) _timeService.applySlotClock(resolved: after);
  }

  /// Fill missing pairs from the live clock / nearest real time, persist.
  bool _backfillLoadedSlotClocks() {
    return backfillSlotClocks(
      _messages,
      liveClock: _timeService.clock,
      startDate: _timeService.startDate,
    );
  }

  /// Load / reload / fork / import: backfill then tip.after.
  void _syncLoadedSlotClocks() {
    _backfillLoadedSlotClocks();
    _applyTipClock();
  }

  /// Greeting overlay may re-seed the card clock. Session row is live.
  void _reloadSessionClockThenSync(Session s) {
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
    );
    _syncLoadedSlotClocks();
  }

  /// Pre-reply clock for regen evals. After backfill the pair exists.
  void _rewindClockToPreReply(ChatMessage lastMsg) {
    if (!_clockRunning) return;
    _discoverAndPersistMessageBefore(lastMsg);
    _timeService.rewindToBeforeIso(knownStoryClockBefore(lastMsg));
  }

  /// First known before for this message position.
  void _discoverAndPersistMessageBefore(ChatMessage msg) {
    var before = knownStoryClockBefore(msg);
    if (before == null) {
      final mins = minutesRecordedForClockRewind(msg.activeMetadata);
      if (mins != null && mins > 0) {
        final from = slotClockAfter(msg.activeMetadata) ?? _timeService.clock;
        before = StoryClock.serializeClock(
          from.subtract(Duration(minutes: mins)),
        );
      } else {
        before = _timeService.storyClockIso;
      }
    }
    persistStoryClockBefore(msg, before);
  }

  /// THE writer. Tick / nudge / abort all land here, then [_applyTipClock].
  void _writeSlotClock(ChatMessage? target, {required _SlotClockWrite kind}) {
    if (target == null || target.isUser) return;
    if (kind != _SlotClockWrite.abort && !_clockRunning) return;

    final known = StoryClock.parse(knownStoryClockBefore(target));
    final before = switch (kind) {
      _SlotClockWrite.nudge => _timeService.clock,
      _ => known ?? _timeService.clock,
    };
    final after = switch (kind) {
      _SlotClockWrite.abort => before,
      _ => _timeService.clock,
    };

    String? chip;
    var clearChip = false;
    if (kind == _SlotClockWrite.abort) {
      clearChip = true;
    } else if (kind == _SlotClockWrite.tick) {
      final existing = target.activeMetadata;
      if ((existing?['time_skip_to'] as String? ?? '').isNotEmpty) {
        chip = null;
      } else {
        chip = _timeService.bodyTimeLabel;
        if (chip == null || chip.isEmpty) {
          final mins = after.difference(before).inMinutes;
          if (mins != 0) {
            chip = timePassedLabel(
              minutes: mins < 0 ? 0 : mins,
              nextMorning: false,
              isSkip: false,
            );
          }
        }
      }
    }

    if (kind == _SlotClockWrite.tick || kind == _SlotClockWrite.nudge) {
      persistStoryClockBefore(target, StoryClock.serializeClock(before));
    }
    final slot = Map<String, dynamic>.from(target.activeMetadata ?? {});
    writeSlotClockPair(
      slot,
      before: before,
      after: after,
      timePassed: chip,
      clearChip: clearChip,
      timeNudged: kind == _SlotClockWrite.nudge,
    );
    target.activeMetadata = slot;
    if (kind == _SlotClockWrite.nudge) {
      target.metadata ??= {};
      writeSlotClockPair(
        target.metadata!,
        before: before,
        after: after,
        timeNudged: true,
      );
    }
    _applyTipClock();
  }
}

enum _SlotClockWrite { tick, nudge, abort }
