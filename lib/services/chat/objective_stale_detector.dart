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

/// Objective-level staleness: consecutive-NO counting, durable task stale
/// flags, and quest exhaustion fate. Pure — the LLM call already happened
/// before anything here runs, so a Dart short-circuit does NOT save tokens.
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

/// Allowed Porch Life values: off / 1 / 2 (default) / 4.
int normalizeObjectiveStaleThreshold(int? raw) => switch (raw) {
  0 || 1 || 2 || 4 => raw!,
  _ => 2,
};

/// How a quest with no remaining open task should retire.
enum QuestExhaustion { open, achieved, stale }

QuestExhaustion questExhaustion(Iterable<Map<String, dynamic>> tasks) {
  final list = tasks.toList();
  if (list.isEmpty) return QuestExhaustion.open;
  if (list.any(objectiveTaskIsOpen)) return QuestExhaustion.open;
  if (list.any(objectiveTaskIsStale)) return QuestExhaustion.stale;
  return QuestExhaustion.achieved;
}

/// In-memory consecutive explicit `objective_relevant=NO` counts, keyed by
/// objective id. A restart merely delays retirement; nothing is persisted.
class ObjectiveStaleTracker {
  final Map<String, int> _consecutiveIrrelevant = {};

  /// [explicitIrrelevant] must be an explicit NO. Unsure/KEEP resets.
  /// [thresholdN] 0 = off (never retire for objective-level irrelevance).
  bool noteObjectiveIrrelevant({
    required String objectiveId,
    required bool explicitIrrelevant,
    required int thresholdN,
  }) {
    if (!explicitIrrelevant) {
      _consecutiveIrrelevant.remove(objectiveId);
      return false;
    }
    if (thresholdN <= 0) return false;
    final n = (_consecutiveIrrelevant[objectiveId] ?? 0) + 1;
    if (n >= thresholdN) {
      _consecutiveIrrelevant.remove(objectiveId);
      return true;
    }
    _consecutiveIrrelevant[objectiveId] = n;
    return false;
  }

  void forget(String objectiveId) => _consecutiveIrrelevant.remove(objectiveId);
}

/// What the orchestrator should persist after one parsed item.
enum ObjectiveApplyKind {
  none,
  completeOpenTask,
  completeOpenTaskAndAchieve,
  staleOpenTask,
  staleOpenTaskAndRetire,
  retireObjectiveStale,
  achieveTaskless,
}

class ObjectiveApply {
  const ObjectiveApply(this.kind, {this.taskDescription});

  final ObjectiveApplyKind kind;
  final String? taskDescription;

  bool get creditsAchievement =>
      kind == ObjectiveApplyKind.completeOpenTask ||
      kind == ObjectiveApplyKind.completeOpenTaskAndAchieve ||
      kind == ObjectiveApplyKind.achieveTaskless;

  bool get retiresStale =>
      kind == ObjectiveApplyKind.staleOpenTaskAndRetire ||
      kind == ObjectiveApplyKind.retireObjectiveStale;
}

/// Task-stale is immediate. Objective-stale uses [retireObjectiveNow]
/// (the tracker). Unparsed/KEEP relevance never reaches a stale kind.
ObjectiveApply decideObjectiveApply({
  required List<Map<String, dynamic>> tasks,
  required String? currentOpenTask,
  required bool objectiveRelevant,
  required bool taskRelevant,
  required bool taskDone,
  required bool retireObjectiveNow,
}) {
  if (!objectiveRelevant && retireObjectiveNow) {
    return const ObjectiveApply(ObjectiveApplyKind.retireObjectiveStale);
  }
  if (!objectiveRelevant) return const ObjectiveApply(ObjectiveApplyKind.none);

  if (tasks.isEmpty) {
    return taskDone
        ? const ObjectiveApply(ObjectiveApplyKind.achieveTaskless)
        : const ObjectiveApply(ObjectiveApplyKind.none);
  }
  if (currentOpenTask == null) {
    return const ObjectiveApply(ObjectiveApplyKind.none);
  }

  final lastOpen = tasks.where(objectiveTaskIsOpen).length <= 1;
  if (!taskRelevant) {
    return ObjectiveApply(
      lastOpen
          ? ObjectiveApplyKind.staleOpenTaskAndRetire
          : ObjectiveApplyKind.staleOpenTask,
      taskDescription: currentOpenTask,
    );
  }
  if (!taskDone) return const ObjectiveApply(ObjectiveApplyKind.none);
  return ObjectiveApply(
    lastOpen
        ? ObjectiveApplyKind.completeOpenTaskAndAchieve
        : ObjectiveApplyKind.completeOpenTask,
    taskDescription: currentOpenTask,
  );
}
