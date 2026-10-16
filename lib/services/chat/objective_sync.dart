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

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart' show ChatMessage;
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart'
    show recentExchange;
import 'package:front_porch_ai/services/chat/objective_check_skip.dart';
import 'package:front_porch_ai/services/chat/objective_eval_fire.dart';
import 'package:front_porch_ai/services/chat/objective_origin.dart';
import 'package:front_porch_ai/services/chat/objective_stale_detector.dart';
import 'package:front_porch_ai/services/chat/objective_sync_decide.dart';
import 'package:front_porch_ai/services/chat/objective_sync_parse.dart';
import 'package:front_porch_ai/services/chat/objective_sync_tools.dart';
import 'package:front_porch_ai/services/services.dart' show LLMService;

enum ObjectiveSyncOutcome { notRun, noSignal, skipped, applied }

/// The goal sync (docs/design/objectives-that-keep-up.md part 1): one
/// batched call asks where every open goal stands; the answer ticks steps in
/// any order, rewrites the next step to fit the story, sets a goal aside or
/// wakes it, and retires it as achieved or let go. It replaces the old
/// YES/NO check at the same cadence, at the same price.
class ObjectiveSync {
  ObjectiveSync({
    required this.door,
    required this.getLlmService,
    required this.getMessages,
    required this.getActiveObjectives,
    required this.tasksForObjective,
    required this.writeSyncedTasks,
    required this.retireObjective,
    required this.setObjectiveDormant,
    required this.getIsChecking,
    required this.setIsChecking,
    required this.onNotify,
    required this.isGenInFlight,
    required this.wasGenRetried,
    required this.retryGen,
    this.isHeldToday,
    this.onObjectiveCompleted,
    this.onQuestAchieved,
    this.onObjectiveStale,
  });

  final ObjectiveEvalDoor door;
  final LLMService Function() getLlmService;
  final List<ChatMessage> Function() getMessages;
  final List<Objective> Function() getActiveObjectives;
  final List<Map<String, dynamic>> Function(Objective) tasksForObjective;
  final Future<void> Function(Objective, List<Map<String, dynamic>>)
  writeSyncedTasks;
  final Future<void> Function(Objective, ObjectiveEnd) retireObjective;
  final Future<void> Function(Objective, bool dormant) setObjectiveDormant;
  final bool Function() getIsChecking;
  final void Function(bool) setIsChecking;
  final VoidCallback onNotify;
  final bool Function(String id) isGenInFlight;
  final bool Function(String id) wasGenRetried;
  final void Function(Objective) retryGen;
  final bool Function(Objective)? isHeldToday;

  /// A step or a whole goal was won: the Journal and Growth salience kick.
  final VoidCallback? onObjectiveCompleted;

  /// A whole goal achieved (ambition tick, the today line's win).
  final void Function(Objective)? onQuestAchieved;

  /// A goal let go (the today line maps it to abandoned). Never a win.
  final void Function(Objective)? onObjectiveStale;

  final ObjectiveCheckSkip _skip = ObjectiveCheckSkip();

  ObjectiveSkip skip() => _skip.skip();

  Future<void> _retire(Objective obj, ObjectiveEnd end) async {
    await retireObjective(obj, end);
    if (end == ObjectiveEnd.achieved) {
      onQuestAchieved?.call(obj);
    } else {
      onObjectiveStale?.call(obj);
    }
    debugPrint('[Objective] ${end.name}: ${obj.objective}');
  }

  ObjectiveSyncItem _item(Objective obj, List<Map<String, dynamic>> tasks) =>
      ObjectiveSyncItem(
        goal: obj.objective,
        dormant: objectiveIsDormant(obj),
        stepsFixed: objectiveStepsAreAuthored(obj) && tasks.isNotEmpty,
        steps: [
          for (final t in tasks)
            (
              (t['description'] as String?) ?? '',
              objectiveTaskIsStale(t)
                  ? 'skipped'
                  : (objectiveTaskIsCompleted(t) ? 'done' : 'open'),
            ),
        ],
      );

