// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
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
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Plain (non-ChangeNotifier) leaf sibling to LlmEvalEngine owning the objective
/// proposal path handling support (autonomous "none" vs value + dedup +
/// autoGenerateTasks:true *only* for autonomous + correct target even under group
/// impersonation via god's dance), generateObjectiveTasks (uses 2000 budget +
/// central stripThinkBlocks cb for thinking models), _checkTaskCompletionInBackground
/// (uses 2000 + strip; task vs taskless completion; all-tasks-done quests are
/// retired via deact so the primary slot frees up for the next autonomous main
/// quest) + closely related prompt/strip/parse sites inside them.
///
/// Per extraction order (step 11 after llm_eval_engine step 9 + realism_evals step 10
/// per docs/refactoring-guide.md table and CLAUDE.md Critical Services / Path Map).
/// The proposed_objective "none" vs value + dedup + auto flag decision lives in
/// realism_evals (narrative/oneShot parses); setObjective dispatch + list mutation +
/// load/save/deact coordination stay thin/stayed in god per plan for step9/11
/// (qualify explicitly); the gen/check impls + their internal prompt/strip/parse/
/// 2000 + direct stream moved full here. Correct proposal target (speaking char)
/// even under group non-obs impersonation is preserved via live getActiveCharacter
/// cb (god sets _active + _activeObjectives before calling the evals that may
/// propose + auto-gen; restore after). Proposal decision + set target via dance; gen prompt char read (inside generate after awaits save/load) is best-effort post-unawait and may race the restore in group non-obs; correct for decision/attach but prompt context (charName/scenario in task gen prompt) timing-dependent. (See god setObjective unawaited + impersonation finally + leaf generate getActiveCharacter call site.)
///
/// ChatService (god) owns via late final (after _realismEvals / _llmEvalEngine) +
/// thins/delegations at *every* prior call site for generateObjectiveTasks +
/// _checkTaskCompletionInBackground (full excision of moved code from engine + any
/// old thin bodies). 0 @Deprecated shims.
///
/// Granular callbacks for cross-state (engine fire/strip/extract via god thins —
/// strip used here for central &lt;think&gt; handling; fire/extract not for these paths
/// as they use direct generateStream with 2000/temp-specific for creative/strict
/// YES/NO), active/group/observer/speaker for impersonation + correct target,
/// pending (not directly here), objectives mgmt cbs that stay thin in god per plan:
/// getActiveObjectives, tasksForObjective, loadActiveObjectives, saveObjectiveTasks,
/// deactivateObjective, getIsCheckingCompletion/setIsCheckingCompletion,
/// markTaskCompleted (thin cb; god impl does find+set completed+save+load per plan for task auto side-effect), onNotify (for final in check),
/// onSaveChat if needed for consistency with siblings, getMessages, getUserName,
/// getRealismEnabled, getActiveCharacter (critical for gen prompt target under
/// impersonation), getLlmService (for isReady + generateStream custom budget/temp).
/// ~19 cbs (getPrimaryObjective removed per deletion hygiene as unused inside gen/check; was only for realism_evals proposal decision path). Live closures in god for test overrides + group per-speaker
/// impersonation (proposal target must be the speaking character in group non-obs).
///
/// 0 new god private _ methods (live grep -c '^\s*void _[a-zA-Z]' lib/services/chat_service.dart
/// must stay exactly 15 after every edit + final; thins + late final + reset comment
/// syncs only).
///
/// Dedicated test: test/services/chat/objective_proposal_test.dart using factory
/// (createTestObjectiveProposal) with *live* closures over group maps + cbs (real
/// dispatch exercised without forcing god internals); 16 `test()` bodies via
/// live `grep -c '^\s*test('` *post mandatory dead noop/placeholder/vestigial/
/// factory-setup deletion as part of task* (see objective_proposal_test header + round 3 for !ready guard+restore coverage + mark no-op/error paths; previous rounds for dels/strengthens; quest-retirement fix added all-tasks-done deact coverage).
///
/// aug/integration tests (llm_eval_engine_test, realism_engine_test,
/// group_realism_test, chat_service_session_test etc.) receive *only* qualified
/// passive notes in headers/comments (exact precedent: "aug exercising only
/// passive/qualified (no objective-proposal-specific aug file edits; full in
/// dedicated + manual; exercised via god thins generate/check ; qualified notes
/// only in dedicated header + god + MD per precedent)"); no leaf-specific logic
/// edits.
///
/// Strict 1:1 vs group + (if relevant) oneShot vs normal parity for
/// proposed_objective "none" vs value + dedup + autoGenerateTasks:true only for
/// autonomous + correct target (even under impersonation; decision/attach via dance, gen prompt read best-effort post-unawait may race restore in group non-obs as qualified); task vs taskless
/// completion paths; 2000 budget + central strip for thinking models. Dispatch
/// preserved exactly via cbs + god's impersonation dance.
///
/// Stateless/prompt-only leaf (no owned reset/seed/load state for objectives;
/// no reset calls needed on leaf); god reset "keep blocks in sync" comments
/// expanded at *all* ~15+ documented sites (full prior+current list + this leaf
/// as "stateless or prompt-only; no reset calls needed") + "incomplete zeroing
/// of secondary config on group/0-session/new-chat now complete" + *both*
/// startNewChat branches explicit + cross-refs (e.g. setActiveCharacter:1572).
///
/// Anti-accumulation/dead-code audit: explicit greps/audit of affected methods
/// in god (no new _Proposal/*Objective/Gen/Check/Task privates in god); deletion
/// of moved code + any dead/vestigial as part of task.
///
/// Barrel not added (internal to ChatService only; per "unless 3+ locations").
///
/// Some objective mgmt / prompt coordination / list mutation may stay thin in
/// god per plan (qualify explicitly in leaf header + god thins + test + MD:
/// "thin delegation here; full objective proposal in step 11").
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

      // IMPORTANT: these tasks are the CHARACTER's own steps, not a quest handed to
      // the player. The actor must be stated explicitly and the user named as the
      // forbidden subject — without this, "quest designer" framing biases models
      // (especially smaller local models) into writing tasks for $userName to do.
      final prompt =
          '$preamble'
          'You are breaking an objective down into the concrete steps that $charName — the CHARACTER, not the user — will personally carry out to pursue it. '
          'Given the objective, context, and recent conversation below, generate exactly $taskCount sequential tasks '
          'that $charName performs to achieve the objective. '
          'Every task is an in-story action $charName personally takes — NEVER an instruction, request, or task assigned to $userName (the user/player). '
          'Write each task in the third person with $charName as the one acting. '
          'Tasks should be specific, actionable, and naturally progress the story. '
          'Do NOT include tasks for things that have already happened in the conversation.\n\n'
          'Character who carries out every task: $charName\n'
          'Scenario: $scenario\n'
          'Objective $charName is pursuing: ${obj.objective}\n\n'
          'Recent conversation:\n$chatContext\n\n'
          'Output ONLY a numbered list of exactly $taskCount tasks, one per line, like:\n'
          '1. [a specific action $charName takes]\n'
          '2. [a specific action $charName takes]\n'
          '...\n'
          'Each task is a short, clear action $charName performs. No preamble, no explanations, just the numbered list.';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 2000,
        temperature: 0.7,
        stopSequences: [],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
      }

      // Strip &lt;think&gt;...&lt;/think&gt; blocks (and unclosed ones) so thinking models can
      // reason at length before emitting the final numbered list. We increased
      // maxLength to 2000 to give them room.
      responseText = stripThinkBlocks(responseText);

      debugPrint('[Objective] Raw tasks response:\n$responseText');

      // Parse numbered list — tolerant of multiple formats (1. / 1) / - / bullet / plain)
      final lines = responseText.split('\n');
      final genTasks = <Map<String, dynamic>>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // Try numbered: "1. ...", "1) ...", "1 - ..."
        final numbered = RegExp(r'^\d+[\.\)\-]?\s*(.+)').firstMatch(trimmed);
        if (numbered != null) {
          final desc = numbered.group(1)!.trim();
          if (desc.isNotEmpty && !desc.startsWith('[')) {
            genTasks.add({'description': desc, 'completed': false});
          }
          continue;
        }
        // Try bullet: "- ...", "• ...", "* ..."
        final bullet = RegExp(r'^[-•*]\s+(.+)').firstMatch(trimmed);
        if (bullet != null) {
          final desc = bullet.group(1)!.trim();
          if (desc.isNotEmpty) {
            genTasks.add({'description': desc, 'completed': false});
          }
          continue;
        }
        // Plain sentence fallback (skip very short lines or header-like lines)
        if (trimmed.length > 15 &&
            !trimmed.endsWith(':') &&
            genTasks.length < taskCount) {
          genTasks.add({'description': trimmed, 'completed': false});
        }
      }

      // De-duplicate and cap
      final seen = <String>{};
      final uniqueTasks = genTasks
          .where((t) => seen.add(t['description'] as String))
          .take(taskCount)
          .toList();

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
  /// "overtaken by events" (checks run every user turn with realism on, so
  /// this is ~4 turns of the story having moved past it — maintainer tuned
  /// down from 8: a step the plot left behind should not linger).
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

      final msgs = getMessages();
      final recentMessages = msgs.length > 8
          ? msgs.sublist(msgs.length - 8)
          : msgs;
      final contextText = recentMessages
          .map((m) => '${m.sender}: ${m.text}')
          .join('\n');

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
      final prompt =
          'You are evaluating whether roleplay tasks/objectives have been '
          'completed based on recent conversation. Be generous in your '
          'assessment — if the events in the conversation show an item has '
          'been accomplished, partially fulfilled, or naturally resolved, '
          'answer YES for it.\n\n'
          'Recent conversation:\n$contextText\n\n'
          'Evaluate EACH item below. Reply with ONLY one line per item, in '
          'order, formatted exactly as "1: YES" or "1: NO" — no explanations.\n'
          '${itemLines.join('\n')}';

      final params = GenerationParams(
        prompt: prompt,
        // Reasoning OFF (same recipe as LlmEvalEngine/Journal): thinking
        // models were burning up to 2,000 tokens at local decode speed to
        // reason about YES/NO verdicts — the bulk of the multi-minute
        // objective stall on a 31B (maintainer report 2026-07-15).
        // reasoningMaxTokens: 0 forces the disable block onto remote
        // ":thinking" hybrids too. maxLength stays generous as headroom for
        // models that leak reasoning anyway (stripThinkBlocks cleans it).
        maxLength: 2000,
        temperature: 0.1,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        stopSequences: [],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
      }
      responseText = stripThinkBlocks(responseText);
      // One raw log per batch so a parse failure or surprise YES is
      // diagnosable (review finding: verdict-only logging hid them).
      final rawPreview = responseText.replaceAll('\n', ' / ');
      debugPrint(
        '[Objective] Batched verdicts raw: '
        '"${rawPreview.length > 300 ? rawPreview.substring(0, 300) : rawPreview}"',
      );

      // Forgiving parse (local-model floor): "1: YES", "1. YES", "1) yes"…
      final verdicts = <int, bool>{};
      for (final m in RegExp(
        r'^\s*(\d+)\s*[:.)\-]\s*(YES|NO)\b',
        multiLine: true,
        caseSensitive: false,
      ).allMatches(responseText)) {
        verdicts[int.parse(m.group(1)!)] =
            m.group(2)!.toUpperCase() == 'YES';
      }
      // Single-item fallback keeps the historical loose behavior when a
      // model ignores the numbering entirely.
      if (verdicts.isEmpty && pending.length == 1) {
        verdicts[1] = responseText.toUpperCase().contains('YES');
      }

      for (var i = 0; i < pending.length; i++) {
        final (obj, tasks, currentTask) = pending[i];
        var done = verdicts[i + 1] ?? false;
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
}
