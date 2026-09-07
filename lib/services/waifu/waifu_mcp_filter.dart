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

/// MCP servers that clone the coding-agent (Desktop Commander, etc.).
/// Their FS/shell tools bypass the selected Waifu Coder path scope, and their
/// descriptions dump another product's onboarding into the spoken line.
const kWaifuMcpBlockedBareNames = {
  'list_directory',
  'directory_tree',
  'read_file',
  'write_file',
  'edit_block',
  'create_directory',
  'move_file',
  'get_file_info',
  'search_files',
  'start_process',
  'interact_with_process',
  'read_process_output',
  'force_terminate',
  'list_sessions',
  'list_processes',
  'kill_process',
  'list_prompts',
  'get_prompts',
  'give_feedback_to_desktop_commander',
  'get_usage_stats',
  'get_config',
  'set_config_value',
  'start_search',
  'get_more_search_results',
};

String waifuBareMcpName(String name) {
  var n = name.trim();
  final i = n.lastIndexOf('__');
  if (i >= 0 && i < n.length - 2) n = n.substring(i + 2);
  return n.toLowerCase().replaceAll('-', '_');
}

bool waifuMcpNameBlocked(String name) =>
    kWaifuMcpBlockedBareNames.contains(waifuBareMcpName(name));

bool waifuMcpToolBlocked(Map<String, dynamic> tool) {
  final fn = tool['function'];
  if (fn is! Map) return true;
  final name = (fn['name'] ?? '').toString();
  final desc = (fn['description'] ?? '').toString();
  if (waifuMcpNameBlocked(name)) return true;
  final blob = '$name $desc'.toLowerCase();
  return blob.contains('desktop commander');
}

/// Whether a named MCP tool should cross the Plan/Build mutation gate.
///
/// OpenAI-shaped schemas do not retain MCP annotations here. Known lookup
/// verbs fail open as reads; known mutation verbs and every unknown tool fail
/// closed as mutations. `null` means this is not an advertised MCP tool.
bool? waifuMcpMutationHint(String name, List<Map<String, dynamic>> tools) {
  for (final tool in waifuKeepMcpTools(tools)) {
    final fn = tool['function'];
    if (fn is! Map || fn['name']?.toString() != name) continue;
    final bare = waifuBareMcpName(name);
    final mutating = RegExp(
      r'(^|_)(add|apply|commit|copy|create|delete|edit|execute|install|kill|'
      r'merge|move|patch|post|put|remove|rename|restart|run|send|set|start|'
      r'stop|uninstall|update|upload|write)($|_)',
    );
    if (mutating.hasMatch(bare)) return true;
    final readOnly = RegExp(
      r'(^|_)(check|count|describe|fetch|find|get|health|inspect|list|lookup|'
      r'ping|preview|query|read|resolve|search|show|status|validate|view)($|_)',
    );
    return !readOnly.hasMatch(bare);
  }
  return null;
}

final _onboarding = RegExp(
  r'NEW USER ONBOARDING|Desktop Commander|New to Desktop|'
  r'try these prompts|STEP 1: Answer the user',
  caseSensitive: false,
);

/// Drop another product's onboarding if an MCP server stuffed it in a result.
String waifuSanitizeMcpOutput(String raw) {
  if (!_onboarding.hasMatch(raw)) return raw;
  final denied = RegExp(r'^\[DENIED\][^\n]*').firstMatch(raw);
  if (denied != null) {
    return '${denied.group(0)}\n(onboarding from an MCP server was dropped)';
  }
  return '(MCP onboarding text dropped)';
}

String waifuSanitizeMcpDescription(String raw) {
  final cut = RegExp(r'\n?\s*New to\b', caseSensitive: false).firstMatch(raw);
  final t = cut == null ? raw : raw.substring(0, cut.start);
  return t.trim();
}

Map<String, dynamic> waifuSanitizeMcpTool(Map<String, dynamic> tool) {
  final fn = tool['function'];
  if (fn is! Map) return tool;
  final desc = waifuSanitizeMcpDescription(
    (fn['description'] ?? '').toString(),
  );
  return {
    ...tool,
    'function': {...fn, 'description': desc},
  };
}

List<Map<String, dynamic>> waifuKeepMcpTools(List<Map<String, dynamic>> tools) {
  return [
    for (final t in tools)
      if (!waifuMcpToolBlocked(t)) waifuSanitizeMcpTool(t),
  ];
}
