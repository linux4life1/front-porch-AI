// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/chat/session_open_window.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// The open chat as the story clock sees it. Every getter runs live, so
/// Porch Life Passage of Time flips take effect on the next call.
class StoryClockScope {
  const StoryClockScope({
    required this.messages,
    required this.history,
    required this.time,
    required this.clockRunning,
    required this.activeGroup,
    required this.activeCharacter,
  });

  /// The chat's in-memory message list (the same list object, not a copy).
  final List<ChatMessage> messages;
  final SessionHistoryWindow history;
  final TimeService Function() time;

  /// Porch Life `passageOfTimeDefault`, read live.
  final bool Function() clockRunning;
  final GroupChat? Function() activeGroup;
  final CharacterCard? Function() activeCharacter;
}

/// One clock path, read side: live = the visible tip slot's resolved
/// after. Mutations go through [StoryClockWriter] and then
/// [applyTipClock].
class StoryClockReader {
  StoryClockReader(this._scope);

  final StoryClockScope _scope;

  List<ChatMessage> get _messages => _scope.messages;
  TimeService get _timeService => _scope.time();

  /// Last non-user, non-system bot — guests below a host are the tip.
  ChatMessage? visibleTipMessage() {
    for (final msg in _messages.reversed) {
      if (msg.isUser || msg.sender == 'System') continue;
      return msg;
    }
    return null;
  }

  bool get _historyClockIncomplete =>
      _scope.history.hasMore || _scope.history.isBackfilling;

  /// Message 0 only, and only on a complete history. A 24-row tail
  /// must not treat its first bot as the greeting (HIGH-1 / B1).
  DateTime? greetingClockForResolve() {
    if (_historyClockIncomplete) return null;
    return frozenDetectionGreetingClock(_messages);
  }

  /// THE reader. Live clock = the visible tip slot's resolved after.
  /// Never another swipe's after — a cancelled regen swipe must not
  /// inherit the rejected pair. Every path goes through [resolveSlotAfter].
  /// Porch Life off never moves the live clock — including snap and
  /// dayCount rungs.
  void applyTipClock() {
    if (!_scope.clockRunning()) return;
    final after = resolveVisibleAfter();
    if (after != null) _timeService.applySlotClock(resolved: after);
  }

  /// One ladder for the visible tip. Uses the stored slot so load
  /// recover and abort keep step 1. Tip-live ranks above own before
  /// (clamp floor), greeting-as-tip included. A far neighbour stamp
  /// stays below tip-live. Day 1 is the fork empty-pre-user seed.
  DateTime? resolveVisibleAfter({ChatMessage? tip, DateTime? liveClock}) {
    final target = tip ?? visibleTipMessage();
    if (target == null) return null;
    final greetingClock = greetingClockForResolve();
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

  /// Fill missing pairs from the live clock / nearest real time.
  /// Mutates in-memory slots; the load path persists when this returns true.
  bool backfillLoadedSlotClocks() {
    // The 24-row open window is not a clock. Guessing here treats the
    // first tail bot as the greeting (B1). Wait for the full history.
    if (!_scope.clockRunning()) return false;
    if (_historyClockIncomplete) return false;
    return backfillSlotClocks(
      _messages,
      liveClock: _timeService.clock,
      startDate: _timeService.startDate,
    );
  }

  /// A named pair stores `same moment` at the live clock. Reopen and
  /// backfill must re-arm the hold so a later 0-minute eval cannot
  /// land the 2-minute floor on that pair.
  void holdNamedReconcileIfSameMoment() {
    final clock = _timeService.clock;
    for (final msg in _messages) {
      if (msg.isUser || msg.sender == 'System') continue;
      for (final slot in [msg.metadata, ...msg.swipeMetadata]) {
        if (minutesFromTimePassed(slot?['time_passed']) != 0) continue;
        final after = slotClockAfter(slot);
        if (after != null && after == clock) {
          _timeService.holdNamedReconcileExact();
          return;
        }
      }
    }
  }

  /// Visible prefix has a user turn and a later bot reply.
  bool prefixLeftTheOpening() {
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
  DateTime day1OfStoryStart({DateTime? startDate}) {
    var tod = 'morning';
    String? startTime;
    String? cardStart;
    final group = _scope.activeGroup();
    if (group != null) {
      final seed = parseGroupTimeSeed(
        group.defaultMemberRealismState,
        group.baselineRealismState,
      );
      if (seed != null) {
        tod = seed.timeOfDay;
        startTime = seed.storyStartTime;
        cardStart = seed.storyStartDate;
      }
    } else {
      final ext = _scope.activeCharacter()?.frontPorchExtensions;
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
}
