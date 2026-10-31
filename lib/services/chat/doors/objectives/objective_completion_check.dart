// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseMemoryQueries, Objective, ObjectivesCompanion;
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';

/// The goal check and the goal sync's writes. Gates on the live
/// [ObjectiveShellHooks.objectivesActive] AND, never a stored one.
class ObjectiveCompletionCheck {
  ObjectiveCompletionCheck(this._door, this._d);

  final ObjectivesDoor _door;
  final ObjectiveDeps _d;

  ObjectiveTurnOps get _ops => _door.turnOps;

  /// The overlay's "Skip goal check": the check's own request is called off
  /// and its verdicts are dropped. The reply still comes (the turn path
  /// awaits the check, which now returns). Turn ops it recorded before the
  /// call (a quest whose steps were all done) stay, so regen still undoes them.
  void skip() {
    switch (_d.proposal().skipCheck()) {
      case ObjectiveSkip.notRunning:
        return;
      case ObjectiveSkip.skipped:
        _d.hooks.setStatus('Goal check skipped. Your goals stay as they were.');
      case ObjectiveSkip.tooLate:
        _d.hooks.setStatus(
          'Too late to skip: the goal check already had its answer.',
        );
    }
  }

  /// The pre-generation check, awaited by the send path.
  Future<void> maybeCheckSync() async {
    final active = _door.activeObjectives;
    // The recurring cost this feature's switch exists to stop: one model call
    // every `freq` messages, forever, for as long as a quest is open.
    if (!_d.hooks.objectivesActive() ||
        active.isEmpty ||
        !_d.hooks.hasChatModel() ||
        _door.isCheckingCompletion) {
      return;
    }

    final time = _d.time();
    final messages = _d.session.messages;
    _door.messagesSinceLastCheck++;
    // A story day crossed since these goals were last synced (an OOC skip
    // at the start of this send, "next morning", time away) re-plans them
    // now, whatever the cadence says, and the sync is told how long it has
    // been (objectives-that-keep-up.md part 2). The clock alone retires
    // nothing; only the answer does.
    final charId = active.first.characterId;
    final replanMinutes = objectiveReplanMinutes(
      stamp: lastObjectiveSyncStamp(messages, charId),
      dayNow: time.dayCount,
      clockNow: time.clock,
    );
    // The per-objective cadence the UI exposes is the cadence, full stop.
    // The old realism-on override forced freq to one — a BLOCKING model
    // call, awaited before every reply — onto every single turn the moment
    // any quest was open with the engine on, silently ignoring the
    // checkFrequency the user can see and set (eval review Tier-1 §3.1).
    final freq =
        _door.primaryObjective?.checkFrequency ?? active.first.checkFrequency;
    if (replanMinutes == null && _door.messagesSinceLastCheck < freq) {
      // Off-interval, the check still fires the moment the scene actually
      // touches a quest: a completion can only be shown by the exchange, and
      // the check reads exactly this window — so an exchange sharing none of
      // a quest's content words is a guaranteed NO not worth a blocking
      // round trip. A paraphrase the gate misses is caught by the next
      // interval check, never lost. Cast + user name tokens are excluded or
      // "get Jennifer to admit her fear" would match every line Jennifer
      // speaks.
      final recentLower = messages.reversed
          .take(8)
          .map((m) => m.promptText)
          .join('\n')
          .toLowerCase();
      final quests = <String>[
        for (final o in active)
          ...openQuestMentionTexts(o.objective, _door.tasks.tasksFor(o)),
      ];
      if (!objectivesMentionedIn(
        recentLower,
        quests,
        ignore: _door.objectiveIgnoreTokens(),
      )) {
        return;
      }
      debugPrint('[Objective] Mention gate: quest touched — checking early');
    }
    _door.messagesSinceLastCheck = 0;
    if (replanMinutes != null) {
      debugPrint('[Objective] Story moved ${replanMinutes}m — re-planning');
    }

    // Arm turn-op recording only for THIS turn-path check: its completions
    // and retirements belong to the turn being generated and must roll back
    // on regen; manual "Check now" runs the same check unarmed.
    _ops.armed = true;
    try {
      final outcome = await _d.proposal().checkTaskCompletionInBackground(
        elapsedSpan: replanMinutes == null
            ? ''
            : objectiveSpanLine(replanMinutes),
      );
      // "Last synced" rides the reply this turn writes: a restart reads it
      // back; a regen or delete drops it with the sync's own changes.
      if (outcome == ObjectiveSyncOutcome.applied) {
        final t = _d.time();
        _d.hooks.pendingMetadata()[kObjectiveSyncStampKey] = ObjectiveSyncStamp(
          charId: charId,
          day: t.dayCount,
          clockIso: t.storyClockIso,
        ).toJson();
      }
    } finally {
      _ops.armed = false;
    }
  }

