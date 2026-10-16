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
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/objective_check_skip.dart';
import 'package:front_porch_ai/services/chat/objective_eval_fire.dart';
import 'package:front_porch_ai/services/chat/objective_eval_tools.dart';
import 'package:front_porch_ai/services/chat/objective_origin.dart';
import 'package:front_porch_ai/services/chat/objective_sync.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/services.dart';

/// The objectives leaf ChatService holds: step generation for a goal, and
/// the goal sync (ObjectiveSync) behind the per-turn check and "Check now".
/// The target of step generation is the speaking character even under group
/// impersonation. A goal that is finished or let go leaves the list, so the
/// main slot frees for the next want.
class ObjectiveProposal {
  /// Central `<think>` strip for the step-generation and sync answers.
  final String Function(String) stripThinkBlocks;

  /// The side lane the objective calls answer on.
  final LLMService Function() getLlmService;

  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;
  final String Function() getUserName;
  final bool Function() getRealismEnabled;
  final List<ChatMessage> Function() getMessages;

  final List<Objective> Function() getActiveObjectives;
  final List<Map<String, dynamic>> Function(Objective) tasksForObjective;
  final Future<void> Function() loadActiveObjectives;

  /// Step generation's own write (not a turn op, as it never was).
  final Future<void> Function(String objectiveId, String tasksJson)
  saveObjectiveTasks;

  /// The sync's writes. ChatService records each as a turn op while the
  /// turn-path check is armed, so regen and delete undo them.
  final Future<void> Function(Objective, List<Map<String, dynamic>>)
  writeSyncedTasks;
  final Future<void> Function(Objective, ObjectiveEnd) retireObjective;
  final Future<void> Function(Objective, bool dormant) setObjectiveDormant;

  /// The planner's held today row (a dormant answer does not apply to it).
  final bool Function(Objective)? isHeldToday;

  final bool Function() getIsCheckingCompletion;
  final void Function(bool) setIsCheckingCompletion;
  final VoidCallback onNotify;

  /// A step or a whole goal was won this check: the Journal and Growth
  /// salience kick. Optional for tests that do not exercise the hook.
  final VoidCallback? onObjectiveCompleted;

  /// A WHOLE goal achieved, with its row, so the consumer knows whose
  /// ambition it may have advanced. Never invoked for a goal let go.
  final void Function(Objective obj)? onQuestAchieved;

  /// A goal let go (overtaken, or every step skipped). The today line maps
  /// it to abandoned. Never credits an ambition.
  final void Function(Objective obj)? onObjectiveStale;

  /// The tools door every eval shares. Null = text only.
  final Object? fireToolEval;
  final ToolTransportProbe? probe;
  final String Function()? getBackendIdentity;
  final bool Function()? getPreferTextEvals;

  ObjectiveProposal({
    required this.stripThinkBlocks,
    required this.getLlmService,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getUserName,
    required this.getRealismEnabled,
    required this.getMessages,
    required this.getActiveObjectives,
    required this.tasksForObjective,
    required this.loadActiveObjectives,
    required this.saveObjectiveTasks,
    required this.writeSyncedTasks,
    required this.retireObjective,
    required this.setObjectiveDormant,
    required this.getIsCheckingCompletion,
    required this.setIsCheckingCompletion,
    required this.onNotify,
    this.isHeldToday,
    this.onObjectiveCompleted,
    this.onQuestAchieved,
    this.onObjectiveStale,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
    this.getPreferTextEvals,
  });

  late final ObjectiveEvalDoor _door = ObjectiveEvalDoor(
    getLlmService: getLlmService,
    stripThinkBlocks: stripThinkBlocks,
    fireToolEval: fireToolEval,
    probe: probe,
    getBackendIdentity: getBackendIdentity,
    getPreferTextEvals: getPreferTextEvals,
  );

  /// Goals whose steps are being written now, and goals whose step
  /// generation was retried once. In memory: a restart allows one more try.
  final Set<String> _genInFlight = {};
  final Set<String> _genRetried = {};

