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

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:path/path.dart' as p;

const kWaifuWorkflowDir = '$kWaifuDotDir/workflows';
const kWaifuLegacyWorkflowDir = '$kWaifuLegacyDotDir/workflows';
const kWaifuWorkflowMaxSteps = 8;
const kWaifuWorkflowMaxParallel = 4;
const kWaifuWorkflowMaxAgents = 12;
const kWaifuWorkflowMaxBytes = 65536;

const kWaifuBuiltinRunPlanStep = 'run-plan-step';
const kWaifuBuiltinRunPlanStepDescription =
    'Work the next pending accepted-plan step, then verify.';

WaifuWorkflow waifuBuiltinRunPlanStepWorkflow() => const WaifuWorkflow(
  name: kWaifuBuiltinRunPlanStep,
  description: kWaifuBuiltinRunPlanStepDescription,
  steps: [
    WaifuWorkflowStep(
      agents: [
        WaifuWorkflowAgent(
          subagent: 'general',
          prompt:
              'Execute the next pending step of the accepted plan. '
              'Read the listed files, then put the change on disk with '
              'write, edit, or apply_patch. Do not mark the step done yet.',
        ),
      ],
    ),
    WaifuWorkflowStep(
      agents: [
        WaifuWorkflowAgent(
          subagent: 'general',
          prompt:
              'Verify the change from {{prev}}. Re-read every touched path '
              'AND run the step verify command written on the plan step. '
              'If the step has no verify field, run this repo’s native '
              'check (whatever the project already uses — cargo test, '
              'npm test, pytest, go test, dart test, and the rest). '
              'Do not assume a host-app stack. Bash stays hard-deny '
              'protected. Do not claim the step done without both receipts.',
        ),
      ],
    ),
  ],
);

