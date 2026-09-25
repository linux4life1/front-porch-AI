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

  /// THE reader. Live clock = the visible tip slot's resolved after.
  /// Never another swipe's after — a cancelled regen swipe must not
  /// inherit the rejected pair. Every path goes through [resolveSlotAfter].
  /// Porch Life off never moves the live clock.
  void _applyTipClock() {
    if (!_clockRunning) return;
    final after = _resolveVisibleAfter();
    if (after != null) _timeService.applySlotClock(resolved: after);
  }

  /// One ladder for the visible tip. Uses the stored slot so load
  /// recover and abort keep step 1. Tip-live ranks above own before
  /// (clamp floor), greeting-as-tip included. A far neighbour stamp
  /// stays below tip-live. Day 1 is the fork empty-pre-user seed.
  DateTime? _resolveVisibleAfter({ChatMessage? tip, DateTime? liveClock}) {
    final target = tip ?? _visibleTipMessage();
    if (target == null) return null;
    final greetingClock = _openingGreetingSnap();
    final clock = liveClock ?? _timeService.clock;
    final idx = _messages.indexWhere((m) => identical(m, target));
    final greetingSlot =
        idx == 0 && !target.isUser && target.sender != 'System';
    final answered = answeredUserClock(
      _messages,
      idx,
      liveClock: clock,
      startDate: _timeService.startDate,
      greetingClock: greetingClock,
      neighbourStamp: idx > 0
          ? _nearestStoredStamp(
              _messages[idx - 1],
              greetingClock: greetingClock,
            )
          : null,
    );
    var slot = target.activeMetadata;
    // A load-guessed live pair is not own after. It must not hide
    // the answering user's story_day (clamp floor above a Day-1 live).
    if (answered != null &&
        slotHasCompletePair(slot) &&
        !slotHasAuthoredClock(slot) &&
        slotClockAfter(slot) == clock) {
      final copy = Map<String, dynamic>.from(slot!);
      copy.remove('story_clock_after');
      copy.remove('story_clock_before');
      slot = copy;
    }
    return resolveSlotAfter(
      slot,
      isTip: true,
      liveClock: clock,
      startDate: _timeService.startDate,
      greetingClock: greetingClock,
      neighbourStamp: _nearestStoredStamp(target, greetingClock: greetingClock),
      answeredUserBefore: answered,
      isGreeting: greetingSlot,
      greetingIsTip: greetingSlot,
    );
  }

  void _writeResolvedTipAfter(ChatMessage tip, DateTime after) {
    if (!_clockRunning) return;
    if (slotClockAfter(tip.activeMetadata) == after) return;
    final before = slotClockBefore(tip.activeMetadata) ?? after;
    writeSlotClockPair(_clockWriteSlot(tip), before: before, after: after);
    persistStoryClockBefore(tip, StoryClock.serializeClock(before));
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

  /// Tail-delete goes through the one resolver. Nudge overwrites with
  /// the pre-nudge clock. Otherwise the remaining tip resolves against
  /// the deleted before (not the still-advanced live clock) so a
  /// greeting that already stores after (Day-1 00:10) keeps it at
  /// step 1, and an empty remaining tip takes the rewind at step 6.
  void _applyClockAfterDelete(ChatMessage deleted, {required bool wasTail}) {
    if (wasTail) {
      final nudged = deleted.activeMetadata?['time_nudged'] == true;
      if (nudged) {
        final restored =
            StoryClock.parse(
              deleted.activeMetadata?['nudge_from'] as String?,
            ) ??
            slotClockBefore(deleted.activeMetadata);
        if (restored != null) {
          final tip = _visibleTipMessage();
          if (tip != null) _writeResolvedTipAfter(tip, restored);
          if (_clockRunning) {
            _timeService.applySlotClock(resolved: restored);
          }
          return;
        }
      }
      final rewind =
          slotClockBefore(deleted.activeMetadata) ??
          StoryClock.parse(knownStoryClockBefore(deleted)) ??
          _timeService.clock;
      final tip = _visibleTipMessage();
      if (tip != null) {
        final after = _resolveVisibleAfter(tip: tip, liveClock: rewind);
        if (after != null) {
          _writeResolvedTipAfter(tip, after);
          if (_clockRunning) {
            _timeService.applySlotClock(resolved: after);
          }
          return;
        }
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

  /// First known before for this message position. A frozen Day-1
  /// snap is not a pre-reply — first regen must rewind to the slot's
  /// real before (or live) and add only the new swipe's minutes.
  void _discoverAndPersistMessageBefore(ChatMessage msg) {
    var before = knownStoryClockBefore(msg);
    final slot = msg.activeMetadata;
    final snap = slotSnapClock(slot);
    // Regen pops the tip before rewind. The popped snap is still the
    // earliest-reply greeting clock when message 0 has no stamp.
    final greeting = _openingGreetingSnap() ?? snap;
    final known = StoryClock.parse(before);
    if (known != null &&
        snap != null &&
        known == snap &&
        slotSnapIsFrozen(snap, greetingClock: greeting)) {
      before = null;
    }
    if (before == null) {
      final mins = minutesRecordedForClockRewind(slot);
      final storedAfter = slotClockAfter(slot);
      final afterIsFrozen =
          storedAfter != null &&
          slotSnapIsFrozen(storedAfter, greetingClock: greeting);
      if (mins != null && mins > 0 && storedAfter != null && !afterIsFrozen) {
        before = StoryClock.serializeClock(
          storedAfter.subtract(Duration(minutes: mins)),
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

  DateTime? _openingGreetingSnap() => frozenDetectionGreetingClock(_messages);

  DateTime? _nearestStoredStamp(ChatMessage tip, {DateTime? greetingClock}) {
    final idx = _messages.indexWhere((m) => identical(m, tip));
    final earlierAfter = <int, DateTime>{};
    final laterBefore = <int, DateTime>{};
    for (var i = 0; i < _messages.length; i++) {
      if (i == idx || _messages[i].sender == 'System') continue;
      final slot = clockSlotForResolve(_messages[i]);
      final stamp = resolveSlotAfter(
        slot,
        isTip: false,
        liveClock: _timeService.clock,
        startDate: _timeService.startDate,
        greetingClock: greetingClock,
      );
      if (stamp != null) earlierAfter[i] = stamp;
      final before =
          slotClockBefore(slot) ??
          StoryClock.parse(knownStoryClockBefore(_messages[i]));
      if (before != null) laterBefore[i] = before;
    }
    return directionalNeighbourStamp(
      index: idx,
      earlierAfter: earlierAfter,
      laterBefore: laterBefore,
    );
  }

  /// Fork lands on the fork-point slot via the one resolver. Day 1
  /// of the start applies only at or before the first user turn
  /// with nothing stored — a transcript that opens with a user turn
  /// and already has a later bot is not that case. A neighbour
  /// story_day is not this slot's clock (rung 6 is live).
  void _applyForkPointClock() {
    final leftOpening = _prefixLeftTheOpening();
    final tip = _visibleTipMessage();
    if (tip == null) {
      if (!leftOpening && _clockRunning) {
        _timeService.applySlotClock(resolved: _day1OfStoryStart());
      }
      return;
    }
    _backfillLoadedSlotClocks();
    final greetingClock = _openingGreetingSnap();
    final slot = tip.activeMetadata;
    final guessedLive =
        slotHasCompletePair(slot) &&
        !slotHasAuthoredClock(slot) &&
        slotClockAfter(slot) == _timeService.clock;
    final emptyPreUser =
        !leftOpening &&
        !slotHasAuthoredClock(slot) &&
        (!slotHasStoredClockData(slot, greetingClock: greetingClock) ||
            guessedLive);
    if (emptyPreUser) {
      final day1 = _day1OfStoryStart();
      _writeResolvedTipAfter(tip, day1);
      if (_clockRunning) {
        _timeService.applySlotClock(resolved: day1);
      }
      return;
    }
    final after = _resolveVisibleAfter(tip: tip, liveClock: _timeService.clock);
    if (after != null) {
      _writeResolvedTipAfter(tip, after);
      if (_clockRunning) {
        _timeService.applySlotClock(resolved: after);
      }
      return;
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
