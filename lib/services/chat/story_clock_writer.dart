// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart' show Session;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/body_clock.dart';
import 'package:front_porch_ai/services/chat/message_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/story_clock_reader.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

enum SlotClockWrite { tick, nudge, abort, seed, resolved, beforeOnly }

/// Visible slot, created once. Never [Map.from] — that shares the
/// inner `realism_state` and then replaces the swipe map, so a later
/// restore can pin pre-eval trust/needs.
Map<String, dynamic> clockWriteSlot(ChatMessage target) {
  final existing = target.activeMetadata;
  if (existing != null) return existing;
  final slot = <String, dynamic>{};
  target.metadata ??= slot;
  target.activeMetadata = slot;
  return slot;
}

/// THE writer. Every slot mutation lands in [writeSlotClock], then
/// [StoryClockReader.applyTipClock]. Load, fork, delete, abort and regen
/// rewind are the callers that move the clock, so they live here too.
class StoryClockWriter {
  StoryClockWriter(
    this._scope,
    this._reader, {
    required this.currentSessionId,
    required this.saveChat,
    required this.notify,
    required this.setGuestStatus,
  });

  final StoryClockScope _scope;
  final StoryClockReader _reader;
  final String? Function() currentSessionId;
  final Future<void> Function() saveChat;
  final VoidCallback notify;
  final void Function(String status) setGuestStatus;

  /// Pre-nudge live clock, stamped on the slot as `nudge_from` so a tail
  /// delete can restore it without rewriting `story_clock_before`.
  DateTime? pendingNudgeBefore;

  TimeService get _timeService => _scope.time();
  bool get _clockRunning => _scope.clockRunning();