/// JSON pipelines, not Grok's Rhai dialect.
final kWaifuWorkflowToolSchema = <String, dynamic>{
  'type': 'function',
  'function': {
    'name': kWaifuToolWorkflow,
    'description':
        'List or run a JSON workflow from $kWaifuWorkflowDir. '
        'Omit name to list. Each step is one nested explore/general agent, '
        'or a parallel list. A step may delegate one more bounded task layer. '
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

class WaifuWorkflowAgent {
  const WaifuWorkflowAgent({required this.subagent, required this.prompt});

  final String subagent;
  final String prompt;
}

class WaifuWorkflowStep {
  const WaifuWorkflowStep({required this.agents});

  final List<WaifuWorkflowAgent> agents;
  bool get isParallel => agents.length > 1;
}

class WaifuWorkflow {
  const WaifuWorkflow({
    required this.name,
    required this.description,
    required this.steps,
  });

  final String name;
  final String description;
  final List<WaifuWorkflowStep> steps;

  int get agentCount => steps.fold(0, (n, s) => n + s.agents.length);
}

class WaifuWorkflowParse {
  const WaifuWorkflowParse.ok(this.workflow) : error = null;
  const WaifuWorkflowParse.fail(this.error) : workflow = null;

  final WaifuWorkflow? workflow;
  final String? error;
}

class WaifuWorkflowInfo {
  const WaifuWorkflowInfo({required this.name, required this.description});

  final String name;
  final String description;
}

bool waifuWorkflowNameOk(String name) {
  final t = name.trim();
  if (t.isEmpty || t.contains('..') || t.contains('/') || t.contains('\\')) {
    return false;
  }
  return RegExp(r'^[a-z0-9][a-z0-9_-]{0,62}$').hasMatch(t);
}

String waifuFillPrev(String prompt, String prev) =>
    prompt.replaceAll('{{prev}}', prev);

bool waifuWorkflowWantsList(Map<String, dynamic> args) {
  final name = args['name']?.toString().trim() ?? '';
  final script = args['script'];
  if (name.isNotEmpty) return false;
  if (script == null) return true;
  if (script is String) return script.trim().isEmpty;
  return false;
}

String waifuWorkflowListing(List<WaifuWorkflowInfo> items) {
  if (items.isEmpty) {
    return 'No saved workflows. Drop a JSON file in $kWaifuWorkflowDir '
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

String? waifuWorkflowRhaiReject(String name, Object? script) {
  final n = name.trim().toLowerCase();
  if (n.endsWith('.rhai')) {
    return 'workflow: Waifu Coder uses JSON pipelines in '
        '$kWaifuWorkflowDir, not Rhai scripts';
  }
  if (script is String &&
      script.contains('let meta') &&
      script.contains('#{')) {
    return 'workflow: Rhai scripts are not run. Use JSON steps.';
  }
  return null;
}

WaifuWorkflowParse parseWaifuWorkflow(
  Object? raw, {
  String fallbackName = 'inline',
}) {
  if (raw is! Map) {
    return const WaifuWorkflowParse.fail('workflow: JSON object required');
  }
  final name = (raw['name']?.toString() ?? fallbackName).trim();
  if (!waifuWorkflowNameOk(name)) {
    return const WaifuWorkflowParse.fail(
      'workflow: name must be lowercase letters, digits, _ or -',
    );
  }
  final description = raw['description']?.toString().trim() ?? '';
  final stepsRaw = raw['steps'];
  if (stepsRaw is! List || stepsRaw.isEmpty) {
    return const WaifuWorkflowParse.fail(
      'workflow: steps must be a non-empty list',
    );
  }
  if (stepsRaw.length > kWaifuWorkflowMaxSteps) {
    return WaifuWorkflowParse.fail(
      'workflow: at most $kWaifuWorkflowMaxSteps steps',
    );
  }
  final steps = <WaifuWorkflowStep>[];
  var agents = 0;
  for (final s in stepsRaw) {
    final step = _parseStep(s);
    if (step.error != null) {
      return WaifuWorkflowParse.fail(step.error!);
    }
    agents += step.step!.agents.length;
    if (agents > kWaifuWorkflowMaxAgents) {
      return WaifuWorkflowParse.fail(
        'workflow: at most $kWaifuWorkflowMaxAgents nested agents',
      );
    }
    steps.add(step.step!);
  }
  return WaifuWorkflowParse.ok(
    WaifuWorkflow(name: name, description: description, steps: steps),
  );
}

class _StepParse {
  const _StepParse.ok(this.step) : error = null;
  const _StepParse.fail(this.error) : step = null;
  final WaifuWorkflowStep? step;
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
    if (parallel.length > kWaifuWorkflowMaxParallel) {
      return _StepParse.fail(
        'workflow: at most $kWaifuWorkflowMaxParallel parallel agents',
      );
    }
    final agents = <WaifuWorkflowAgent>[];
    for (final e in parallel) {
      final a = _parseAgent(e);
      if (a.error != null) return _StepParse.fail(a.error!);
      agents.add(a.agent!);
    }
    return _StepParse.ok(WaifuWorkflowStep(agents: agents));
  }
  final a = _parseAgent(raw);
  if (a.error != null) return _StepParse.fail(a.error!);
  return _StepParse.ok(WaifuWorkflowStep(agents: [a.agent!]));
}

class _AgentParse {
  const _AgentParse.ok(this.agent) : error = null;
  const _AgentParse.fail(this.error) : agent = null;
  final WaifuWorkflowAgent? agent;
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
  return _AgentParse.ok(WaifuWorkflowAgent(subagent: kind, prompt: prompt));
}

Directory waifuWorkflowDirectory(String folderRoot) =>
    Directory(p.join(folderRoot, kWaifuWorkflowDir));

List<Directory> waifuWorkflowDirectories(String folderRoot) => [
  waifuWorkflowDirectory(folderRoot),
  Directory(p.join(folderRoot, kWaifuLegacyWorkflowDir)),
];

Future<List<WaifuWorkflowInfo>> waifuListWorkflows(String folderRoot) async {
  final seen = <String>{kWaifuBuiltinRunPlanStep};
  final out = <WaifuWorkflowInfo>[
    const WaifuWorkflowInfo(
      name: kWaifuBuiltinRunPlanStep,
      description: kWaifuBuiltinRunPlanStepDescription,
    ),
  ];
  for (final dir in waifuWorkflowDirectories(folderRoot)) {
    if (!await dir.exists()) continue;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      if (p.extension(e.path).toLowerCase() != '.json') continue;
      final stem = p.basenameWithoutExtension(e.path);
      if (!waifuWorkflowNameOk(stem) || !seen.add(stem)) continue;
      try {
        final parsed = parseWaifuWorkflow(
          jsonDecode(await e.readAsString()),
          fallbackName: stem,
        );
        final wf = parsed.workflow;
        if (wf == null) continue;
        out.add(WaifuWorkflowInfo(name: wf.name, description: wf.description));
      } catch (_) {}
    }
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

Future<WaifuWorkflowParse> waifuLoadWorkflow(
  String folderRoot,
  String name,
) async {
  final stem = name.trim().toLowerCase().replaceAll(RegExp(r'\.json$'), '');
  final rhai = waifuWorkflowRhaiReject(name, null);
  if (rhai != null) return WaifuWorkflowParse.fail(rhai);
  if (stem == kWaifuBuiltinRunPlanStep) {
    return WaifuWorkflowParse.ok(waifuBuiltinRunPlanStepWorkflow());
  }
  if (!waifuWorkflowNameOk(stem)) {
    return const WaifuWorkflowParse.fail('workflow: bad name');
  }
  var file = File(p.join(folderRoot, kWaifuWorkflowDir, '$stem.json'));
  if (!await file.exists()) {
    file = File(p.join(folderRoot, kWaifuLegacyWorkflowDir, '$stem.json'));
  }
  if (!await file.exists()) {
    return WaifuWorkflowParse.fail('workflow: $stem.json not found');
  }
  final bytes = await file.length();
  if (bytes > kWaifuWorkflowMaxBytes) {
    return const WaifuWorkflowParse.fail('workflow: file too large');
  }
  try {
    return parseWaifuWorkflow(
      jsonDecode(await file.readAsString()),
      fallbackName: stem,
    );
  } catch (_) {
    return const WaifuWorkflowParse.fail('workflow: invalid JSON');
  }
}

Future<WaifuWorkflowParse> waifuWorkflowFromArgs(
  String folderRoot,
  Map<String, dynamic> args,
) async {
  final name = args['name']?.toString().trim() ?? '';
  final script = args['script'];
  final rhai = waifuWorkflowRhaiReject(name, script);
  if (rhai != null) return WaifuWorkflowParse.fail(rhai);
  if (name.isNotEmpty) return waifuLoadWorkflow(folderRoot, name);
  if (script is Map) {
    return parseWaifuWorkflow(script, fallbackName: 'inline');
  }
  if (script is String && script.trim().isNotEmpty) {
    try {
      return parseWaifuWorkflow(jsonDecode(script), fallbackName: 'inline');
    } catch (_) {
      return const WaifuWorkflowParse.fail('workflow: script is not JSON');
    }
  }
  return const WaifuWorkflowParse.fail('workflow: name or script required');
}
