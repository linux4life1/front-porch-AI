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

/// Step generation's tool, parser and prompt — the same tools-vs-text fork
/// Realism uses (`fireStructuredEval` + `preferTextEvals`). Taking up a goal
/// stays on the narrative judge; where a goal stands is the goal sync
/// (objective_sync_tools.dart).
library;

import 'dart:convert';

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/services.dart' show LlmToolCall;

const String kObjectiveTasksTool = 'report_objective_tasks';

final List<Map<String, dynamic>> kObjectiveTasksEvalTools = [
  {
    'type': 'function',
    'function': {
      'name': kObjectiveTasksTool,
      'description':
          'Report the character\'s own next steps for the objective.',
      'parameters': {
        'type': 'object',
        'properties': {
          'tasks': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Sequential in-story actions the CHARACTER personally takes, '
                'never the user.',
          },
        },
        'required': ['tasks'],
      },
    },
  },
];

List<String>? _asStringList(dynamic v) {
  if (v == null) return null;
  if (v is List) {
    return [
      for (final e in v)
        if (e != null) e.toString(),
    ];
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return [s];
}

/// A matching step-generation tool call as the flat JSON the parser reads.
/// An empty array is a real answer (parse-fail restore), never a reason to
/// fall back to text.
String? objectiveToolCallToJson(String toolName, List<LlmToolCall> calls) {
  if (toolName != kObjectiveTasksTool) return null;
  for (final call in calls) {
    if (call.name != toolName) continue;
    final list = _asStringList(call.arguments['tasks']);
    if (list == null) continue;
    return jsonEncode({'tasks': list});
  }
  return null;
}

List<String>? _stringListFromJsonKey(String text, String key) {
  final decoded = parseEvalJsonObject(text);
  if (decoded == null || !decoded.containsKey(key)) return null;
  return _asStringList(decoded[key]);
}

/// Deduped, capped task maps (`description` + `completed: false`).
List<Map<String, dynamic>> parseObjectiveTasks(String text, int taskCount) {
  final cap = taskCount < 1 ? 1 : taskCount;
  final fromJson = _stringListFromJsonKey(text, 'tasks');
  final genTasks = <Map<String, dynamic>>[];
  void addDesc(String desc) {
    final t = desc.trim();
    if (t.isEmpty || t.startsWith('[')) return;
    genTasks.add({'description': t, 'completed': false});
  }

  if (fromJson != null) {
    for (final d in fromJson) {
      addDesc(d);
    }
  } else {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final numbered = RegExp(r'^\d+[\.\)\-]?\s*(.+)').firstMatch(trimmed);
      if (numbered != null) {
        addDesc(numbered.group(1)!);
        continue;
      }
      final bullet = RegExp(r'^[-•*]\s+(.+)').firstMatch(trimmed);
      if (bullet != null) {
        addDesc(bullet.group(1)!);
        continue;
      }
      if (trimmed.length > 15 &&
          !trimmed.endsWith(':') &&
          genTasks.length < cap) {
        addDesc(trimmed);
      }
    }
  }
  final seen = <String>{};
  return genTasks
      .where((t) => seen.add(t['description'] as String))
      .take(cap)
      .toList();
}

String buildObjectiveTaskGenPrompt({
  required String preamble,
  required String charName,
  required String userName,
  required String scenario,
  required String objective,
  required String chatContext,
  required int taskCount,
  required bool toolsMode,
}) {
  final closing = toolsMode
      ? 'Report by calling the $kObjectiveTasksTool tool with a "tasks" '
            'array of exactly $taskCount strings. Each string is a short, '
            'clear action $charName performs. Use ONLY the tool — no '
            'plain-text reply.'
      : 'Output ONLY a numbered list of exactly $taskCount tasks, one per '
            'line, like:\n'
            '1. [a specific action $charName takes]\n'
            '2. [a specific action $charName takes]\n'
            '...\n'
            'Each task is a short, clear action $charName performs. No '
            'preamble, no explanations, just the numbered list.';
  return '$preamble'
      'You are breaking an objective down into the concrete steps that '
      '$charName — the CHARACTER, not the user — will personally carry '
      'out to pursue it. '
      'Given the objective, context, and recent conversation below, '
      'generate exactly $taskCount sequential tasks that $charName '
      'performs to achieve the objective. '
      'Every task is an in-story action $charName personally takes — '
      'NEVER an instruction, request, or task assigned to $userName '
      '(the user/player). '
      'Write each task in the third person with $charName as the one '
      'acting. '
      'Tasks should be specific, actionable, and naturally progress the '
      'story. '
      'Do NOT include tasks for things that have already happened in the '
      'conversation.\n\n'
      'Character who carries out every task: $charName\n'
      'Scenario: $scenario\n'
      'Objective $charName is pursuing: $objective\n\n'
      'Recent conversation:\n$chatContext\n\n'
      '$closing';
}
