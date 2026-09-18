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

part of '../chat_service.dart';

/// Objective tasks — list decode, generate, and per-task mutate.
extension ChatServiceObjectiveTasks on ChatService {
  /// Parses [obj.tasks] (a JSON-encoded list) into task maps for the UI.
  /// Returns an empty list on any decode failure rather than throwing.
  List<Map<String, dynamic>> tasksForObjective(Objective obj) {
    try {
      return (jsonDecode(obj.tasks) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Generate subtasks for the current objective using the LLM.
  /// Clears existing tasks first so regen always produces a clean slate.
  // Thin delegation (full generateObjectiveTasks + 2000 budget + central strip + proposal
  // handling in objective_proposal step 11; objective mgmt coordination / list / load / db
  // updates stayed thin in god per plan for step9/11; "thin delegation here; full objective
  // proposal in step 11").
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) => _objectiveProposal.generateObjectiveTasks(
    obj,
    taskCount: taskCount,
    nsfw: nsfw,
  );

  /// Marks the first uncompleted task matching taskDesc as completed (best-effort side-effect
  /// for auto-complete in checkTaskCompletionInBackground currentTask YES path).
  /// (Thin delegation; full mutation logic here in god per plan for step 11 to keep list/db
  /// mutation thin/stayed in god; leaf calls via cb. Matches toggleTask pattern exactly.)
  Future<void> markTaskCompleted(Objective obj, String taskDesc) async {
    final tasks = tasksForObjective(obj);
    final idx = tasks.indexWhere(
      (t) => (t['description'] as String) == taskDesc && t['completed'] != true,
    );
    if (idx < 0) return;
    // Turn-op for regen rollback: obj.tasks is still the pre-mutation JSON here,
    // so the inverse is a plain write-back of that string. Armed-gated: manual
    // "Check now" completions are user actions, not turn ops.
    if (_objectiveTurnOpsArmed) {
      _recordObjectiveTurnOp({
        'op': 'tasks_changed',
        'id': obj.id,
        'prev': obj.tasks,
      });
    }
    tasks[idx]['completed'] = true;
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Manually toggle a task's completion status.
  Future<void> toggleTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;

    tasks[taskIndex]['completed'] = !(tasks[taskIndex]['completed'] as bool);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update the description of a specific task.
  Future<void> updateTask(
    Objective obj,
    int taskIndex,
    String newDescription,
  ) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    if (newDescription.trim().isEmpty) return;

    tasks[taskIndex]['description'] = newDescription.trim();
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Add a manually created task to the active objective.
  Future<void> addManualTask(Objective obj, String description) async {
    if (description.trim().isEmpty) return;
    final tasks = tasksForObjective(obj);
    tasks.add({'description': description.trim(), 'completed': false});
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Remove a task from the active objective.
  Future<void> removeTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    tasks.removeAt(taskIndex);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }
}
