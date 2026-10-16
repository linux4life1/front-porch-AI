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

  /// The goal sync's step list: ticks in any order and a rewritten next
  /// step, written once and rewound together by regen (one tasks_changed op
  /// holding the pre-sync list).
  Future<void> _writeSyncedTasks(
    Objective obj,
    List<Map<String, dynamic>> tasks,
  ) => _writeCheckDrivenTasks(obj, tasks);

  /// The sync retires a goal: finished or let go, with when. The turn op
  /// keeps the status it had so a regen puts the goal back exactly.
  Future<void> _retireObjectiveFromSync(Objective obj, ObjectiveEnd end) async {
    if (_objectiveTurnOpsArmed) {
      _recordObjectiveTurnOp({
        'op': 'deactivated',
        'id': obj.id,
        'prevStatus': obj.status,
      });
    }
    await _db.updateObjective(
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
    await _loadActiveObjectives();
  }

  /// The sync sets a goal aside, or wakes it.
  Future<void> _setObjectiveDormant(Objective obj, bool dormant) async {
    if (_objectiveTurnOpsArmed) {
      _recordObjectiveTurnOp({
        'op': 'status',
        'id': obj.id,
        'prev': obj.status,
      });
    }
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        status: drift.Value(dormant ? kObjectiveStatusDormant : null),
      ),
    );
    await _loadActiveObjectives();
  }

  Future<void> _writeCheckDrivenTasks(
    Objective obj,
    List<Map<String, dynamic>> tasks,
  ) async {
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
