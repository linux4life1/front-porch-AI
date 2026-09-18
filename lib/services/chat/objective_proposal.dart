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
import 'package:front_porch_ai/services/chat/eval_traffic.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart'
    show recentExchange;
import 'package:front_porch_ai/services/chat/objective_eval_tools.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/services.dart';

/// Objective proposal: autonomous "none" vs value + dedup, auto-tasks only
/// for autonomous proposals, generateObjectiveTasks, and background
/// task-completion checks. Proposal target is the speaking character even
/// under group impersonation. All-tasks-done quests deactivate so the
/// primary slot frees for the next autonomous quest.
class ObjectiveProposal {
  // Engine-provided central strip (via god thins) for &lt;think&gt; in gen/check (2000
  // budget paths for thinking models).
  final String Function(String) stripThinkBlocks;

  // LLM access for direct stream (gen uses temp 0.7/2000 creative; check uses
  // 0.1/2000 strict YES/NO; not the eval fire 4000/0.1/no-reasoning).
  final LLMService Function() getLlmService;

  // Character/group/mode for guards + gen prompt target (correct speaker under
  // group impersonation for autonomous proposal).
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;

  // Context + flags
  final String Function() getUserName;
  final bool Function() getRealismEnabled;
  final List<ChatMessage> Function() getMessages;

  // Objective mgmt cbs (thin/stayed in god per plan; mutation/list/load/save/deact
  // coordination stays in god; leaf uses for snapshot/iter + taskless deact).
  final List<Objective> Function() getActiveObjectives;
  final List<Map<String, dynamic>> Function(Objective) tasksForObjective;
  final Future<void> Function() loadActiveObjectives;
  final Future<void> Function(String objectiveId, String tasksJson)
  saveObjectiveTasks;
  final Future<void> Function(String objectiveId) deactivateObjective;
  final Future<void> Function(Objective, String)
  markTaskCompleted; // thin; god owns find+mutate 'completed':true + save+load (task auto side-effect only for currentTask YES path)
  final bool Function() getIsCheckingCompletion;
  final void Function(bool) setIsCheckingCompletion;

  // Notify for UI after check completion (onNotify only; save via god paths).
  final VoidCallback onNotify;

  /// Fired once per check when any task/objective completed — the Journal
  /// uses it to flag a significant event for its next maintenance pass
  /// (design §4.2 event-triggered cadence). Optional: null in dedicated
  /// tests that don't exercise the journal hook.
  final VoidCallback? onObjectiveCompleted;

  /// Fired when a WHOLE quest retires as achieved (final task done, or a
  /// taskless objective completed) — with the row, so the consumer knows
  /// whose ambition it may have advanced (Living Time §6). Fire-and-forget.
  final void Function(Objective obj)? onQuestAchieved;

