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

/// Objectives eval tools — the same tools-vs-text fork Realism uses
/// (`fireStructuredEval` + `preferTextEvals`), not a third door and not
/// chat-reply / Waifu todo tools. Propose-a-quest stays on the judges;
/// this file is YES/NO completion and task generation only.
library;

import 'dart:convert';

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/services.dart' show LlmToolCall;

const String kObjectiveVerdictsTool = 'report_objective_verdicts';
const String kObjectiveTasksTool = 'report_objective_tasks';

Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, Map<String, dynamic>> fields,
  List<String> required,
) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': fields,
      'required': required,
    },
  },
};

final Map<String, Map<String, dynamic>> _verdictsFields = {
  'objective_relevant': {
    'type': 'array',
    'items': {'type': 'string'},
    'description':
        'YES or NO for each numbered item, in order. Unsure is YES '
        '(KEEP). NO only when the quest is clearly abandoned, contradicted, '
        'or overtaken.',
  },
  'task_relevant': {
    'type': 'array',
    'items': {'type': 'string'},
    'description':
        'YES, NO, or NA for each item, in order. NA if '
        'objective_relevant is NO or the item is taskless. Unsure is YES '
        '(KEEP).',
  },
  'task_done': {
    'type': 'array',
    'items': {'type': 'string'},
    'description':
        'YES, NO, or NA for each item, in order. Unsure is NO. '
        'Taskless: YES means the objective itself completed. NA when '
        'objective_relevant is NO.',
  },
};

final Map<String, Map<String, dynamic>> _tasksFields = {
  'tasks': {
    'type': 'array',
    'items': {'type': 'string'},
    'description':
        'Sequential in-story actions the CHARACTER personally takes, '
        'never the user.',
  },
};

final List<Map<String, dynamic>> kObjectiveVerdictsEvalTools = [
  _tool(
    kObjectiveVerdictsTool,
    'Report relevance and completion for each batched quest/task. '
    'Parallel arrays, same order and length as the numbered items. '
    'Never treat an overtaken quest as completed.',
    _verdictsFields,
    const ['objective_relevant', 'task_relevant', 'task_done'],
  ),
];