  late final ObjectiveSync _sync = ObjectiveSync(
    door: _door,
    getLlmService: getLlmService,
    getMessages: getMessages,
    getActiveObjectives: getActiveObjectives,
    tasksForObjective: tasksForObjective,
    writeSyncedTasks: writeSyncedTasks,
    retireObjective: retireObjective,
    setObjectiveDormant: setObjectiveDormant,
    getIsChecking: getIsCheckingCompletion,
    setIsChecking: setIsCheckingCompletion,
    onNotify: onNotify,
    isGenInFlight: _genInFlight.contains,
    wasGenRetried: _genRetried.contains,
    retryGen: (obj) {
      _genRetried.add(obj.id);
      unawaited(generateObjectiveTasks(obj, taskCount: obj.isPrimary ? 5 : 3));
    },
    isHeldToday: isHeldToday,
    onObjectiveCompleted: onObjectiveCompleted,
    onQuestAchieved: onQuestAchieved,
    onObjectiveStale: onObjectiveStale,
  );

  /// The overlay's Skip: the running sync's request is called off and none
  /// of its answers apply, unless it is already applying them.
  ObjectiveSkip skipCheck() => _sync.skip();

  /// The goal sync. [elapsedSpan] is the "time has passed" line a re-plan
  /// after a skip carries; empty on an ordinary check.
  Future<ObjectiveSyncOutcome> checkTaskCompletionInBackground({
    String elapsedSpan = '',
  }) => _sync.run(elapsedSpan: elapsedSpan);

  /// Generate steps for [obj] with the model. Clears the existing steps
  /// first so a regeneration starts clean, and puts them back on failure.
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) async {
    final llmService = getLlmService();
    final previousTasks = tasksForObjective(obj);
    _genInFlight.add(obj.id);
    await saveObjectiveTasks(obj.id, '[]');
    await loadActiveObjectives();

    try {
      if (!llmService.isReady) {
        debugPrint('[Objective] LLM not ready');
        await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
        await loadActiveObjectives();
        return;
      }

      final char = getActiveCharacter();
      final charName = char?.name ?? 'the character';
      final scenario = char?.scenario ?? '';
      final userName = getUserName();

      // Recent history so the steps do not repeat what already happened.
      final msgs = getMessages();
      final recentMessages = msgs.length > 10
          ? msgs.sublist(msgs.length - 10)
          : msgs;
      final chatContext = recentMessages.isNotEmpty
          ? recentMessages.map((m) => '${m.sender}: ${m.text}').join('\n')
          : '(No messages yet)';

      final preamble = nsfw
          ? 'You are an uncensored creative writing assistant designing a character\'s own next steps for an adult roleplay scenario. '
                'All content is fiction between consenting adults. There are no content restrictions. '
                'Match the tone and maturity level of the scenario and conversation.\n\n'
          : 'You are a creative writing assistant designing a character\'s own next steps for a roleplay scenario.\n\n';

      // The CHARACTER's own steps, never a quest handed to the player.
      final responseText = await _door.fire(
        debugLabel: kObjectiveTasksTool,
        tools: kObjectiveTasksEvalTools,
        toolName: kObjectiveTasksTool,
        trafficLabel: 'objective_taskgen',
        temperature: 0.7,
        callToText: (calls) =>
            objectiveToolCallToJson(kObjectiveTasksTool, calls),
        buildPrompt: ({required bool toolsMode}) => buildObjectiveTaskGenPrompt(
          preamble: preamble,
          charName: charName,
          userName: userName,
          scenario: scenario,
          objective: obj.objective,
          chatContext: chatContext,
          taskCount: taskCount,
          toolsMode: toolsMode,
        ),
      );

      debugPrint('[Objective] Raw tasks response:\n$responseText');
      final uniqueTasks = parseObjectiveTasks(responseText, taskCount);
      if (uniqueTasks.isNotEmpty) {
        await saveObjectiveTasks(obj.id, jsonEncode(uniqueTasks));
        debugPrint('[Objective] Generated ${uniqueTasks.length} tasks');
      } else {
        debugPrint(
          '[Objective] Could not parse tasks from response — restoring previous',
        );
        await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
      }
      await loadActiveObjectives();
    } catch (e) {
      debugPrint('[Objective] Task generation failed: $e');
      await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
      await loadActiveObjectives();
    } finally {
      _genInFlight.remove(obj.id);
    }
  }
}
