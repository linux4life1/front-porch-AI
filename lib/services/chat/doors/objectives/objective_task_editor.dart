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

import 'package:front_porch_ai/database/database.dart'
    show AppDatabaseMemoryQueries, Objective, ObjectivesCompanion;
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';

/// An objective's steps: decode, generate, and the panel's own edits. None
/// of these record turn ops: they are the user's, and regen leaves them.
class ObjectiveTaskEditor {
  ObjectiveTaskEditor(this._door, this._d);

  final ObjectivesDoor _door;
  final ObjectiveDeps _d;

  /// Parses [obj.tasks] (a JSON-encoded list) into task maps for the UI.
  /// Returns an empty list on any decode failure rather than throwing.
  List<Map<String, dynamic>> tasksFor(Objective obj) {
    try {
      return (jsonDecode(obj.tasks) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Generate subtasks for [obj] with the LLM. Clears existing tasks first
  /// so a regen always produces a clean slate.
  Future<void> generate(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) => _d.proposal().generateObjectiveTasks(
    obj,
    taskCount: taskCount,
    nsfw: nsfw,
  );

  /// Update how often task completion is checked.
  Future<void> updateCheckFrequency(Objective obj, int frequency) async {
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        checkFrequency: drift.Value(frequency),
      ),
    );
    await _door.loadActiveObjectives();
  }

  /// Manually toggle a task's completion status.
  Future<void> toggle(Objective obj, int taskIndex) async {
    final tasks = tasksFor(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    tasks[taskIndex]['completed'] = !(tasks[taskIndex]['completed'] as bool);
    await _write(obj, tasks);
  }

  /// Update the description of a specific task.
  Future<void> update(Objective obj, int taskIndex, String description) async {
    final tasks = tasksFor(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    if (description.trim().isEmpty) return;
    tasks[taskIndex]['description'] = description.trim();
    // A step the user rewrote starts fresh: the prompt names it again.
    tasks[taskIndex].remove(kStuckChecksKey);
    await _write(obj, tasks);
  }

  /// Add a manually created task to the objective.
  Future<void> add(Objective obj, String description) async {
    if (description.trim().isEmpty) return;
    final tasks = tasksFor(obj);
    tasks.add({'description': description.trim(), 'completed': false});
    await _write(obj, tasks);
  }

  /// Remove a task from the objective.
  Future<void> remove(Objective obj, int taskIndex) async {
    final tasks = tasksFor(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    tasks.removeAt(taskIndex);
    await _write(obj, tasks);
  }

  Future<void> _write(Objective obj, List<Map<String, dynamic>> tasks) async {
    await _d.db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _door.loadActiveObjectives();
  }
}
