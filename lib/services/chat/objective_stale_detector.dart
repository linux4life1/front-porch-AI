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

/// A goal's step states: open, done, or skipped ("stale", written by builds
/// before the goal sync). Pure. Where a goal stands as a whole is the goal
/// sync's answer (objective_sync_decide.dart).
library;

bool objectiveTaskIsStale(Map<String, dynamic> task) => task['stale'] == true;

bool objectiveTaskIsCompleted(Map<String, dynamic> task) =>
    task['completed'] == true && !objectiveTaskIsStale(task);

bool objectiveTaskIsOpen(Map<String, dynamic> task) =>
    !objectiveTaskIsCompleted(task) && !objectiveTaskIsStale(task);

String? currentOpenTaskDescription(Iterable<Map<String, dynamic>> tasks) {
  for (final task in tasks) {
    if (objectiveTaskIsOpen(task)) {
      final desc = task['description'];
      if (desc is String && desc.isNotEmpty) return desc;
    }
  }
  return null;
}

int completedQuestTaskCount(Iterable<Map<String, dynamic>> tasks) =>
    tasks.where(objectiveTaskIsCompleted).length;

int countableQuestTaskCount(Iterable<Map<String, dynamic>> tasks) =>
    tasks.where((t) => !objectiveTaskIsStale(t)).length;

/// Completed / non-stale. All-stale (or empty) is 0 — never a 100% win.
double questCompletionRatio(Iterable<Map<String, dynamic>> tasks) {
  final denom = countableQuestTaskCount(tasks);
  if (denom <= 0) return 0;
  return completedQuestTaskCount(tasks) / denom;
}

String questProgressLabel(Iterable<Map<String, dynamic>> tasks) =>
    '${completedQuestTaskCount(tasks)}/${countableQuestTaskCount(tasks)}';

/// Texts the mention gate may use: the goal plus OPEN steps only.
List<String> openQuestMentionTexts(
  String objective,
  Iterable<Map<String, dynamic>> tasks,
) => [
  objective,
  for (final task in tasks)
    if (objectiveTaskIsOpen(task)) (task['description'] as String? ?? ''),
];

/// How a quest with no remaining open task should retire.
enum QuestExhaustion { open, achieved, stale }

QuestExhaustion questExhaustion(Iterable<Map<String, dynamic>> tasks) {
  final list = tasks.toList();
  if (list.isEmpty) return QuestExhaustion.open;
  if (list.any(objectiveTaskIsOpen)) return QuestExhaustion.open;
  if (list.any(objectiveTaskIsStale)) return QuestExhaustion.stale;
  return QuestExhaustion.achieved;
}
