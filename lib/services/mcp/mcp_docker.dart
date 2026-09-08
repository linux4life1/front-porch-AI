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

import 'package:front_porch_ai/services/mcp/mcp_hub.dart';
import 'package:front_porch_ai/services/mcp/mcp_local_probe.dart';
import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/mcp/mcp_settings.dart';

/// One-tap Docker Desktop MCP. Prefers an already-listening HTTP gateway
/// (no extra process), otherwise spawns `docker mcp gateway run` on stdio.
class McpDockerEasy {
  static Future<String> connect({
    required McpSettings settings,
    required McpHub hub,
    McpLocalProbe? probe,
  }) async {
    for (final existing in settings.servers) {
      if (!mcpIsDockerConfig(existing)) continue;
      debugPrint(
        '[MCP] docker-easy reuse id=${existing.id} '
        'transport=${existing.transport.name}',
      );
      return hub.check(existing.id);
    }

    final found = await (probe ?? McpLocalProbe()).findDocker();
    if (found.found && found.url != null) {
      debugPrint('[MCP] docker-easy HTTP gateway at ${found.url}');
      final server = await settings.addServer(
        displayName: 'Docker',
        url: found.url!,
      );
      final line = await hub.check(server.id);
      if (!line.startsWith('Connected')) {
        await settings.removeServer(server.id);
        await hub.onServerRemoved(server.id);
      }
      return line;
    }

    debugPrint('[MCP] docker-easy spawn stdio $kMcpDockerStdioCommand');
    final server = await settings.addServer(
      displayName: 'Docker',
      url: mcpStdioCommandLine(kMcpDockerStdioCommand, kMcpDockerStdioArgs),
      transport: McpTransportKind.stdio,
      command: kMcpDockerStdioCommand,
      args: kMcpDockerStdioArgs,
    );
    final line = await hub.check(server.id);
    if (!line.startsWith('Connected')) {
      await settings.removeServer(server.id);
      await hub.onServerRemoved(server.id);
    }
    return line;
  }
}