  void writeSlotClock(
    ChatMessage? target, {
    required SlotClockWrite kind,
    DateTime? after,
    DateTime? before,
  }) {
    if (target == null || target.isUser) return;
    if (!_clockRunning) return;

    if (kind == SlotClockWrite.seed) {
      if (slotHasCompletePair(target.activeMetadata)) {
        _reader.applyTipClock();
        return;
      }
      final clock = _timeService.clock;
      writeSlotClockPair(
        clockWriteSlot(target),
        before: clock,
        after: clock,
        fromWriter: true,
      );
      persistStoryClockBefore(target, StoryClock.serializeClock(clock));
      _reader.applyTipClock();
      return;
    }

    if (kind == SlotClockWrite.resolved) {
      final resolved = after;
      if (resolved == null) return;
      var storedBefore = slotClockBefore(target.activeMetadata) ?? resolved;
      if (resolved.isBefore(storedBefore)) storedBefore = resolved;
      writeSlotClockPair(
        clockWriteSlot(target),
        before: storedBefore,
        after: resolved,
        fromWriter: true,
      );
      persistStoryClockBefore(target, StoryClock.serializeClock(storedBefore));
      _reader.applyTipClock();
      return;
    }

    if (kind == SlotClockWrite.beforeOnly) {
      final stamp = before;
      if (stamp == null) return;
      persistStoryClockBefore(target, StoryClock.serializeClock(stamp));
      _reader.applyTipClock();
      return;
    }

    final known = StoryClock.parse(knownStoryClockBefore(target));
    var slotBefore = switch (kind) {
      SlotClockWrite.nudge => _timeService.clock,
      _ => known ?? _timeService.clock,
    };
    final slotAfter = switch (kind) {
      SlotClockWrite.abort => slotBefore,
      _ => _timeService.clock,
    };
    // Any write that lands earlier than the turn's before (named
    // 07:30, backward nudge, skip) stores before = after so the
    // pair is never inverted. Clamp stays global. Message-level
    // before stays on persistStoryClockBefore (putIfAbsent).
    if (slotAfter.isBefore(slotBefore)) {
      slotBefore = slotAfter;
    }

    String? chip;
    var clearChip = false;
    if (kind == SlotClockWrite.abort) {
      clearChip = true;
    } else if (kind == SlotClockWrite.tick) {
      final existing = target.activeMetadata;
      if ((existing?['time_skip_to'] as String? ?? '').isNotEmpty) {
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

    if (kind == SlotClockWrite.tick || kind == SlotClockWrite.nudge) {
      persistStoryClockBefore(target, StoryClock.serializeClock(slotBefore));
    }
    final slot = clockWriteSlot(target);
    writeSlotClockPair(
      slot,
      before: slotBefore,
      after: slotAfter,
      timePassed: chip,
      clearChip: clearChip,
      timeNudged: kind == SlotClockWrite.nudge,
      fromWriter: true,
    );
    final nudgeFrom = pendingNudgeBefore;
    if (kind == SlotClockWrite.nudge && nudgeFrom != null) {
      final from = StoryClock.serializeClock(nudgeFrom);
      slot['nudge_from'] = from;
      if (target.metadata != null && !identical(target.metadata, slot)) {
        target.metadata!['nudge_from'] = from;
      }
    }
    pendingNudgeBefore = null;
    if (kind == SlotClockWrite.nudge &&
        target.metadata != null &&
        !identical(target.metadata, target.activeMetadata)) {
      writeSlotClockPair(
        target.metadata!,
        before: slotBefore,
        after: slotAfter,
        timeNudged: true,
        fromWriter: true,
      );
    }
    _reader.applyTipClock();
  }

  /// Day 1 of the persisted start. Empty-pre-user and the no-tip
  /// fork share this. Tip present: write the pair (applyTip inside
  /// the writer). No tip: live only — the only [applySlotClock]
  /// outside the tip reader and regen rewind.
  void applyDay1Clock({DateTime? startDate, ChatMessage? tip}) {
    if (!_clockRunning) return;
    final day1 = _reader.day1OfStoryStart(startDate: startDate);
    if (tip != null) {
      writeSlotClock(tip, kind: SlotClockWrite.resolved, after: day1);
      return;
    }
    _timeService.applySlotClock(resolved: day1);
  }

  /// Regen rewind: persist the slot before, then move live to it.
  void rewindLiveToSlotBefore(ChatMessage lastMsg) {
    discoverAndPersistMessageBefore(lastMsg);
    final before = StoryClock.parse(knownStoryClockBefore(lastMsg));
    if (before == null) return;
    _timeService.applySlotClock(resolved: before);
  }

  void restoreCapturedThroughReader({String? sessionId}) {
    _timeService.restoreCapturedClock(sessionId: sessionId);
    _reader.applyTipClock();
  }

  /// Load / reload / fork / import: backfill then tip.after.
  void syncLoadedSlotClocks() {
    try {
      _reader.backfillLoadedSlotClocks();
    } catch (e, st) {
      debugPrint('[Clock] backfill failed: $e\n$st');
    }
    _reader.applyTipClock();
    _reader.holdNamedReconcileIfSameMoment();
  }

  /// Session scalars first, then tip resolve. Live must not stay
  /// on the TimeService default (today) while greeting-as-tip reads it.
  Future<void> reloadSessionClockThenSync(Session s) async {
    _timeService.clearCapturedClock();
    _timeService.loadTimeScalars(
      timeOfDay: s.timeOfDay,
      dayCount: s.dayCount,
      startDayOfWeek: s.startDayOfWeek,
      storyClock: s.storyClock,
      storyStartDate: s.storyStartDate,
    );
    _reader.applyTipClock();
    _reader.holdNamedReconcileIfSameMoment();
    final sid = currentSessionId();
    final history = _scope.history;
    final epoch = history.epoch;
    final pending = history.backfill;
    if (pending != null) {
      unawaited(
        pending.then((_) {
          if (sid != currentSessionId() || epoch != history.epoch) return;
          _finishLoadedSlotClockBackfill();
        }),
      );
      return;
    }
    _finishLoadedSlotClockBackfill();
  }

  void _finishLoadedSlotClockBackfill() {
    try {
      final changed = _reader.backfillLoadedSlotClocks();
      _reader.applyTipClock();
      _reader.holdNamedReconcileIfSameMoment();
      if (changed) unawaited(saveChat());
      notify();
    } catch (e, st) {
      debugPrint('[Clock] load backfill failed: $e\n$st');
    }
  }

  /// Abort may only undo a clock change THIS turn made. Continue never
  /// ticks. Porch Life off never writes. Abort-write sets after=before
  /// on the kept tip so live clock equals that pair. [streamTarget] is
  /// read only when the abort writes.
  void abortSlotClockIfThisTurnTicked(
    ChatMessage Function() streamTarget, {
    required bool isContinue,
  }) {
    if (isContinue) {
      _reader.applyTipClock();
      return;
    }
    if (!_clockRunning) {
      _reader.applyTipClock();
    } else {
      writeSlotClock(streamTarget(), kind: SlotClockWrite.abort);
      _reader.applyTipClock();
    }
    setGuestStatus('Reply kept. Scene time and needs weren\'t updated.');
  }

  /// Tail-delete goes through the one resolver. Nudge overwrites with
  /// the pre-nudge clock via resolved(after). Otherwise the remaining
  /// tip resolves against the deleted before so a greeting that already
  /// stores after keeps it at step 1.
  void applyClockAfterDelete(ChatMessage deleted, {required bool wasTail}) {
    if (wasTail) {
      final nudged = deleted.activeMetadata?['time_nudged'] == true;
      if (nudged) {
        final restored =
            StoryClock.parse(
              deleted.activeMetadata?['nudge_from'] as String?,
            ) ??
            slotClockBefore(deleted.activeMetadata);
        if (restored != null) {
          writeSlotClock(
            _reader.visibleTipMessage(),
            kind: SlotClockWrite.resolved,
            after: restored,
          );
          return;
        }
      }
      final deletedSlot = deleted.activeMetadata;
      final storedBefore = slotClockBefore(deletedSlot);
      final start = _timeService.startDate;
      final floor = StoryClock.dateOnly(start);
      // Only a stored before. Chip-derived after-minus-chip (even
      // when floored at Day 1 midnight) is not stored — keep live.
      DateTime? rewind;
      if (storedBefore != null &&
          !slotBeforeIsChipDerived(deletedSlot, startDate: start)) {
        rewind = storedBefore.isBefore(floor) ? floor : storedBefore;
      }
      rewind ??= _timeService.clock;
      final tip = _reader.visibleTipMessage();
      if (tip != null) {
        final after = _reader.resolveVisibleAfter(tip: tip, liveClock: rewind);
        if (after != null) {
          writeSlotClock(tip, kind: SlotClockWrite.resolved, after: after);
          return;
        }
      }
    }
    _reader.applyTipClock();
  }

  /// Pre-reply clock for regen evals. After backfill the pair exists.
  void rewindClockToPreReply(ChatMessage lastMsg) {
    if (!_clockRunning) return;
    _timeService.captureLiveClock();
    rewindLiveToSlotBefore(lastMsg);
  }

  /// First known before for this message position. A frozen Day-1
  /// snap is not a pre-reply — first regen must rewind to the slot's
  /// real before (or live) and add only the new swipe's minutes.
  void discoverAndPersistMessageBefore(ChatMessage msg) {
    if (!_clockRunning) return;
    var before = knownStoryClockBefore(msg);
    final slot = msg.activeMetadata;
    final snap = slotSnapClock(slot);
    // Regen pops the tip before rewind. The popped snap is still the
    // earliest-reply greeting clock when message 0 has no stamp.
    final greeting = _reader.greetingClockForResolve() ?? snap;
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
      writeSlotClock(msg, kind: SlotClockWrite.beforeOnly, before: parsed);
    }
  }

  /// Fork lands on the fork-point slot via the one resolver. Day 1
  /// of the start applies only at or before the first user turn
  /// with nothing stored — a transcript that opens with a user turn
  /// and already has a later bot is not that case. A neighbour
  /// story_day is not this slot's clock (rung 6 is live).
  void applyForkPointClock({DateTime? parentStartDate}) {
    final leftOpening = _reader.prefixLeftTheOpening();
    final tip = _reader.visibleTipMessage();
    if (tip == null) {
      if (!leftOpening) applyDay1Clock(startDate: parentStartDate);
      return;
    }
    _reader.backfillLoadedSlotClocks();
    final greetingClock = _reader.greetingClockForResolve();
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
      applyDay1Clock(startDate: parentStartDate, tip: tip);
      return;
    }
    final after = _reader.resolveVisibleAfter(
      tip: tip,
      liveClock: _timeService.clock,
    );
    if (after != null) {
      writeSlotClock(tip, kind: SlotClockWrite.resolved, after: after);
      return;
    }
    _reader.applyTipClock();
  }
}
