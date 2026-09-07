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
import 'dart:io';

import 'package:front_porch_ai/services/desk/desk_brand.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';
import 'package:path/path.dart' as p;

const kDeskWorkflowDir = '$kWaifuDotDir/workflows';
const kDeskLegacyWorkflowDir = '$kWaifuLegacyDotDir/workflows';
const kDeskWorkflowMaxSteps = 8;
const kDeskWorkflowMaxParallel = 4;
const kDeskWorkflowMaxAgents = 12;
const kDeskWorkflowMaxBytes = 65536;

/// JSON pipelines, not Grok's Rhai dialect.
final kDeskWorkflowToolSchema = <String, dynamic>{
  'type': 'function',
  'function': {
    'name': kDeskToolWorkflow,
    'description':
        'List or run a JSON workflow from $kDeskWorkflowDir. '
        'Omit name to list. Each step is one nested explore/general agent, '
        'or a parallel list. Nested agents cannot spawn children. '
        'Not a Rhai script.',
    'parameters': {
      'type': 'object',
      'properties': {
        'name': {
          'type': 'string',
          'description': 'Saved workflow name, without .json',
        },
        'script': {
          'type': 'string',
          'description': 'Inline JSON workflow (name, description, steps)',
        },
      },
    },
  },
};

class DeskWorkflowAgent {
  const DeskWorkflowAgent({required this.subagent, required this.prompt});

  final String subagent;
  final String prompt;
}

class DeskWorkflowStep {
  const DeskWorkflowStep({required this.agents});

  final List<DeskWorkflowAgent> agents;
  bool get isParallel => agents.length > 1;
}

class DeskWorkflow {
  const DeskWorkflow({
    required this.name,
    required this.description,
    required this.steps,
  });

  final String name;
  final String description;
  final List<DeskWorkflowStep> steps;

  int get agentCount => steps.fold(0, (n, s) => n + s.agents.length);
}

class DeskWorkflowParse {
  const DeskWorkflowParse.ok(this.workflow) : error = null;
  const DeskWorkflowParse.fail(this.error) : workflow = null;

  final DeskWorkflow? workflow;
  final String? error;
}

class DeskWorkflowInfo {
  const DeskWorkflowInfo({required this.name, required this.description});

  final String name;
  final String description;
}

bool deskWorkflowNameOk(String name) {
  final t = name.trim();
  if (t.isEmpty || t.contains('..') || t.contains('/') || t.contains('\\')) {
    return false;
  }
  return RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$').hasMatch(t);
}

String deskFillPrev(String prompt, String prev) =>
    prompt.replaceAll('{{prev}}', prev);

bool deskWorkflowWantsList(Map<String, dynamic> args) {
  final name = args['name']?.toString().trim() ?? '';
  final script = args['script'];
  if (name.isNotEmpty) return false;
  if (script == null) return true;
  if (script is String) return script.trim().isEmpty;
  return false;
}

String deskWorkflowListing(List<DeskWorkflowInfo> items) {
  if (items.isEmpty) {
    return 'No saved workflows. Drop a JSON file in $kDeskWorkflowDir '
        '(name, description, steps). Each step is '
        '{subagent: explore|general, prompt} or {parallel: [...]}. '
        '{{prev}} is the previous step output. Not a Rhai script.';
  }
  final buf = StringBuffer('Saved workflows:\n');
  for (final i in items) {
    buf.writeln(
      i.description.isEmpty ? '  ${i.name}' : '  ${i.name} — ${i.description}',
    );
  }
  return buf.toString().trimRight();
}

String? deskWorkflowRhaiReject(String name, Object? script) {
  final n = name.trim().toLowerCase();
  if (n.endsWith('.rhai')) {
    return 'workflow: Waifu Coder uses JSON pipelines in '
        '$kDeskWorkflowDir, not Rhai scripts';
  }
  if (script is String &&
      script.contains('let meta') &&
      script.contains('#{')) {
    return 'workflow: Rhai scripts are not run. Use JSON steps.';
  }
  return null;
}

DeskWorkflowParse parseDeskWorkflow(
  Object? raw, {
  String fallbackName = 'inline',
}) {
  if (raw is! Map) {
    return const DeskWorkflowParse.fail('workflow: JSON object required');
  }
  final name = (raw['name']?.toString() ?? fallbackName).trim();
  if (!deskWorkflowNameOk(name)) {
    return const DeskWorkflowParse.fail(
      'workflow: name must be lowercase letters, digits, _ or -',
    );
  }
  final description = raw['description']?.toString().trim() ?? '';
  final stepsRaw = raw['steps'];
  if (stepsRaw is! List || stepsRaw.isEmpty) {
    return const DeskWorkflowParse.fail(
      'workflow: steps must be a non-empty list',
    );
  }
  if (stepsRaw.length > kDeskWorkflowMaxSteps) {
    return DeskWorkflowParse.fail(
      'workflow: at most $kDeskWorkflowMaxSteps steps',
    );
  }
  final steps = <DeskWorkflowStep>[];
  var agents = 0;
  for (final s in stepsRaw) {
    final step = _parseStep(s);
    if (step.error != null) {
      return DeskWorkflowParse.fail(step.error!);
    }
    agents += step.step!.agents.length;
    if (agents > kDeskWorkflowMaxAgents) {
      return DeskWorkflowParse.fail(
        'workflow: at most $kDeskWorkflowMaxAgents nested agents',
      );
    }
    steps.add(step.step!);
  }
  return DeskWorkflowParse.ok(
    DeskWorkflow(name: name, description: description, steps: steps),
  );
}