  Future<void> checkInBackground() =>
      _d.proposal().checkTaskCompletionInBackground(countStuck: false);

  /// The goal sync's step list: ticks in any order and a rewritten next
  /// step, written once and rewound together by regen (one tasks_changed op
  /// holding the pre-sync list).
  Future<void> writeSyncedTasks(
    Objective obj,
    List<Map<String, dynamic>> tasks,
  ) async {
    // Turn-op for regen rollback: obj.tasks is still the pre-mutation JSON
    // here, so the inverse is a plain write-back of that string. Armed-gated:
    // manual "Check now" completions are user actions, not turn ops.
    if (_ops.armed) {
      _ops.record({'op': 'tasks_changed', 'id': obj.id, 'prev': obj.tasks});
    }
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _door.loadActiveObjectives();
  }

  /// The sync retires a goal: finished or let go, with when. The turn op
  /// keeps the status it had so a regen puts the goal back exactly.
  Future<void> retireFromSync(Objective obj, ObjectiveEnd end) async {
    // Taken now, while the turn that ended the goal is still running.
    final cite = _ops.cite();
    if (_ops.armed) {
      _ops.record({
        'op': 'deactivated',
        'id': obj.id,
        'prevStatus': obj.status,
      });
    }
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        active: const drift.Value(false),
        status: drift.Value(
          end == ObjectiveEnd.achieved
              ? kObjectiveStatusDone
              : kObjectiveStatusOvertaken,
        ),
        endedAt: drift.Value(DateTime.now()),
      ),
    );
    await _rewardEnd(obj, end, cite);
    await _door.loadActiveObjectives();
  }

  /// A goal of the character's own ended: the feeling it brings (unless a
  /// stronger one stands) and a diary card cited at the turn's reply, so a
  /// regen or delete takes both back with the goal.
  Future<void> _rewardEnd(
    Objective obj,
    ObjectiveEnd end,
    List<int> cite,
  ) async {
    if (!objectiveEarnsRewards(obj)) return;
    final owner = obj.characterId;
    final group = _d.session.activeGroup != null;
    final moods = _d.mood();
    if (_d.hooks.realismActiveThisMode()) {
      final current = group ? moods.memberState(owner) : moods.state;
      final next = objectiveRewardMood(
        current: current,
        end: end,
        primary: obj.isPrimary,
        goal: obj.objective,
      );
      if (next != null && !group) {
        moods.set(next.label, next.intensity, cause: next.cause);
      } else if (next != null) {
        // The owner may not be this turn's speaker, whose stamp is the only
        // one a regen restores, so the member's old mood rides the turn ops.
        if (_ops.armed) {
          _ops.record({
            'op': 'mood',
            'charId': owner,
            'prev': current.toStamp(),
          });
        }
        moods.setMember(owner, next);
        final loaded = _d.session.activeCharacter;
        if (loaded != null && _d.characterIdFor(loaded) == owner) {
          moods.set(next.label, next.intensity, cause: next.cause);
        }
      }
    }
    final sessionId = _d.session.currentSessionId;
    final memory = _d.storage().memorySettings;
    if (!memory.journalEnabled || sessionId == null) return;
    final mood = group ? moods.memberState(owner) : moods.state;
    final time = _d.time();
    await _d.journal().addCard(
      sessionId: sessionId,
      characterId: owner,
      content: objectiveDiaryLine(end, obj.objective),
      category: 'moment',
      kind: 'goal',
      sourcePositions: cite,
      storyDay: time.dayCount,
      storyClock: time.storyClockIso,
      emotionLabel: mood.isNeutral ? null : mood.label,
      maxCards: memory.journalMaxCards,
    );
  }

  /// The sync sets a goal aside, or wakes it.
  Future<void> setDormant(Objective obj, bool dormant) async {
    if (_ops.armed) {
      _ops.record({'op': 'status', 'id': obj.id, 'prev': obj.status});
    }
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        status: drift.Value(dormant ? kObjectiveStatusDormant : null),
      ),
    );
    await _door.loadActiveObjectives();
  }
}
