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

import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_mcp_filter.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:front_porch_ai/services/waifu/waifu_webfetch.dart';
import 'package:front_porch_ai/services/waifu/waifu_workflow.dart';

const kWaifuExploreToolNames = {
  kWaifuToolRead,
  kWaifuToolGlob,
  kWaifuToolGrep,
  kWaifuToolSkill,
};

/// Parent → child → grandchild. The deepest worker cannot spawn again.
const kWaifuMaxTaskDepth = 2;

/// Nested Explore (read-only) or General (same selected path scope).
final kWaifuTaskToolSchema = <String, dynamic>{
  'type': 'function',
  'function': {
    'name': kWaifuToolTask,
    'description':
        'Run a nested Explore (read-only) or General agent and wait. '
        'A child may delegate one more bounded task layer; there is no '
        'unbounded agent tree.',
    'parameters': {
      'type': 'object',
      'properties': {
        'subagent': {'type': 'string', 'description': 'explore or general'},
        'prompt': {
          'type': 'string',
          'description': 'What the nested agent should do',
        },
      },
      'required': ['subagent', 'prompt'],
    },
  },
};

bool waifuMcpToolLooksLikeLookup(Map<String, dynamic> tool) {
  final fn = tool['function'];
  if (fn is! Map) return false;
  final blob = '${fn['name']} ${fn['description']}'.toLowerCase();
  return blob.contains('search') ||
      blob.contains('fetch') ||
      blob.contains('browse') ||
      blob.contains('wikipedia');
}

List<Map<String, dynamic>> waifuPrioritizeLookupTools(
  List<Map<String, dynamic>> tools,
) {
  final hit = <Map<String, dynamic>>[];
  final rest = <Map<String, dynamic>>[];
  for (final t in tools) {
    (waifuMcpToolLooksLikeLookup(t) ? hit : rest).add(t);
  }
  return [...hit, ...rest];
}

String waifuMcpToolsLine(List<Map<String, dynamic>> tools) {
  final lookup = <String>[];
  var other = 0;
  for (final t in tools) {
    final n = ((t['function'] as Map?)?['name'] ?? '').toString();
    if (n.isEmpty) continue;
    if (waifuMcpToolLooksLikeLookup(t)) {
      lookup.add(n);
    } else {
      other++;
    }
  }
  if (lookup.isEmpty && other == 0) return '';
  final buf = StringBuffer();
  if (lookup.isNotEmpty) {
    buf.write(
      'MCP search/fetch tools (prefer these for unknown versions): '
      '${lookup.join(', ')}.',
    );
  }
  if (other > 0) {
    if (buf.isNotEmpty) buf.write(' ');
    buf.write('$other other MCP tools are also available by name.');
  }
  return buf.toString();
}

String? _toolName(Map<String, dynamic> tool) =>
    (tool['function'] as Map?)?['name']?.toString();

List<Map<String, dynamic>> waifuAdvertisedTools({
  required bool exploreOnly,
  required bool includeWebSearch,
  required bool mcpOptIn,
  required List<Map<String, dynamic>> mcpTools,
  required bool includeTask,
  bool? includeWorkflow,
  WaifuPathMode pathMode = WaifuPathMode.folderJail,
  WaifuMode mode = WaifuMode.build,
}) {
  final plan = mode == WaifuMode.plan && !exploreOnly;
  final workflow = plan ? false : (includeWorkflow ?? includeTask);
  Iterable<Map<String, dynamic>> fileTools = pathMode == WaifuPathMode.wholeDisk
      ? kWaifuWholeDiskFileTools
      : kWaifuFileTools;
  if (exploreOnly) {
    fileTools = kWaifuFileTools.where((t) {
      final n = _toolName(t);
      return kWaifuExploreToolNames.contains(n);
    });
  } else if (plan) {
    fileTools = waifuPlanAdvertisedTools(kWaifuFileTools);
  }
  final taken = <String>{
    for (final t in fileTools)
      if (_toolName(t) != null) _toolName(t)!,
    kWaifuToolWebFetch,
    if (includeWebSearch) kWaifuToolWebSearch,
    if (includeTask) kWaifuToolTask,
    if (workflow) kWaifuToolWorkflow,
  };
  final mcp = [
    for (final t in waifuKeepMcpTools(mcpTools))
      if (!taken.contains(_toolName(t))) t,
  ];
  return [
    ...fileTools,
    if (!exploreOnly) kWaifuWebFetchToolSchema,
    if (!exploreOnly && includeWebSearch) kWaifuWebSearchToolSchema,
    if (!exploreOnly && mcpOptIn) ...waifuPrioritizeLookupTools(mcp),
    if (includeTask) kWaifuTaskToolSchema,
    if (workflow) kWaifuWorkflowToolSchema,
  ];
}

String? waifuSubagentKind(String name, Map<String, dynamic> args) {
  switch (name.trim().toLowerCase()) {
    case 'explore':
      return 'explore';
    case 'general':
      return 'general';
  }
  final v = (args['subagent'] ?? args['type'] ?? args['agent'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (v == 'explore' || v == 'general') return v;
  return null;
}
