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

part of 'chat_tools_facade.dart';

/// Quests: set, generate and edit tasks, completion checks, promotion, and
/// abandoning today's side quest.
extension ChatToolsFacadeObjectives on ChatToolsFacade {
  // ── Objectives (per-character; scoped to the focused cast participant so a
  //    new goal attaches to whoever the sidebar is focused on) ───────────────
  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    String? participantId,
  }) async {
    if (!_chat.objectivesActive) return;
    await _chat.setObjective(
      goal,
      isPrimary: isPrimary,
      targetCharacter: _focusedParticipant(participantId)?.card,
    );
    _notify();
  }

  /// Generate tasks for the objective with [id]. Returns false if unknown.
  Future<bool> generateTasks(
    String id, {
    int taskCount = 5,
    bool nsfw = false,
  }) {
    if (!_chat.objectivesActive) return Future.value(false);
    return _withObjective(id, (o) async {
      await _chat.generateObjectiveTasks(o, taskCount: taskCount, nsfw: nsfw);
    });
  }

  Future<bool> addTask(String id, String description) {
    return _withObjective(id, (o) => _chat.addManualTask(o, description));
  }

  Future<bool> toggleTask(String id, int taskIndex) {
    return _withObjective(id, (o) => _chat.toggleTask(o, taskIndex));
  }

  Future<bool> updateTask(String id, int taskIndex, String description) {
    return _withObjective(
      id,
      (o) => _chat.updateTask(o, taskIndex, description),
    );
  }

  Future<bool> removeTask(String id, int taskIndex) {
    return _withObjective(id, (o) => _chat.removeTask(o, taskIndex));
  }

  Future<bool> setCheckFrequency(String id, int frequency) {
    return _withObjective(id, (o) => _chat.updateCheckFrequency(o, frequency));
  }

  Future<bool> clearObjective(String id) {
    return _withObjective(id, (o) => _chat.clearObjective(o));
  }

  /// Promote a side quest to the primary quest in place (same
  /// [ChatService.promoteObjective] the desktop sidebar uses — keeps tasks,
  /// demotes any existing primary).
  Future<bool> promoteObjective(String id) {
    return _withObjective(id, (o) => _chat.promoteObjective(o));
  }

  void checkCompletion() {
    _chat.forceCheckCompletion();
    _notify();
  }

  void abandonToday() {
    _chat.abandonToday();
    _notify();
  }

  /// Resolve an objective by id, run [action], notify. Searches every cast
  /// participant's objectives (not just the host's) so task ops work on whoever
  /// the sidebar is focused on, in 1:1 or group.
  Future<bool> _withObjective(
    String id,
    Future<void> Function(Objective) action,
  ) async {
    final seen = <String>{};
    final all = <Objective>[
      if (_chat.primaryObjective != null) _chat.primaryObjective!,
      ..._chat.secondaryObjectives,
      for (final p in _chat.cast)
        ..._chat.getObjectivesForGroupCharacter(p.card),
    ];
    Objective? match;
    for (final o in all) {
      if (!seen.add(o.id)) continue;
      if (o.id == id) {
        match = o;
        break;
      }
    }
    if (match == null) return false;
    await action(match);
    _notify();
    return true;
  }
}
