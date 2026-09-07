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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/services.dart';

({List<Map<String, dynamic>> tools, WaifuMcpCallFn? call}) waifuMcpBind(
  BuildContext context,
) {
  try {
    final chat = Provider.of<ChatService>(context, listen: false);
    final snaps = chat.mcpHub.snapshots();
    final enabled = {
      for (final s in snaps)
        if (s.config.enabledGlobal) s.config.id,
    };
    final catalog = buildMcpCatalog(
      inProcess: const [],
      servers: snaps,
      enabledForChat: enabled,
    );
    return (
      tools: waifuKeepMcpTools(catalog.toOpenAiTools()),
      call: (name, args) async {
        CatalogTool? tool;
        for (final t in catalog.tools) {
          if (t.name == name) {
            tool = t;
            break;
          }
        }
        final serverId = tool?.serverId;
        if (serverId == null) {
          return WaifuToolResult.error('mcp: unknown tool $name');
        }
        final result = await chat.mcpHub.callTool(
          serverId: serverId,
          toolName: name,
          arguments: args,
          enabledForChat: enabled,
        );
        return WaifuToolResult(
          ok: result.ok && !result.isError,
          output: waifuSanitizeMcpOutput(result.text),
        );
      },
    );
  } on ProviderNotFoundException {
    return (tools: const <Map<String, dynamic>>[], call: null);
  }
}

/// Wikipedia/Tavily via the same client character chat uses. Each waifu
/// tool call resets the per-send HTTP cap so a turn can look up more
/// than once (Flutter version AND a package).
WaifuWebSearchFn? waifuWebSearchBind(BuildContext context) {
  try {
    final chat = Provider.of<ChatService>(context, listen: false);
    return (q) async {
      chat.webSearchService.beginUserSend();
      final r = await chat.webSearchService.lookup(q);
      return r.snippet;
    };
  } on ProviderNotFoundException {
    return null;
  }
}