class _StepParse {
  const _StepParse.ok(this.step) : error = null;
  const _StepParse.fail(this.error) : step = null;
  final DeskWorkflowStep? step;
  final String? error;
}

_StepParse _parseStep(Object? raw) {
  if (raw is! Map) {
    return const _StepParse.fail('workflow: each step must be an object');
  }
  final parallel = raw['parallel'];
  if (parallel != null) {
    if (parallel is! List || parallel.isEmpty) {
      return const _StepParse.fail(
        'workflow: parallel must be a non-empty list',
      );
    }
    if (parallel.length > kDeskWorkflowMaxParallel) {
      return _StepParse.fail(
        'workflow: at most $kDeskWorkflowMaxParallel parallel agents',
      );
    }
    final agents = <DeskWorkflowAgent>[];
    for (final e in parallel) {
      final a = _parseAgent(e);
      if (a.error != null) return _StepParse.fail(a.error!);
      agents.add(a.agent!);
    }
    return _StepParse.ok(DeskWorkflowStep(agents: agents));
  }
  final a = _parseAgent(raw);
  if (a.error != null) return _StepParse.fail(a.error!);
  return _StepParse.ok(DeskWorkflowStep(agents: [a.agent!]));
}

class _AgentParse {
  const _AgentParse.ok(this.agent) : error = null;
  const _AgentParse.fail(this.error) : agent = null;
  final DeskWorkflowAgent? agent;
  final String? error;
}

_AgentParse _parseAgent(Object? raw) {
  if (raw is! Map) {
    return const _AgentParse.fail('workflow: agent must be an object');
  }
  var kind = (raw['subagent'] ?? raw['agent'] ?? 'explore').toString().trim();
  kind = kind.toLowerCase();
  if (kind != 'explore' && kind != 'general') {
    return const _AgentParse.fail(
      'workflow: subagent must be explore or general',
    );
  }
  final prompt = raw['prompt']?.toString() ?? '';
  if (prompt.trim().isEmpty) {
    return const _AgentParse.fail('workflow: prompt is empty');
  }
  return _AgentParse.ok(DeskWorkflowAgent(subagent: kind, prompt: prompt));
}

Directory deskWorkflowDirectory(String folderRoot) =>
    Directory(p.join(folderRoot, kDeskWorkflowDir));

List<Directory> deskWorkflowDirectories(String folderRoot) => [
  deskWorkflowDirectory(folderRoot),
  Directory(p.join(folderRoot, kDeskLegacyWorkflowDir)),
];

Future<List<DeskWorkflowInfo>> deskListWorkflows(String folderRoot) async {
  final seen = <String>{};
  final out = <DeskWorkflowInfo>[];
  for (final dir in deskWorkflowDirectories(folderRoot)) {
    if (!await dir.exists()) continue;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      if (p.extension(e.path).toLowerCase() != '.json') continue;
      final stem = p.basenameWithoutExtension(e.path);
      if (!deskWorkflowNameOk(stem) || !seen.add(stem)) continue;
      try {
        final parsed = parseDeskWorkflow(
          jsonDecode(await e.readAsString()),
          fallbackName: stem,
        );
        final wf = parsed.workflow;
        if (wf == null) continue;
        out.add(DeskWorkflowInfo(name: wf.name, description: wf.description));
      } catch (_) {}
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

Future<DeskWorkflowParse> deskLoadWorkflow(
  String folderRoot,
  String name,
) async {
  final stem = name.trim().toLowerCase().replaceAll(RegExp(r'\.json$'), '');
  final rhai = deskWorkflowRhaiReject(name, null);
  if (rhai != null) return DeskWorkflowParse.fail(rhai);
  if (!deskWorkflowNameOk(stem)) {
    return const DeskWorkflowParse.fail('workflow: bad name');
  }
  var file = File(p.join(folderRoot, kDeskWorkflowDir, '$stem.json'));
  if (!await file.exists()) {
    file = File(p.join(folderRoot, kDeskLegacyWorkflowDir, '$stem.json'));
  }
  if (!await file.exists()) {
    return DeskWorkflowParse.fail('workflow: $stem.json not found');
  }
  final bytes = await file.length();
  if (bytes > kDeskWorkflowMaxBytes) {
    return const DeskWorkflowParse.fail('workflow: file too large');
  }
  try {
    return parseDeskWorkflow(
      jsonDecode(await file.readAsString()),
      fallbackName: stem,
    );
  } catch (_) {
    return const DeskWorkflowParse.fail('workflow: invalid JSON');
  }
}

Future<DeskWorkflowParse> deskWorkflowFromArgs(
  String folderRoot,
  Map<String, dynamic> args,
) async {
  final name = args['name']?.toString().trim() ?? '';
  final script = args['script'];
  final rhai = deskWorkflowRhaiReject(name, script);
  if (rhai != null) return DeskWorkflowParse.fail(rhai);
  if (name.isNotEmpty) return deskLoadWorkflow(folderRoot, name);
  if (script is Map) {
    return parseDeskWorkflow(script, fallbackName: 'inline');
  }
  if (script is String && script.trim().isNotEmpty) {
    try {
      return parseDeskWorkflow(jsonDecode(script), fallbackName: 'inline');
    } catch (_) {
      return const DeskWorkflowParse.fail('workflow: script is not JSON');
    }
  }
  return const DeskWorkflowParse.fail('workflow: name or script required');
}
