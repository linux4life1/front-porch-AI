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

/// What one sync answer does to one goal
/// (docs/design/objectives-that-keep-up.md part 1), and which goals a sync
/// may ask about at all (part 4). Pure: the caller writes and records.
library;

import 'package:front_porch_ai/services/chat/objective_origin.dart';
import 'package:front_porch_ai/services/chat/objective_stale_detector.dart';
import 'package:front_porch_ai/services/chat/objective_sync_parse.dart';

class ObjectiveSyncApply {
  const ObjectiveSyncApply({this.newTasks, this.end, this.dormant});

  /// The step list to write, when a tick or a rewrite changed it.
  final List<Map<String, dynamic>>? newTasks;

  /// The goal leaves the list.
  final ObjectiveEnd? end;

  /// Set aside (true) or woken (false); null leaves it.
  final bool? dormant;

  bool get isNoop => newTasks == null && end == null && dormant == null;

  static const none = ObjectiveSyncApply();
}

ObjectiveSyncApply decideObjectiveSync({
  required List<Map<String, dynamic>> tasks,
  required ObjectiveSyncVerdict verdict,
  required bool stepsAuthored,
  bool isHeldToday = false,
  bool wasDormant = false,
}) {
  if (verdict.isUnsure) return ObjectiveSyncApply.none;
  final copy = [for (final t in tasks) Map<String, dynamic>.from(t)];

  if (verdict.legacyYes) {
    if (copy.isEmpty) {
      return const ObjectiveSyncApply(end: ObjectiveEnd.achieved);
    }
    final first = copy.indexWhere(objectiveTaskIsOpen);
    if (first < 0) return ObjectiveSyncApply.none;
    copy[first]['completed'] = true;
    final exhausted = !copy.any(objectiveTaskIsOpen);
    return ObjectiveSyncApply(
      newTasks: copy,
      end: exhausted ? _exhaustedEnd(copy) : null,
    );
  }

  var changed = false;
  for (final n in verdict.stepsDone) {
    final i = n - 1;
    if (i < 0 || i >= copy.length || !objectiveTaskIsOpen(copy[i])) continue;
    copy[i]['completed'] = true;
    changed = true;
  }

  switch (verdict.status) {
    case 'done':
      return ObjectiveSyncApply(
        newTasks: changed ? copy : null,
        end: ObjectiveEnd.achieved,
      );
    case 'overtaken':
      return ObjectiveSyncApply(
        newTasks: changed ? copy : null,
        end: ObjectiveEnd.letGo,
      );
    case 'dormant':
      // The held today line is the day's plan: setting it aside is the day
      // itself, which the planner already handles. A goal the user or the
      // card set is story direction, not the character's want, so the judge
      // does not get to mute it (live run 2026-10-16: a user goal was set
      // aside on the first sync and never came back to the prompt).
      return ObjectiveSyncApply(
        newTasks: changed ? copy : null,
        dormant: (isHeldToday || wasDormant || stepsAuthored) ? null : true,
      );
  }

  // on_track
  if (copy.isNotEmpty && !copy.any(objectiveTaskIsOpen)) {
    return ObjectiveSyncApply(
      newTasks: changed ? copy : null,
      end: _exhaustedEnd(copy),
    );
  }
  final next = verdict.nextStep?.trim() ?? '';
  if (next.isNotEmpty && !stepsAuthored && copy.isNotEmpty) {
    final open = copy.indexWhere(objectiveTaskIsOpen);
    // A "next step" that is already on the list (often one just ticked) is
    // not new: writing it would tell the model to do it again (live run
    // 2026-10-16).
    final lower = next.toLowerCase();
    final known = copy.any(
      (t) => (t['description'] as String? ?? '').trim().toLowerCase() == lower,
    );
    if (open >= 0 && !known) {
      copy[open]['description'] = next;
      changed = true;
    }
  }
  return ObjectiveSyncApply(
    newTasks: changed ? copy : null,
    dormant: wasDormant ? false : null,
  );
}

ObjectiveEnd _exhaustedEnd(List<Map<String, dynamic>> tasks) =>
    questExhaustion(tasks) == QuestExhaustion.stale
    ? ObjectiveEnd.letGo
    : ObjectiveEnd.achieved;

enum ObjectiveSyncEligibility {
  /// Ask about it.
  include,

  /// Leave it out of this sync.
  skip,

  /// Generate its steps again, then leave it out of this sync.
  retryThenSkip,
}

/// A goal the character just took up is not asked about until its steps
/// exist, so it cannot be "won" on a lenient read before it has any. Step
/// generation is retried once; after that a taskless want stays in, where
/// only an explicit "done" can retire it.
ObjectiveSyncEligibility objectiveSyncEligibility({
  required bool ownWant,
  required bool hasTasks,
  required bool genInFlight,
  required bool genRetried,
}) {
  if (!ownWant || hasTasks) return ObjectiveSyncEligibility.include;
  if (genInFlight) return ObjectiveSyncEligibility.skip;
  if (!genRetried) return ObjectiveSyncEligibility.retryThenSkip;
  return ObjectiveSyncEligibility.include;
}