  Future<ObjectiveSyncOutcome> run({String elapsedSpan = ''}) async {
    if (getIsChecking() || getActiveObjectives().isEmpty) {
      return ObjectiveSyncOutcome.notRun;
    }
    setIsChecking(true);
    final cancel = _skip.begin();
    var anyWin = false;
    try {
      if (!getLlmService().isReady) return ObjectiveSyncOutcome.notRun;
      final contextText = recentExchange(getMessages(), take: 8);

      final pending = <(Objective, List<Map<String, dynamic>>)>[];
      for (final obj in [...getActiveObjectives()]) {
        if (cancel.isCancelled) return ObjectiveSyncOutcome.skipped;
        final tasks = tasksForObjective(obj);
        // Every step already ticked or skipped (by hand, or before this
        // build): retire it without spending a token on it.
        if (tasks.isNotEmpty && currentOpenTaskDescription(tasks) == null) {
          final win = questExhaustion(tasks) != QuestExhaustion.stale;
          await _retire(obj, win ? ObjectiveEnd.achieved : ObjectiveEnd.letGo);
          anyWin |= win;
          continue;
        }
        final eligibility = objectiveSyncEligibility(
          ownWant: objectiveOrigin(obj) == kObjectiveOriginCharacter,
          hasTasks: tasks.isNotEmpty,
          genInFlight: isGenInFlight(obj.id),
          genRetried: wasGenRetried(obj.id),
        );
        if (eligibility == ObjectiveSyncEligibility.retryThenSkip) {
          retryGen(obj);
        }
        if (eligibility != ObjectiveSyncEligibility.include) continue;
        pending.add((obj, tasks));
      }
      if (pending.isEmpty || cancel.isCancelled) {
        return ObjectiveSyncOutcome.notRun;
      }

      final items = [for (final (o, t) in pending) _item(o, t)];
      final answer = door.fire(
        cancel: cancel,
        debugLabel: kObjectiveSyncTool,
        tools: kObjectiveSyncEvalTools,
        toolName: kObjectiveSyncTool,
        trafficLabel: 'objective_check',
        temperature: 0.1,
        reasoningOff: true,
        callToText: objectiveSyncCallToJson,
        buildPrompt: ({required bool toolsMode}) => buildObjectiveSyncPrompt(
          contextText: contextText,
          items: items,
          toolsMode: toolsMode,
          elapsedSpan: elapsedSpan,
        ),
      );
      // Skip answers at once; the abandoned request ends in its abort error.
      unawaited(
        answer.then<void>(
          (_) {},
          onError: (Object e) => debugPrint('[Objective] Sync ended: $e'),
        ),
      );
      final text = await Future.any<String?>([
        answer,
        cancel.whenCancelled.then((_) => null),
      ]);
      if (text == null || cancel.isCancelled) {
        debugPrint('[Objective] Sync skipped — goals left as they were');
        return ObjectiveSyncOutcome.skipped;
      }
      final parsed = parseObjectiveSync(text, pending.length);
      if (!parsed.hadSignal) {
        debugPrint('[Objective] Sync gave no usable answer — keeping goals');
        return ObjectiveSyncOutcome.noSignal;
      }
      // The last moment a skip stops everything; after it, all apply.
      if (!_skip.startApplying(cancel)) return ObjectiveSyncOutcome.skipped;

      for (var i = 0; i < pending.length; i++) {
        final (obj, tasks) = pending[i];
        final apply = decideObjectiveSync(
          tasks: tasks,
          verdict: parsed.items[i],
          stepsAuthored: objectiveStepsAreAuthored(obj),
          isHeldToday: isHeldToday?.call(obj) ?? false,
          wasDormant: objectiveIsDormant(obj),
        );
        debugPrint(
          '[Objective] Sync "${obj.objective}": '
          'status=${parsed.items[i].status} '
          'steps=${parsed.items[i].stepsDone} '
          'next=${parsed.items[i].nextStep} → '
          'tasks=${apply.newTasks != null} dormant=${apply.dormant} '
          'end=${apply.end?.name}',
        );
        if (apply.isNoop) continue;
        final newTasks = apply.newTasks;
        if (newTasks != null) {
          await writeSyncedTasks(obj, newTasks);
          if (completedQuestTaskCount(newTasks) >
              completedQuestTaskCount(tasks)) {
            anyWin = true;
          }
        }
        final dormant = apply.dormant;
        if (dormant != null) await setObjectiveDormant(obj, dormant);
        final end = apply.end;
        if (end != null) {
          await _retire(obj, end);
          anyWin |= end == ObjectiveEnd.achieved;
        }
      }
      return ObjectiveSyncOutcome.applied;
    } catch (e) {
      debugPrint('[Objective] Sync failed: $e');
      return ObjectiveSyncOutcome.noSignal;
    } finally {
      _skip.end(cancel);
      setIsChecking(false);
      if (anyWin) onObjectiveCompleted?.call();
      onNotify();
    }
  }
}
