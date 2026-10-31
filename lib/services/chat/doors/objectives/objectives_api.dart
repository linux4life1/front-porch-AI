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

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';

/// The objectives' old names on [ChatService]. Every body only calls
/// [ChatService.objectivesDoor]; the shell exports this library so callers
/// keep their imports.
extension ChatServiceObjectivesApi on ChatService {
  /// All active objectives for the current character/session (both primary
  /// and secondary; see [primaryObjective] / [secondaryObjectives]).
  List<Objective> get activeObjectives => objectivesDoor.activeObjectives;

  /// The sidebar's task-generation prefs (session-held, not persisted).
  bool get objectiveNsfwTasks => objectivesDoor.objectiveNsfwTasks;
  set objectiveNsfwTasks(bool value) =>
      objectivesDoor.objectiveNsfwTasks = value;
  int get objectiveTaskCount => objectivesDoor.objectiveTaskCount;
  set objectiveTaskCount(int value) =>
      objectivesDoor.objectiveTaskCount = value;

  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    CharacterCard? targetCharacter,
    bool autoGenerateTasks = false,
    bool recordTurnOps = false,
    String? servedAmbition,
    String origin = kObjectiveOriginUser,
  }) => objectivesDoor.writer.setObjective(
    goal,
    isPrimary: isPrimary,
    targetCharacter: targetCharacter,
    autoGenerateTasks: autoGenerateTasks,
    recordTurnOps: recordTurnOps,
    servedAmbition: servedAmbition,
    origin: origin,
  );

  Future<void> promoteObjective(Objective obj) =>
      objectivesDoor.writer.promote(obj);

  Future<void> clearObjective(Objective obj) =>
      objectivesDoor.writer.clear(obj);

  List<Map<String, dynamic>> tasksForObjective(Objective obj) =>
      objectivesDoor.tasks.tasksFor(obj);

  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) => objectivesDoor.tasks.generate(obj, taskCount: taskCount, nsfw: nsfw);

  Future<void> toggleTask(Objective obj, int taskIndex) =>
      objectivesDoor.tasks.toggle(obj, taskIndex);

  Future<void> updateTask(
    Objective obj,
    int taskIndex,
    String newDescription,
  ) => objectivesDoor.tasks.update(obj, taskIndex, newDescription);

  Future<void> addManualTask(Objective obj, String description) =>
      objectivesDoor.tasks.add(obj, description);

  Future<void> removeTask(Objective obj, int taskIndex) =>
      objectivesDoor.tasks.remove(obj, taskIndex);

  Future<void> updateCheckFrequency(Objective obj, int frequency) =>
      objectivesDoor.tasks.updateCheckFrequency(obj, frequency);

  void forceCheckCompletion() => objectivesDoor.forceCheckCompletion();

  Future<void> focusObjectivesForGroupCharacter(CharacterCard character) =>
      objectivesDoor.focusObjectivesForGroupCharacter(character);
}