final List<Map<String, dynamic>> kObjectiveTasksEvalTools = [
  _tool(
    kObjectiveTasksTool,
    'Report the character\'s own next steps for the objective.',
    _tasksFields,
    const ['tasks'],
  ),
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

/// Convert a matching tool call into flat JSON the parsers consume.
/// Empty arrays are a real answer (all-KEEP / all-NO / parse-fail restore),
/// never a reason to fall back to text.
String? objectiveToolCallToJson(String toolName, List<LlmToolCall> calls) {
  for (final call in calls) {
    if (call.name != toolName) continue;
    if (toolName == kObjectiveVerdictsTool) {
      final objRel = _asStringList(call.arguments['objective_relevant']);
      final taskRel = _asStringList(call.arguments['task_relevant']);
      final taskDone = _asStringList(call.arguments['task_done']);
      if (objRel != null || taskRel != null || taskDone != null) {
        return jsonEncode({
          'objective_relevant': ?objRel,
          'task_relevant': ?taskRel,
          'task_done': ?taskDone,
        });
      }
      final legacy = _asStringList(call.arguments['verdicts']);
      if (legacy != null) return jsonEncode({'verdicts': legacy});
      continue;
    }
    if (toolName == kObjectiveTasksTool) {
      final list = _asStringList(call.arguments['tasks']);
      if (list == null) continue;
      return jsonEncode({'tasks': list});
    }
  }
  return null;
}

/// True only for an explicit yes. Confused / "1" / empty is NO — never
/// complete a quest because the model mumbled.
bool objectiveVerdictIsYes(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  final u = v.toString().trim().toUpperCase();
  if (u.isEmpty || u == 'NO' || u == 'FALSE' || u == 'N') return false;
  if (u == 'YES' || u == 'TRUE' || u == 'Y') return true;
  return RegExp(r'\bYES\b').hasMatch(u);
}

/// One parsed item. Missing / unsure relevance stays KEEP; unsure
/// completion stays NO. Only an explicit NO/STALE can retire.
class ObjectiveItemVerdict {
  const ObjectiveItemVerdict({
    this.objectiveRelevant = true,
    this.taskRelevant = true,
    this.taskDone = false,
  });

  final bool objectiveRelevant;
  final bool taskRelevant;
  final bool taskDone;
}

class ObjectiveCheckParse {
  const ObjectiveCheckParse({required this.items, required this.hadSignal});

  final List<ObjectiveItemVerdict> items;

  /// False when neither tool JSON nor the text floor produced a verdict.
  /// The orchestrator must retain current state — no destructive retire.
  final bool hadSignal;
}

enum _Yn { yes, no, unsure }

_Yn _relevanceToken(dynamic v) {
  if (v == null) return _Yn.unsure;
  if (v is bool) return v ? _Yn.yes : _Yn.no;
  final u = v.toString().trim().toUpperCase();
  if (u.isEmpty || u == 'NA' || u == 'N/A') return _Yn.unsure;
  if (u == 'KEEP' || u == 'RELEVANT' || u == 'YES' || u == 'TRUE' || u == 'Y') {
    return _Yn.yes;
  }
  if (u == 'STALE' || u == 'NO' || u == 'FALSE' || u == 'N') return _Yn.no;
  return _Yn.unsure;
}

ObjectiveItemVerdict _itemFromTokens({
  dynamic objectiveRelevant,
  dynamic taskRelevant,
  dynamic taskDone,
}) {
  final obj = _relevanceToken(objectiveRelevant);
  final task = _relevanceToken(taskRelevant);
  return ObjectiveItemVerdict(
    objectiveRelevant: obj != _Yn.no,
    taskRelevant: task != _Yn.no,
    taskDone: objectiveVerdictIsYes(taskDone),
  );
}

List<String>? _stringListFromJsonKey(String text, String key) {
  final decoded = parseEvalJsonObject(text);
  if (decoded == null || !decoded.containsKey(key)) return null;
  return _asStringList(decoded[key]);
}

/// Flat parallel arrays (or the text floor). Unparsed relevance = KEEP.
ObjectiveCheckParse parseObjectiveCheck(String text, int itemCount) {
  final n = itemCount < 0 ? 0 : itemCount;
  final items = List<ObjectiveItemVerdict>.generate(
    n,
    (_) => const ObjectiveItemVerdict(),
  );
  if (n <= 0) return ObjectiveCheckParse(items: items, hadSignal: false);

  final decoded = parseEvalJsonObject(text);
  if (decoded != null) {
    final objRel = _asStringList(decoded['objective_relevant']);
    final taskRel = _asStringList(decoded['task_relevant']);
    final taskDone = _asStringList(decoded['task_done']);
    final legacy = _asStringList(decoded['verdicts']);
    if (objRel != null || taskRel != null || taskDone != null) {
      for (var i = 0; i < n; i++) {
        items[i] = _itemFromTokens(
          objectiveRelevant: objRel != null && i < objRel.length
              ? objRel[i]
              : null,
          taskRelevant: taskRel != null && i < taskRel.length
              ? taskRel[i]
              : null,
          taskDone: taskDone != null && i < taskDone.length
              ? taskDone[i]
              : null,
        );
      }
      return ObjectiveCheckParse(items: items, hadSignal: true);
    }
    if (legacy != null) {
      for (var i = 0; i < n && i < legacy.length; i++) {
        items[i] = _itemFromTokens(taskDone: legacy[i]);
      }
      return ObjectiveCheckParse(items: items, hadSignal: true);
    }
  }

  final triple = RegExp(
    r'^\s*(\d+)\s*[:.)\-]\s*(KEEP|STALE)\s*\|\s*(RELEVANT|STALE|NA)\s*\|\s*(YES|NO|NA)\b',
    multiLine: true,
    caseSensitive: false,
  );
  var saw = false;
  for (final m in triple.allMatches(text)) {
    final i = int.parse(m.group(1)!) - 1;
    if (i < 0 || i >= n) continue;
    saw = true;
    items[i] = _itemFromTokens(
      objectiveRelevant: m.group(2),
      taskRelevant: m.group(3),
      taskDone: m.group(4),
    );
  }
  if (saw) return ObjectiveCheckParse(items: items, hadSignal: true);

  final numbered = RegExp(
    r'^\s*(\d+)\s*[:.)\-]\s*(YES|NO)\b',
    multiLine: true,
    caseSensitive: false,
  );
  for (final m in numbered.allMatches(text)) {
    final i = int.parse(m.group(1)!) - 1;
    if (i < 0 || i >= n) continue;
    saw = true;
    items[i] = _itemFromTokens(taskDone: m.group(2));
  }
  if (saw) return ObjectiveCheckParse(items: items, hadSignal: true);

  if (n == 1 && text.toUpperCase().contains('YES')) {
    items[0] = const ObjectiveItemVerdict(taskDone: true);
    return ObjectiveCheckParse(items: items, hadSignal: true);
  }
  return ObjectiveCheckParse(items: items, hadSignal: false);
}

/// One bool per batched item — `task_done` only. Missing / unparsed is false.
List<bool> parseObjectiveVerdicts(String text, int itemCount) =>
    parseObjectiveCheck(text, itemCount).items.map((v) => v.taskDone).toList();

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

String buildObjectiveCheckPrompt({
  required String contextText,
  required List<String> itemLines,
  required bool toolsMode,
}) {
  final items = itemLines.join('\n');
  // Completion and relevance use opposite polarity. Do not fold them into
  // one "be generous" preamble — unsure completion is NO; unsure
  // relevance is KEEP.
  const polarity =
      'Completion: Be generous. If the conversation shows a step '
      'accomplished, partially fulfilled, or naturally resolved, answer YES '
      'for task_done. Unsure is NO — never invent a win.\n'
      'Relevance: Be stingy. KEEP a quest or step relevant unless the story '
      'has clearly abandoned, contradicted, or overtaken it. Unsure is KEEP. '
      'Only an explicit NO/STALE retires. Never treat an overtaken quest as '
      'completed — abandonment is not victory.\n\n';
  final closing = toolsMode
      ? 'Evaluate EACH item below. Report by calling the '
            '$kObjectiveVerdictsTool tool with three parallel arrays of the '
            'same length and order as the items: objective_relevant (YES/NO), '
            'task_relevant (YES/NO/NA), task_done (YES/NO/NA). NA for '
            'task_relevant when objective_relevant is NO or the item is '
            'taskless. NA for task_done when objective_relevant is NO. Use '
            'ONLY the tool — no plain-text reply.\n$items'
      : 'Evaluate EACH item below. Reply with ONLY one line per item, in '
            'order, formatted exactly as:\n'
            '1: KEEP|RELEVANT|NO\n'
            '2: STALE|NA|NA\n'
            '3: KEEP|STALE|NA\n'
            'KEEP = relevant, STALE = not relevant. Unsure relevance = KEEP. '
            'Unsure completion = NO. No explanations.\n$items';
  return '${polarity}Recent conversation:\n$contextText\n\n$closing';
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
