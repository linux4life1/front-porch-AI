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
  /// Porch Life off never writes the clock.
  void _stampOpeningClockPair() {
    if (!_clockRunning) return;
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
    if (!_clockRunning) return false;
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
    } else {
      _writeSlotClock(t.streamTarget, kind: _SlotClockWrite.abort);
    }
    _setGuestStatus('Reply kept. Scene time and needs weren\'t updated.');
  }

  /// Tail-delete of a nudged tip restores the pre-nudge clock onto
  /// the new visible tip so hold-spec (clock == tip.after) and the
  /// pre-nudge pin agree. Non-nudge tail delete writes the deleted
  /// before only when the new tip has no pair — a greeting that
  /// already stores after (load neighbour, opening pair) is the
  /// remaining tip clock. Nudge always overwrites.
  void _applyClockAfterDelete(ChatMessage deleted, {required bool wasTail}) {
    if (wasTail) {
      final nudged = deleted.activeMetadata?['time_nudged'] == true;
      final restored = nudged
          ? StoryClock.parse(
                  deleted.activeMetadata?['nudge_from'] as String?,
                ) ??
                slotClockBefore(deleted.activeMetadata)
          : slotClockBefore(deleted.activeMetadata) ??
                StoryClock.parse(knownStoryClockBefore(deleted));
      if (restored != null) {
        final tip = _visibleTipMessage();
        if (!nudged && tip != null && slotHasCompletePair(tip.activeMetadata)) {
          _applyTipClock();
          return;
        }
        if (tip != null && _clockRunning) {
          writeSlotClockPair(
            _clockWriteSlot(tip),
            before: restored,
            after: restored,
          );
          persistStoryClockBefore(tip, StoryClock.serializeClock(restored));
        }
        _timeService.applySlotClock(resolved: restored);
        return;
      }
    }
    final tip = _visibleTipMessage();
    if (tip != null &&
        _clockRunning &&
        !slotHasCompletePair(tip.activeMetadata)) {
      final greetingClock = _openingGreetingSnap();
      final after = resolveSlotAfter(
        clockSlotForResolve(tip),
        isTip: true,
        liveClock: _timeService.clock,
        startDate: _timeService.startDate,
        greetingClock: greetingClock,
        neighbourStamp: _nearestStoredStamp(tip, greetingClock: greetingClock),
      );
      if (after != null) {
        writeSlotClockPair(_clockWriteSlot(tip), before: after, after: after);
        persistStoryClockBefore(tip, StoryClock.serializeClock(after));
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

  /// Day 1 of this story's start. Does not mutate the live clock —
  /// the writer / [_applyTipClock] do that from the resolved after.
  DateTime _day1OfStoryStart() {
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
    final start = _timeService.startDate;
    final hhmm = StoryClock.parseHHMM(startTime);
    if (hhmm != null) {
      return DateTime.utc(start.year, start.month, start.day, hhmm.$1, hhmm.$2);
    }
    return StoryClock.representativeTime(start, tod);
  }

  DateTime? _openingGreetingSnap() {
    if (_messages.isEmpty) return null;
    final first = _messages.first;
    if (first.isUser || first.sender == 'System') return null;
    final raw = first.activeMetadata?['realism_state'];
    if (raw is! Map) return null;
    return StoryClock.parse(raw['storyClock'] as String?);
  }

  DateTime? _nearestStoredStamp(ChatMessage tip, {DateTime? greetingClock}) {
    DateTime? found;
    for (final msg in _messages) {
      if (identical(msg, tip) || msg.sender == 'System') continue;
      final stamp = resolveSlotAfter(
        clockSlotForResolve(msg),
        isTip: false,
        liveClock: _timeService.clock,
        startDate: _timeService.startDate,
        greetingClock: greetingClock,
      );
      if (stamp != null) found = stamp;
    }
    return found;
  }

  /// Fork lands on the fork-point slot via [resolveSlotAfter]. Day 1
  /// of the start is the empty-tip live clock only when the fork is
  /// at or before the first user turn and the slot has nothing stored.
  /// Porch Life off still reads tip.after into the live clock.
  void _applyForkPointClock() {
    final tip = _visibleTipMessage();
    if (tip == null) return;
    // Refresh derived day pairs against the current start. The load
    // marker must not leave a pair measured against an old start.
    _backfillLoadedSlotClocks();
    final slot = clockSlotForResolve(tip);
    final greetingClock = _openingGreetingSnap();
    final emptyPreUser =
        !_prefixLeftTheOpening() &&
        !slotHasAuthoredClock(slot) &&
        !slotHasStoredClockData(slot, greetingClock: greetingClock);
    final live = emptyPreUser ? _day1OfStoryStart() : _timeService.clock;
    final after = resolveSlotAfter(
      slot,
      isTip: true,
      liveClock: live,
      startDate: _timeService.startDate,
      greetingClock: greetingClock,
      neighbourStamp: _nearestStoredStamp(tip, greetingClock: greetingClock),
    );
    if (after != null &&
        _clockRunning &&
        slotClockAfter(tip.activeMetadata) != after) {
      writeSlotClockPair(_clockWriteSlot(tip), before: after, after: after);
      persistStoryClockBefore(tip, StoryClock.serializeClock(after));
    }
    _applyTipClock();
  }

  /// THE writer. Tick / nudge / abort / seed all land here, then
  /// [_applyTipClock].
  void _writeSlotClock(ChatMessage? target, {required _SlotClockWrite kind}) {
    if (target == null || target.isUser) return;
    if (!_clockRunning) return;
    if (kind == _SlotClockWrite.seed) {
      final clock = _timeService.clock;
      writeSlotClockPair(_clockWriteSlot(target), before: clock, after: clock);
      _applyTipClock();
      return;
    }

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
      } else if (_timeService.bodyTimeLabel == 'Next morning') {
        chip = 'Next morning';
      } else {
        chip = timePassedLabel(
          minutes: after.difference(before).inMinutes,
          nextMorning: false,
          isSkip: false,
        );
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
