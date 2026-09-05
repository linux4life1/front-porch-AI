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

import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/chat/web_search_service.dart';
import 'package:front_porch_ai/services/chat/web_search_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/mcp/mcp_catalog.dart';
import 'package:front_porch_ai/services/mcp/mcp_hub.dart';
import 'package:front_porch_ai/services/mcp/mcp_models.dart';

/// Outcome of the one tools round-trip over the unified catalog.
class CatalogRound {
  const CatalogRound({this.injection, this.searchReceipt, this.mcpReceipt});

  final String? injection;
  final Map<String, dynamic>? searchReceipt;
  final Map<String, dynamic>? mcpReceipt;
}

/// One `generateWithTools` with the flat catalog. Dispatches by source:
/// in-process `web_search` vs MCP `tools/call`. A name that is not in the
/// advertised catalog is a no-op. Cap: first advertised call only.
Future<CatalogRound> runCatalogRound({
  required LLMService llm,
  required GenerationParams params,
  required CatalogBuildResult catalog,
  required WebSearchService search,
  required McpHub hub,
  required Set<String> enabledForChat,
}) async {
  final tools = catalog.toOpenAiTools();
  debugPrint(
    '[MCP] catalog round backend=${llm.backendName} '
    'tools=${[for (final t in catalog.tools) t.name]} '
    'reasoning=${params.reasoningEnabled}',
  );
  LlmToolResponse? resp;
  try {
    resp = await llm.generateWithTools(params, tools);
  } catch (e) {
    debugPrint('[MCP] generateWithTools THREW: $e');
    return const CatalogRound();
  }
  if (resp == null) {
    debugPrint('[MCP] generateWithTools returned null (tools unsupported)');
    return const CatalogRound();
  }
  debugPrint(
    '[MCP] think calls=${resp.calls.map((c) => c.name).toList()} '
    'textChars=${resp.text.length}',
  );

  LlmToolCall? call;
  CatalogTool? entry;
  for (final c in resp.calls) {
    final found = catalog.lookup(c.name);
    if (found != null) {
      call = c;
      entry = found;
      break;
    }
    debugPrint(
      '[MCP] ignoring unadvertised call name=${c.name} (no-op, not in catalog)',
    );
  }
  if (call == null || entry == null) {
    debugPrint(
      '[MCP] no advertised tool call — will stream in-character reply',
    );
    return const CatalogRound();
  }

  if (entry.source == McpToolSource.inProcess &&
      entry.name == kWebSearchToolName) {
    return _dispatchSearch(call, search);
  }
  if (entry.source == McpToolSource.mcp && entry.serverId != null) {
    return _dispatchMcp(
      call: call,
      entry: entry,
      hub: hub,
      enabledForChat: enabledForChat,
    );
  }
  debugPrint('[MCP] no-op: catalog entry ${entry.name} has no dispatcher');
  return const CatalogRound();
}

Future<CatalogRound> _dispatchSearch(
  LlmToolCall call,
  WebSearchService search,
) async {
  final query = WebSearchService.prepareQuery(
    call.arguments['query']?.toString() ?? '',
  );
  debugPrint('[MCP] dispatch in-process web_search query="$query"');
  final outcome = await search.lookup(query);
  final injection = outcome.ok
      ? SearchInjection.resultFragment(outcome.snippet)
      : SearchInjection.emptyResultFragment(outcome.query);
  return CatalogRound(
    injection: injection,
    searchReceipt: {
      'query': outcome.query,
      'ok': outcome.ok,
      'cached': outcome.fromCache,
    },
  );
}

Future<CatalogRound> _dispatchMcp({
  required LlmToolCall call,
  required CatalogTool entry,
  required McpHub hub,
  required Set<String> enabledForChat,
}) async {
  debugPrint(
    '[MCP] dispatch MCP tool=${entry.name} server="${entry.serverDisplayName}"',
  );
  final result = await hub.callTool(
    serverId: entry.serverId!,
    toolName: entry.name,
    arguments: call.arguments,
    enabledForChat: enabledForChat,
  );
  final injection = result.ok
      ? McpInjection.resultFragment(result.text)
      : McpInjection.emptyResultFragment;
  return CatalogRound(
    injection: injection,
    mcpReceipt: {
      'server': entry.serverDisplayName ?? '',
      'tool': entry.name,
      'ok': result.ok,
    },
  );
}
