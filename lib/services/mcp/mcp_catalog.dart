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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/mcp/mcp_models.dart';

/// Unified flat catalog: in-process tools plus tools from MCP servers
/// enabled for this chat. Name collisions warn; first-connected wins;
/// the other is omitted. No auto-prefixing.
class CatalogBuildResult {
  const CatalogBuildResult({required this.tools, required this.exclusions});

  final List<CatalogTool> tools;
  final List<CatalogExclusion> exclusions;

  List<Map<String, dynamic>> toOpenAiTools() => [
    for (final t in tools) t.toOpenAiTool(),
  ];

  CatalogTool? lookup(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  bool get isEmpty => tools.isEmpty;
  bool get hasSearch => tools.any((t) => t.name == kWebSearchToolName);
  bool get hasMcp => tools.any((t) => t.source == McpToolSource.mcp);
}

/// In-process `web_search` as a catalog entry. Source is never shown to the model.
CatalogTool inProcessWebSearchTool() {
  final fn = kWebSearchTools.first['function'] as Map<String, dynamic>;
  return CatalogTool(
    name: kWebSearchToolName,
    description: fn['description']?.toString() ?? '',
    parameters: Map<String, dynamic>.from(fn['parameters'] as Map),
    source: McpToolSource.inProcess,
  );
}

/// Merge in-process tools with enabled, successfully-listed MCP servers.
///
/// Filter order (security boundary):
/// 1. Server must be enabled for this chat.
/// 2. Last `tools/list` must have succeeded (connected).
/// 3. Name already taken → omit the later server's tool (first-connected wins).
///    In-process tools always occupy the name first.
CatalogBuildResult buildMcpCatalog({
  required List<CatalogTool> inProcess,
  required List<McpServerSnapshot> servers,
  required Set<String> enabledForChat,
}) {
  final tools = <CatalogTool>[];
  final exclusions = <CatalogExclusion>[];
  final taken = <String, String>{}; // name → owner label

  for (final t in inProcess) {
    tools.add(t);
    taken[t.name] = 'in-process';
    debugPrint('[MCP] catalog include ${t.name} (in-process)');
  }

  final ordered = [...servers]
    ..sort((a, b) => a.connectOrder.compareTo(b.connectOrder));
  for (final snap in ordered) {
    final cfg = snap.config;
    if (!enabledForChat.contains(cfg.id)) {
      debugPrint(
        '[MCP] catalog exclude server "${cfg.displayName}" '
        '(${cfg.id}): not enabled for this chat',
      );
      continue;
    }
    if (snap.status != McpConnectionStatus.connected) {
      debugPrint(
        '[MCP] catalog exclude server "${cfg.displayName}": '
        'status=${snap.status.name} error=${snap.lastError ?? "none"} '
        '(tools/list did not succeed)',
      );
      continue;
    }
    for (final def in snap.tools) {
      if (def.name.isEmpty) {
        debugPrint(
          '[MCP] catalog exclude unnamed tool from "${cfg.displayName}"',
        );
        continue;
      }
      final owner = taken[def.name];
      if (owner != null) {
        final reason =
            'name collision with $owner; first-connected wins, omitted';
        exclusions.add(
          CatalogExclusion(
            toolName: def.name,
            serverId: cfg.id,
            serverDisplayName: cfg.displayName,
            reason: reason,
          ),
        );
        debugPrint(
          '[MCP] catalog exclude ${def.name} from "${cfg.displayName}": $reason',
        );
        continue;
      }
      taken[def.name] = cfg.displayName;
      tools.add(
        CatalogTool(
          name: def.name,
          description: def.description,
          parameters: _schemaToParameters(def.inputSchema),
          source: McpToolSource.mcp,
          serverId: cfg.id,
          serverDisplayName: cfg.displayName,
        ),
      );
      debugPrint(
        '[MCP] catalog include ${def.name} from "${cfg.displayName}" '
        '(chat-enabled, tools/list ok)',
      );
    }
  }

  debugPrint(
    '[MCP] catalog built: ${tools.length} tool(s), '
    '${exclusions.length} excluded; names=${[for (final t in tools) t.name]}',
  );
  return CatalogBuildResult(tools: tools, exclusions: exclusions);
}

Map<String, dynamic> _schemaToParameters(Map<String, dynamic> schema) {
  if (schema.isEmpty) {
    return const {'type': 'object', 'properties': <String, dynamic>{}};
  }
  final type = schema['type']?.toString() ?? 'object';
  if (type != 'object') {
    return {
      'type': 'object',
      'properties': {'value': schema},
    };
  }
  return Map<String, dynamic>.from(schema);
}

/// Advertise MCP tools this turn? Continue, autonomous, guests, and
/// tools-unsupported backends fail closed. Regen, group follow-ups, and
/// a direct user send all may call. Empty enable set → off.
bool shouldAdvertiseMcp({
  required Iterable<String> enabledServerIds,
  required bool continueMode,
  required bool toolsUnsupported,
  bool autonomousMode = false,
  bool guestTurn = false,
}) {
  return enabledServerIds.isNotEmpty &&
      !continueMode &&
      !autonomousMode &&
      !guestTurn &&
      !toolsUnsupported;
}
