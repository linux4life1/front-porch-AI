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

/// The goal sync's tool and prompt (docs/design/objectives-that-keep-up.md
/// part 1): one batched call asks, per open goal, where it stands, which
/// steps the exchange shows done in any order, and what the next step is
/// now. Same tools-vs-text fork every eval uses; the text floor is a line
/// per goal.
library;

import 'dart:convert';

import 'package:front_porch_ai/services/services.dart' show LlmToolCall;

const String kObjectiveSyncTool = 'report_objective_sync';

/// The four answers a goal can get.
const List<String> kObjectiveSyncStatuses = [
  'on_track',
  'done',
  'overtaken',
  'dormant',
];

final List<Map<String, dynamic>> kObjectiveSyncEvalTools = [
  {
    'type': 'function',
    'function': {
      'name': kObjectiveSyncTool,
      'description':
          'Report where each numbered goal stands. One entry per goal, in '
          'order. Never call an overtaken goal done.',
      'parameters': {
        'type': 'object',
        'properties': {
          'goals': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'goal': {'type': 'integer'},
                'status': {'type': 'string', 'enum': kObjectiveSyncStatuses},
                'steps_done': {
                  'type': 'array',
                  'items': {'type': 'integer'},
                },
                'next_step': {'type': 'string'},
              },
              'required': ['goal', 'status', 'steps_done', 'next_step'],
            },
          },
        },
        'required': ['goals'],
      },
    },
  },
];

/// A matching tool call as flat JSON the parser reads. Tolerates the
/// parallel-array shape small local models flatten nested arguments into.
String? objectiveSyncCallToJson(List<LlmToolCall> calls) {
  for (final call in calls) {
    if (call.name != kObjectiveSyncTool) continue;
    final goals = call.arguments['goals'];
    if (goals is List) return jsonEncode({'goals': goals});
    final status = call.arguments['status'];
    if (status is List) {
      return jsonEncode({
        'status': status,
        'steps_done': call.arguments['steps_done'],
        'next_step': call.arguments['next_step'],
      });
    }
  }
  return null;
}

/// One goal as the sync sees it.
class ObjectiveSyncItem {
  const ObjectiveSyncItem({
    required this.goal,
    required this.steps,
    this.dormant = false,
    this.stepsFixed = false,
  });

  final String goal;

  /// Each step's description and state: 'done', 'open' or 'skipped'.
  final List<(String, String)> steps;
  final bool dormant;

  /// The user or the card wrote the steps: answer "none" for next_step.
  final bool stepsFixed;
}

String _itemBlock(int n, ObjectiveSyncItem item) {
  final sb = StringBuffer('$n. Goal: "${item.goal}"');
  if (item.dormant) sb.write(' (set aside for now)');
  if (item.steps.isEmpty) {
    sb.write(
      ' (no steps: done only if the conversation shows the goal '
      'itself accomplished)',
    );
  }
  for (var i = 0; i < item.steps.length; i++) {
    final (text, state) = item.steps[i];
    final mark = switch (state) {
      'done' => '[x]',
      'skipped' => '(skipped)',
      _ => '[ ]',
    };
    sb.write('\n   ${i + 1}. $mark $text');
  }
  if (item.stepsFixed) {
    sb.write('\n   (steps written by the user: next_step is "none")');
  }
  return sb.toString();
}

String buildObjectiveSyncPrompt({
  required String contextText,
  required List<ObjectiveSyncItem> items,
  required bool toolsMode,
  String elapsedSpan = '',
}) {
  final goals = [
    for (var i = 0; i < items.length; i++) _itemBlock(i + 1, items[i]),
  ].join('\n');
  const rules =
      'For each goal give:\n'
      '- status: "on_track" if it is still being pursued or simply not '
      'touched yet (the answer when unsure); "done" only if the conversation '
      'shows the goal itself accomplished; "overtaken" if the story clearly '
      'abandoned, contradicted or made it moot (never a win); "dormant" if it '
      'is still wanted but the story cannot act on it now (another place, '
      'another time). A goal set aside that can be acted on again is '
      '"on_track".\n'
      '- steps_done: the numbers of OPEN steps the conversation shows done, '
      'in any order; [] when none. Count a step done when it is shown or '
      'naturally resolved; when unsure, leave it out.\n'
      '- next_step: for a goal still on track, the next concrete thing to do '
      'from where the story is NOW, in at most fifteen words, when the next '
      'open step no longer fits; otherwise "none".\n\n';
  final span = elapsedSpan.trim().isEmpty ? '' : '${elapsedSpan.trim()}\n\n';
  final closing = toolsMode
      ? 'Evaluate EACH item below. Report by calling the $kObjectiveSyncTool '
            'tool with one entry in "goals" per item, in order, "goal" being '
            'its number. Use ONLY the tool — no plain-text reply.\n$goals'
      : 'Evaluate EACH item below. Reply with ONLY one line per item, in '
            'order, formatted exactly as:\n'
            '1: on_track | 2,3 | <next step or none>\n'
            '2: overtaken | none | none\n'
            'No explanations.\n$goals';
  return 'Recent conversation:\n$contextText\n\n$span$rules$closing';
}
