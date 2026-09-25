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

  bool get _historyClockIncomplete =>
      _history.hasMore || _history.isBackfilling;

  /// Message 0 only, and only on a complete history. A 24-row tail
  /// must not treat its first bot as the greeting (HIGH-1 / B1).
  DateTime? _greetingClockForResolve() {
    if (_historyClockIncomplete) return null;
    return frozenDetectionGreetingClock(_messages);
  }

  /// THE reader. Live clock = the visible tip slot's resolved after.
  /// Never another swipe's after — a cancelled regen swipe must not
  /// inherit the rejected pair. Every path goes through [resolveSlotAfter].
  /// Porch Life off never moves the live clock — including snap and
  /// dayCount rungs.
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
    final greetingClock = _greetingClockForResolve();
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
    // Greeting-as-tip: own snap / dayCount are leftover card copies,
    // not a stored pair. Tip reads pair or live (HIGH-1).
    if (greetingSlot && slot != null && slotClockAfter(slot) == null) {
      final copy = Map<String, dynamic>.from(slot);
      copy.remove('realism_state');
      copy.remove('story_day');
      slot = copy;
    }
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

  /// Fill missing pairs from the live clock / nearest real time.
  /// Mutates in-memory slots; the load path persists when this returns true.
  bool _backfillLoadedSlotClocks() {
    // The 24-row open window is not a clock. Guessing here treats the
    // first tail bot as the greeting (B1). Wait for the full history.
    if (!_clockRunning) return false;
    if (_historyClockIncomplete) return false;
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

  /// Session scalars first, then tip resolve. Live must not stay
  /// on the TimeService default (today) while greeting-as-tip reads it.
  Future<void> _reloadSessionClockThenSync(Session s) async {
    _timeService.clearCapturedClock();
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
    );
    _applyTipClock();
    final sid = _currentSessionId;
    final epoch = _history.epoch;
    final pending = _history.backfill;
    if (pending != null) {
      unawaited(
        pending.then((_) {
          if (sid != _currentSessionId || epoch != _history.epoch) return;
          _finishLoadedSlotClockBackfill();
        }),
      );
      return;
    }
    _finishLoadedSlotClockBackfill();
  }

  void _finishLoadedSlotClockBackfill() {
    try {
      final changed = _backfillLoadedSlotClocks();
      _applyTipClock();
      if (changed) unawaited(_saveChat());
      notifyListeners();
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
    } else if (!_clockRunning) {
      _applyTipClock();
    } else {
      _writeSlotClock(t.streamTarget, kind: _SlotClockWrite.abort);
      _applyTipClock();
    }
    _setGuestStatus('Reply kept. Scene time and needs weren\'t updated.');
  }

  /// Tail-delete goes through the one resolver. Nudge overwrites with
  /// the pre-nudge clock via resolved(after). Otherwise the remaining
  /// tip resolves against the deleted before so a greeting that already
  /// stores after keeps it at step 1.
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
          _writeSlotClock(
            _visibleTipMessage(),
            kind: _SlotClockWrite.resolved,
            after: restored,
          );
          return;
        }
      }
      final deletedSlot = deleted.activeMetadata;
      final storedBefore = slotClockBefore(deletedSlot);
      final start = _timeService.startDate;
      final day1 = day1OfStart(start);
      // Only a stored before. Chip-derived after-minus-chip (even
      // when floored at Day 1) is not stored — keep live.
      DateTime? rewind;
      if (storedBefore != null &&
          !slotBeforeIsChipDerived(deletedSlot, startDate: start)) {
        rewind = storedBefore.isBefore(day1) ? day1 : storedBefore;
      }
      rewind ??= _timeService.clock;
      final tip = _visibleTipMessage();
      if (tip != null) {
        final after = _resolveVisibleAfter(tip: tip, liveClock: rewind);
        if (after != null) {
          _writeSlotClock(tip, kind: _SlotClockWrite.resolved, after: after);
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
    _rewindLiveToSlotBefore(lastMsg);
  }

  /// First known before for this message position. A frozen Day-1
  /// snap is not a pre-reply — first regen must rewind to the slot's
  /// real before (or live) and add only the new swipe's minutes.
  void _discoverAndPersistMessageBefore(ChatMessage msg) {
    if (!_clockRunning) return;
    var before = knownStoryClockBefore(msg);
    final slot = msg.activeMetadata;
    final snap = slotSnapClock(slot);
    // Regen pops the tip before rewind. The popped snap is still the
    // earliest-reply greeting clock when message 0 has no stamp.
    final greeting = _greetingClockForResolve() ?? snap;
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
    final parsed = StoryClock.parse(before);
    if (parsed != null) {
      _writeSlotClock(msg, kind: _SlotClockWrite.beforeOnly, before: parsed);
    }
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

  /// Day 1 of this story's persisted start. Never [StoryClock.todayAnchor]
  /// when the chat already has a start date (session, parent fork, card).
  DateTime _day1OfStoryStart({DateTime? startDate}) {
    var tod = 'morning';
    String? startTime;
    String? cardStart;
    if (_activeGroup != null) {
      final seed = parseGroupTimeSeed(
        _activeGroup!.defaultMemberRealismState,
        _activeGroup!.baselineRealismState,
      );
      if (seed != null) {
        tod = seed.timeOfDay;
        startTime = seed.storyStartTime;
        cardStart = seed.storyStartDate;
      }
    } else {
      final ext = _activeCharacter?.frontPorchExtensions;
      if (ext != null) {
        if (ext.timeOfDay.isNotEmpty) tod = ext.timeOfDay;
        startTime = ext.storyStartTime;
        cardStart = ext.storyStartDate;
      }
    }
    final start = _persistedStoryStart(
      startDate: startDate,
      cardStartDate: cardStart,
    );
    return day1OfStart(start, timeOfDay: tod, startTime: startTime);
  }

  /// Session / parent / card start wins. Today is only a fresh chat.
  DateTime _persistedStoryStart({DateTime? startDate, String? cardStartDate}) {
    if (startDate != null) return StoryClock.dateOnly(startDate);
    final loaded = StoryClock.dateOnly(_timeService.startDate);
    final today = StoryClock.todayAnchor();
    if (loaded != today) return loaded;
    final card = StoryClock.parse(cardStartDate);
    if (card != null) return StoryClock.dateOnly(card);
    return loaded;
  }

  DateTime? _nearestStoredStamp(ChatMessage tip, {DateTime? greetingClock}) {
    if (_historyClockIncomplete) return null;
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
  void _applyForkPointClock({DateTime? parentStartDate}) {
    final leftOpening = _prefixLeftTheOpening();
    final tip = _visibleTipMessage();
    if (tip == null) {
      if (!leftOpening) _applyDay1Clock(startDate: parentStartDate);
      return;
    }
    _backfillLoadedSlotClocks();
    final greetingClock = _greetingClockForResolve();
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
      _applyDay1Clock(startDate: parentStartDate, tip: tip);
      return;
    }
    final after = _resolveVisibleAfter(tip: tip, liveClock: _timeService.clock);
    if (after != null) {
      _writeSlotClock(tip, kind: _SlotClockWrite.resolved, after: after);
      return;
    }
    _applyTipClock();
  }
}
