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

/// Prompt injection for author notes / objective system text (primary +
/// secondary/autonomous objectives with task progress). Always-present
/// fixed section so it is never budget-trimmed. Objectives are
/// chat/session scoped.
class AuthorNoteBuilder {
  final List<dynamic> Function() getActiveObjectives;
  final dynamic Function() getPrimaryObjective;
  final List<Map<String, dynamic>> Function(dynamic obj) tasksForObjective;
  final List<dynamic> Function() getSecondaryObjectives;

  AuthorNoteBuilder({
    required this.getActiveObjectives,
    required this.getPrimaryObjective,
    required this.tasksForObjective,
    required this.getSecondaryObjectives,
  });

  // ── Public surface (for thin delegation in ChatService + tests) ──

  /// Build the prompt injection text for the active objectives.
  /// Wording intensity varies based on injection depth for the primary objective.
  /// Secondary objectives are injected as ambient background goals.
  /// (Verbatim from god _getObjectiveInjection, adapted to cbs.)
  String buildObjectiveInjection() {
    final activeObjectives = getActiveObjectives();
    if (activeObjectives.isEmpty) return '';
    final sb = StringBuffer();
    // Set by every branch that names a concrete step, so the staleness hedge
    // below is written ONCE for the whole block rather than per objective
    // (docs/design/prompt-state-injection.md §6.1 — one register, each fact
    // once). See the hedge's own comment for why it is needed at all.
    var namedAStep = false;

    // 1. Primary Objective
    final pObj = getPrimaryObjective();
    if (pObj != null) {
      final tasks = tasksForObjective(pObj);

      if (tasks.isNotEmpty) {
        final completedTasks = tasks
            .where((t) => t['completed'] == true)
            .map((t) => t['description'] as String)
            .toList();
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;

        if (currentTask != null) {
          namedAStep = true;
          final depth = (pObj is Map
              ? (pObj['injectionDepth'] as num?)?.toInt() ?? 4
              : pObj.injectionDepth);
          final objGoal =
              (pObj is Map
                  ? (pObj['objective'] as String?)
                  : pObj?.objective) ??
              '';
          if (depth <= 2) {
            sb.writeln(
              '[PRIMARY OBJECTIVE (IMPORTANT — actively drive the story toward this):',
            );
            sb.writeln('  Goal: $objGoal');
            sb.writeln('  Current Task: $currentTask');
            if (completedTasks.isNotEmpty) {
              sb.writeln('  Completed: ${completedTasks.join(", ")}');
            }
            sb.writeln(
              '  Guide the narrative toward completing the current task.]',
            );
          } else if (depth <= 6) {
            sb.writeln('[Current Primary Objective: $objGoal]');
            sb.writeln('[Current Task: $currentTask]');
            if (completedTasks.isNotEmpty) {
              sb.writeln('[Completed: ${completedTasks.join(", ")}]');
            }
          } else {
            sb.writeln(
              '[Background primary objective (subtle hint): $objGoal — current step: $currentTask]',
            );
          }
        }
      } else {
        // No tasks, inject objective directly
        final depth = (pObj is Map
            ? (pObj['injectionDepth'] as num?)?.toInt() ?? 4
            : pObj.injectionDepth);
        final objGoal =
            (pObj is Map ? (pObj['objective'] as String?) : pObj?.objective) ??
            '';
        if (depth <= 2) {
          sb.writeln(
            '[PRIMARY OBJECTIVE (IMPORTANT — actively drive the story toward this): $objGoal]',
          );
        } else if (depth <= 6) {
          sb.writeln('[Current Primary Objective: $objGoal]');
        } else {
          sb.writeln('[Background primary objective (subtle hint): $objGoal]');
        }
      }
    }

    // 2. Secondary/Autonomous Objectives — treated as genuine internal drives, not hints
    final secondaries = getSecondaryObjectives();
    if (secondaries.isNotEmpty) {
      sb.writeln();
      for (final sObj in secondaries) {
        final tasks = tasksForObjective(sObj);
        final completedTasks = tasks
            .where((t) => t['completed'] == true)
            .map((t) => t['description'] as String)
            .toList();
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;
        if (currentTask != null) {
          namedAStep = true;
          final sGoal =
              (sObj is Map
                  ? (sObj['objective'] as String?)
                  : sObj?.objective) ??
              '';
          sb.writeln(
            '[AUTONOMOUS GOAL (this character genuinely wants this): $sGoal]',
          );
          sb.writeln(
            '[Pursue this naturally and actively. Current step to work toward: $currentTask]',
          );
          if (completedTasks.isNotEmpty) {
            sb.writeln('[Already accomplished: ${completedTasks.join(", ")}]');
          }
        } else if (tasks.isEmpty) {
          final sGoal =
              (sObj is Map
                  ? (sObj['objective'] as String?)
                  : sObj?.objective) ??
              '';
          sb.writeln(
            '[AUTONOMOUS GOAL (this character genuinely wants this — pursue it actively): $sGoal]',
          );
        }
      }
    }

    // Staleness hedge (docs/design/prompt-state-injection.md §6.1). Task
    // completion is checked FIRE-AND-FORGET in the background
    // (ObjectiveProposal.checkTaskCompletionInBackground), so the step named
    // above is routinely one the story already walked past — and it is stated
    // as a flat instruction ("Current step to work toward"). A model that
    // obeys it literally re-stages a scene that already happened; Kimi 2.6
    // instead burned its reasoning budget deciding to disregard "the outdated
    // current task". Neither is what we want: say plainly that the tracker
    // lags and that the transcript settles it.
    if (namedAStep) {
      sb.writeln(
        '[Progress is tracked in the background and can lag the story: if '
        'the conversation already shows the current step happening, it is '
        'done — carry on from there instead of staging it again.]',
      );
    }
    if (sb.isNotEmpty) sb.writeln();
    return sb.toString();
  }
}