  /// Same tools door TimeService / Realism evals use. Null = text only
  /// (dedicated tests that never wired the probe).
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
    required this.deactivateObjective,
    required this.markTaskCompleted,
    required this.getIsCheckingCompletion,
    required this.setIsCheckingCompletion,
    required this.onNotify,
    this.onObjectiveCompleted,
    this.onQuestAchieved,
    this.fireToolEval,
    this.probe,
    this.getBackendIdentity,
    this.getPreferTextEvals,
  });

  /// Generate subtasks for the current objective using the LLM.
  /// Clears existing tasks first so regen always produces a clean slate.
  /// (thin delegation for objective mgmt; full body here per step 11).
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) async {
    final llmService = getLlmService();

    // Snapshot existing tasks so we can restore on failure
    final previousTasks = tasksForObjective(obj);

    // Clear tasks immediately — UI shows empty state while LLM works
    await saveObjectiveTasks(obj.id, '[]');
    await loadActiveObjectives();

    try {
      if (!llmService.isReady) {
        debugPrint('[Objective] LLM not ready');
        // Restore tasks since we cleared them
        await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
        await loadActiveObjectives();
        return;
      }

      final char = getActiveCharacter();
      final charName = char?.name ?? 'the character';
      final scenario = char?.scenario ?? '';
      final userName = getUserName();

      // Include recent chat history so tasks aren't redundant
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

      // CHARACTER's own steps, never a quest handed to the player.
      final responseText = await _fireObjectiveEval(
        debugLabel: kObjectiveTasksTool,
        tools: kObjectiveTasksEvalTools,
        toolName: kObjectiveTasksTool,
        trafficLabel: 'objective_taskgen',
        temperature: 0.7,
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
        await loadActiveObjectives();
        debugPrint('[Objective] Generated ${uniqueTasks.length} tasks');
      } else {
        // Parse failed — restore previous tasks so we don't leave an empty list
        debugPrint(
          '[Objective] Could not parse tasks from response — restoring previous',
        );
        await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
        await loadActiveObjectives();
      }
    } catch (e) {
      debugPrint('[Objective] Task generation failed: $e');
      // Restore previous tasks on error
      await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
      await loadActiveObjectives();
    }
  }

  /// Consecutive NO verdicts before a stuck step/objective is retired as
  /// "overtaken by events" (cadence is checkFrequency, default 3, plus the
  /// mention-gate peek — not every turn). Maintainer tuned down from 8: a
  /// step the plot left behind should not linger.
  static const int kStaleCheckRetireAfter = 4;

  /// Consecutive-miss counters keyed `objectiveId|currentTask`. In-memory by
  /// design (see the retirement comment in the verdict loop).
  final Map<String, int> _staleCheckCounts = {};

  Future<void> checkTaskCompletionInBackground() async {
    if (getIsCheckingCompletion() || getActiveObjectives().isEmpty) return;
    setIsCheckingCompletion(true);

    var anyCompleted = false;
    try {
      final llmService = getLlmService();
      if (!llmService.isReady) return;

      // The one window builder + per-message clamp. This site was the worst
      // offender in the maintainer's EvalTraffic capture — 50k chars of
      // prompt for an 18-char verdict — because it read 8 messages of RAW
      // `m.text`: think blocks included, no photo markers, no ceiling.
      // recentExchange fixes all three at once (promptText + clamp).
      final contextText = recentExchange(getMessages(), take: 8);

      // Collect every item needing an LLM verdict, retiring already-finished
      // quests without spending a single token on them. (A lingering
      // completed primary blocked the character from proposing their next
      // main quest; also self-heals quests stuck from before that fix.)
      final pending = <(dynamic obj, List<dynamic> tasks, String? task)>[];
      for (final obj in getActiveObjectives()) {
        final tasks = tasksForObjective(obj);
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;
        if (currentTask == null && tasks.isNotEmpty) {
          anyCompleted = true;
          await deactivateObjective(obj.id);
          await loadActiveObjectives();
          debugPrint(
            '[Objective] All tasks complete — quest retired: ${obj.objective}',
          );
          continue;
        }
        pending.add((obj, tasks, currentTask));
      }
      if (pending.isEmpty) return;

      // ONE batched call for every objective (was one FULL LLM round-trip
      // per objective, each re-paying prefill on the same 8-message context —
      // 3 active quests on a 31B local model meant minutes of spinner before
      // the reply could even start; maintainer report 2026-07-15). Verdicts
      // come back as numbered YES/NO lines; anything unparsed counts as NO,
      // so a confused model can never wrongly complete a quest.
      final itemLines = <String>[];
      for (var i = 0; i < pending.length; i++) {
        final (obj, _, task) = pending[i];
        itemLines.add(
          task != null
              ? '${i + 1}. Objective: "${obj.objective}" — Task to evaluate: "$task"'
              : '${i + 1}. Objective to evaluate: "${obj.objective}"',
        );
      }
      // Tools first (same fireStructuredEval fork as TimeService), text
      // scrape as the floor. Unparsed / confused still counts as NO.
      final responseText = await _fireObjectiveEval(
        debugLabel: kObjectiveVerdictsTool,
        tools: kObjectiveVerdictsEvalTools,
        toolName: kObjectiveVerdictsTool,
        trafficLabel: 'objective_check',
        temperature: 0.1,
        reasoningOff: true,
        buildPrompt: ({required bool toolsMode}) => buildObjectiveCheckPrompt(
          contextText: contextText,
          itemLines: itemLines,
          toolsMode: toolsMode,
        ),
      );
      final rawPreview = responseText.replaceAll('\n', ' / ');
      debugPrint(
        '[Objective] Batched verdicts raw: '
        '"${rawPreview.length > 300 ? rawPreview.substring(0, 300) : rawPreview}"',
      );

      final verdicts = parseObjectiveVerdicts(responseText, pending.length);

      for (var i = 0; i < pending.length; i++) {
        final (obj, tasks, currentTask) = pending[i];
        var done = verdicts[i];
        debugPrint(
          '[Objective] Completion check for "${obj.objective}${currentTask != null ? ' - $currentTask' : ''}": ${done ? 'YES' : 'NO'}',
        );
        // Stale-step retirement (maintainer request 2026-07-15): a step the
        // story has moved past can come back NO forever and block the whole
        // quest line (the primary slot never frees). After
        // [kStaleCheckRetireAfter] CONSECUTIVE misses of the SAME item, treat
        // it as overtaken by events and let the quest advance. Counter is
        // in-memory on purpose: a restart merely delays retirement by a few
        // turns, and nothing leaks into the DB or panels.
        final staleKey = '${obj.id}|${currentTask ?? ''}';
        if (done) {
          _staleCheckCounts.remove(staleKey);
        } else {
          final misses = (_staleCheckCounts[staleKey] ?? 0) + 1;
          if (misses >= kStaleCheckRetireAfter) {
            _staleCheckCounts.remove(staleKey);
            done = true;
            debugPrint(
              '[Objective] Step overtaken by events after $misses stale '
              'checks — retiring gracefully: '
              '"${currentTask ?? obj.objective}"',
            );
          } else {
            _staleCheckCounts[staleKey] = misses;
            continue;
          }
        }
        anyCompleted = true;
        if (currentTask != null) {
          // Use thin cb (god impl) for best-effort task mutation (find uncompleted by desc, set completed:true, json+db update + load). Matches god toggleTask pattern exactly. Task vs taskless now both have side effects covered (taskless deact cb).
          await markTaskCompleted(obj, currentTask);
          // currentTask was the only open task left → the whole quest is
          // finished. Retire it now so the primary slot frees up this turn
          // instead of waiting for the next check pass.
          if (tasks.where((t) => t['completed'] != true).length <= 1) {
            await deactivateObjective(obj.id);
            onQuestAchieved?.call(obj);
            debugPrint(
              '[Objective] Final task done — quest retired: ${obj.objective}',
            );
          }
          await loadActiveObjectives();
          debugPrint(
            '[Objective] Task completed (via god thin mark): $currentTask',
          );
        } else {
          // It was a taskless objective that got completed!
          await deactivateObjective(obj.id);
          onQuestAchieved?.call(obj);
          await loadActiveObjectives();
          debugPrint(
            '[Objective] Taskless objective naturally completed: ${obj.objective}',
          );
        }
      }
    } catch (e) {
      debugPrint('[Objective] Completion check failed: $e');
    } finally {
      setIsCheckingCompletion(false);
      // A completed step is a story beat worth journaling — flag it once
      // (post-generation consumer; see onObjectiveCompleted doc).
      if (anyCompleted) onObjectiveCompleted?.call();
      onNotify();
    }
  }

  /// Tools-vs-text fork TimeService uses: `fireStructuredEval` when the
  /// probe is wired, else the existing generateStream floor.
  Future<String> _fireObjectiveEval({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String toolName,
    required String trafficLabel,
    required double temperature,
    required String Function({required bool toolsMode}) buildPrompt,
    bool reasoningOff = false,
  }) async {
    Future<String?> fireText(
      String prompt, {
      void Function(String)? onChunk,
    }) async {
      final llm = getLlmService();
      if (!llm.isReady) return null;
      final params = GenerationParams(
        prompt: prompt,
        maxLength: 2000,
        temperature: temperature,
        reasoningEnabled: false,
        reasoningMaxTokens: reasoningOff ? 0 : null,
        mandatoryReasoningHeadroom: true,
        stopSequences: const [],
      );
      final trafficWatch = Stopwatch()..start();
      var responseText = '';
      await for (final chunk in llm.generateStream(params)) {
        responseText += chunk;
      }
      EvalTraffic.current.record(
        label: trafficLabel,
        lane: 'raw',
        promptChars: params.prompt.length,
        outputChars: responseText.length,
        ms: trafficWatch.elapsedMilliseconds,
      );
      return responseText;
    }

    final raw = fireToolEval != null && probe != null
        ? await fireStructuredEval(
            probe: probe!,
            backendIdentity: getBackendIdentity?.call() ?? '',
            debugLabel: debugLabel,
            tools: tools,
            buildPrompt: buildPrompt,
            callToText: (resp) => objectiveToolCallToJson(toolName, resp.calls),
            fireToolEval: fireToolEval!,
            fireTextEval: fireText,
            toolChoice: toolName,
            maxLength: 2000,
            getPreferTextEvals: getPreferTextEvals,
          )
        : await fireText(buildPrompt(toolsMode: false));
    return stripThinkBlocks(raw ?? '');
  }
}
