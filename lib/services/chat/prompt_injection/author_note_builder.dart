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

import 'package:front_porch_ai/services/chat/objective_origin.dart';
import 'package:front_porch_ai/services/chat/objective_stale_detector.dart';

/// The goals block of the prompt (docs/design/objectives-that-keep-up.md
/// part 5), in two voices: a goal the user or the card set reads as where
/// the story is heading; a goal the character chose reads as what they want,
/// never as an order. A goal set aside is left out. A fixed section, so it is
/// never budget-trimmed; macro-resolved by the caller (`{{char}}` is the
/// speaker in a group).
class AuthorNoteBuilder {
  final List<dynamic> Function() getActiveObjectives;
  final dynamic Function() getPrimaryObjective;
  final List<Map<String, dynamic>> Function(dynamic obj) tasksForObjective;
  final List<dynamic> Function() getSecondaryObjectives;

  /// One line, in words, when the character's last goals all went the same
  /// way (objectives-that-keep-up.md part 6); null otherwise.
  final String? Function()? getStreakLine;

  AuthorNoteBuilder({
    required this.getActiveObjectives,
    required this.getPrimaryObjective,
    required this.tasksForObjective,
    required this.getSecondaryObjectives,
    this.getStreakLine,
  });

  // Objective rows in the app, plain maps in tests.
  static String _goal(dynamic o) =>
      ((o is Map ? o['objective'] as String? : o.objective as String?) ?? '')
          .trim();

  static String? _status(dynamic o) =>
      o is Map ? o['status'] as String? : o.status as String?;

  static bool _ownWant(dynamic o) {
    if (o is! Map) return objectiveIsOwnWant(o);
    final origin = (o['origin'] as String?)?.trim() ?? '';
    if (origin.isNotEmpty) {
      return origin == kObjectiveOriginCharacter ||
          origin == kObjectiveOriginPlanner;
    }
    return ((o['servedAmbition'] as String?)?.trim().isNotEmpty) ?? false;
  }

  String _line(dynamic o, {required bool primary}) {
    final goal = _goal(o);
    if (goal.isEmpty || _status(o) == kObjectiveStatusDormant) return '';
    final tasks = tasksForObjective(o);
    final next = currentOpenTaskDescription(tasks);
    final done = tasks.where(objectiveTaskIsCompleted).toList();
    final last = done.isEmpty ? null : done.last['description'] as String?;
    if (_ownWant(o)) {
      final head = primary
          ? 'Most of all, {{char}} wants: $goal.'
          : '{{char}} also wants: $goal.';
      final sb = StringBuffer('[$head');
      if (last != null && last.trim().isNotEmpty) {
        sb.write(' Already done: ${last.trim()}.');
      }
      if (next != null) sb.write(" What they'd do next: $next.");
      sb.write(']');
      return sb.toString();
    }
    final sb = StringBuffer('[Story direction: $goal.');
    if (next != null) sb.write(' Next: $next.');
    sb.write(']');
    return sb.toString();
  }

  String buildObjectiveInjection() {
    final streak = getStreakLine?.call()?.trim() ?? '';
    final lines = <String>[
      if (getActiveObjectives().isNotEmpty) ...[
        if (getPrimaryObjective() case final p?) _line(p, primary: true),
        for (final s in getSecondaryObjectives()) _line(s, primary: false),
      ],
      if (streak.isNotEmpty) '[$streak]',
    ].where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return '';
    return '${lines.join('\n')}\n\n';
  }
}
