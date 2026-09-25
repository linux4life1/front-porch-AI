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

  /// Visible slot, created once. Never [Map.from] — that shares the
  /// inner `realism_state` and then replaces the swipe map, so a later
  /// restore can pin pre-eval trust/needs.
  Map<String, dynamic> _clockWriteSlot(ChatMessage target) {
    final existing = target.activeMetadata;
    if (existing != null) return existing;
    final slot = <String, dynamic>{};
    target.metadata ??= slot;
    target.activeMetadata = slot;
    return slot;
  }

  /// Opening greeting: pair after == before == live. Not a nudge.
  void _stampOpeningClockPair() {
    final msg = _messages.isEmpty ? null : _messages.first;
    if (msg == null || msg.isUser) return;
    if (slotHasCompletePair(msg.activeMetadata)) return;
    final clock = _timeService.clock;
    writeSlotClockPair(_clockWriteSlot(msg), before: clock, after: clock);
    persistStoryClockBefore(msg, StoryClock.serializeClock(clock));
  }

  /// THE reader. Live clock = the visible tip slot's after. Never
  /// another swipe's after — a cancelled regen swipe must not inherit
  /// the rejected pair.
  void _applyTipClock() {
    final tip = _visibleTipMessage();
    if (tip == null) return;
    final after = slotClockAfter(tip.activeMetadata);
    if (after != null) _timeService.applySlotClock(resolved: after);
  }

  /// Fill missing pairs from the live clock / nearest real time.
  /// Mutates in-memory slots; the load path persists when this returns true.
  bool _backfillLoadedSlotClocks() {
    // The 24-row open window is not a clock. Guessing here treats the
    // first tail bot as the greeting (B1). Wait for the full history.
    if (_history.hasMore || _history.isBackfilling) return false;
    return backfillSlotClocks(
      _messages,
      liveClock: _timeService.clock,
      startDate: _timeService.startDate,
    );
  }

  /// Load / reload / fork / import: backfill then tip.after.
  void _syncLoadedSlotClocks() {
    try {
      _backfillLoadedSlotClocks();
    } catch (e, st) {
      debugPrint('[Clock] backfill failed: $e\n$st');
    }
    _applyTipClock();
  }

  /// Greeting overlay may re-seed the card clock. Session row is live.
  /// Waits for the full history so the 24-row window cannot guess.
  Future<void> _reloadSessionClockThenSync(Session s) async {
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
    );
    await _awaitHistoryHydrated();
    try {
      final changed = _backfillLoadedSlotClocks();
      _applyTipClock();
      if (changed) unawaited(_saveChat());
    } catch (e, st) {
      debugPrint('[Clock] load backfill failed: $e\n$st');
    }
  }

  /// Abort may only undo a clock change THIS turn made. Continue never
  /// ticks. Porch Life off never writes. Abort-write sets after=before
  /// on the kept tip so live clock equals that pair.
  void _abortSlotClockIfThisTurnTicked(_GenTurn t) {
    if (t.mode == GenerationMode.continue_) {
      _applyTipClock();
      return;
    }
    if (!_clockRunning) {
      _applyTipClock();
      return;
    }
    _writeSlotClock(t.streamTarget, kind: _SlotClockWrite.abort);
  }

  /// Tail-delete of a nudged tip restores the pre-nudge clock onto
  /// the new visible tip so hold-spec (clock == tip.after) and the
  /// pre-nudge pin agree.
  void _applyClockAfterDelete(ChatMessage deleted, {required bool wasTail}) {
    if (wasTail && deleted.activeMetadata?['time_nudged'] == true) {
      final restored =
          StoryClock.parse(deleted.activeMetadata?['nudge_from'] as String?) ??
          slotClockBefore(deleted.activeMetadata);
      if (restored != null) {
        final tip = _visibleTipMessage();
        if (tip != null) {
          writeSlotClockPair(
            _clockWriteSlot(tip),
            before: restored,
            after: restored,
          );
        }
        _timeService.applySlotClock(resolved: restored);
        return;
      }
    }
    _applyTipClock();
  }

  /// Pre-reply clock for regen evals. After backfill the pair exists.
  void _rewindClockToPreReply(ChatMessage lastMsg) {
    if (!_clockRunning) return;
    _timeService.captureLiveClock();
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

  /// Visible prefix has a user turn and a later bot reply.
  bool _prefixLeftTheOpening() {
    var sawUser = false;
    for (final m in _messages) {
      if (m.isUser) {
        sawUser = true;
        continue;
      }
      if (sawUser && m.sender != 'System') return true;
    }
    return false;
  }

  /// Day 1 of this story's start. Keeps [startDate]; TOD from the
  /// group time seed or the 1:1 card, else morning.
  void _seedLiveClockToStoryStart() {
    var tod = 'morning';
    String? startTime;
    if (_activeGroup != null) {
      final seed = parseGroupTimeSeed(
        _activeGroup!.defaultMemberRealismState,
        _activeGroup!.baselineRealismState,
      );
      if (seed != null) {
        tod = seed.timeOfDay;
        startTime = seed.storyStartTime;
      }
    } else {
      final ext = _activeCharacter?.frontPorchExtensions;
      if (ext != null) {
        if (ext.timeOfDay.isNotEmpty) tod = ext.timeOfDay;
        startTime = ext.storyStartTime;
      }
    }
    _timeService.seedFromV2OrExt(
      dayCount: 1,
      timeOfDay: tod,
      storyStartDate: _timeService.storyStartDateIso,
      storyStartTime: startTime,
    );
    _applySeededPassageOfTime();
  }

  /// Fork lands on the fork-point slot's clock. An unstamped
  /// greeting / pre-first-user slot is Day 1 of the start — load
  /// backfill may have painted the parent's live Day N. A lived-in
  /// snap or a pair already on Day 1 is left for [_applyTipClock].
  void _applyForkPointClock() {
    final tip = _visibleTipMessage();
    if (tip == null) return;
    if (_prefixLeftTheOpening()) {
      _applyTipClock();
      return;
    }
    if (slotHasAuthoredClock(tip.activeMetadata)) {
      _applyTipClock();
      return;
    }
    final after = slotClockAfter(tip.activeMetadata);
    if (after != null &&
        StoryClock.dayCountFor(after, _timeService.startDate) <= 1) {
      _applyTipClock();
      return;
    }
    _seedLiveClockToStoryStart();
    _writeSlotClock(tip, kind: _SlotClockWrite.seed);
  }

  /// THE writer. Tick / nudge / abort / seed all land here, then
  /// [_applyTipClock].
  void _writeSlotClock(ChatMessage? target, {required _SlotClockWrite kind}) {
    if (target == null || target.isUser) return;
    if (kind == _SlotClockWrite.seed) {
      final clock = _timeService.clock;
      writeSlotClockPair(_clockWriteSlot(target), before: clock, after: clock);
      _applyTipClock();
      return;
    }
    if (!_clockRunning) return;

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
      }
    }

    if (kind == _SlotClockWrite.tick || kind == _SlotClockWrite.nudge) {
      persistStoryClockBefore(target, StoryClock.serializeClock(before));
    }
    final slot = _clockWriteSlot(target);
    writeSlotClockPair(
      slot,
      before: before,
      after: after,
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
        before: before,
        after: after,
        timeNudged: true,
      );
    }
    _applyTipClock();
  }
}

enum _SlotClockWrite { tick, nudge, abort, seed }
