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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_mcp_bind.dart';

/// Snapshot of MCP tools + dispatch. Re-read each generate; do not freeze.
typedef WaifuMcpOf =
    ({List<Map<String, dynamic>> tools, WaifuMcpCallFn? call}) Function();

/// Data-dir store for this page. Injected in tests; live from StorageService.
WaifuStore? waifuStoreForContext(BuildContext context, {WaifuStore? injected}) {
  if (injected != null) return injected;
  try {
    final storage = Provider.of<StorageService>(context, listen: false);
    final root = storage.rootPath;
    if (root == null || root.isEmpty) return null;
    return WaifuStore(waifuStoreDirectory(root));
  } catch (_) {
    return null;
  }
}

/// Sit-down estimate when no harness is bound (system + advertised tools).
int waifuIdleRequestTokens(WaifuSession session) {
  final messages = waifuOpenAiMessages(
    folderName: session.folderRoot,
    coworkerName: session.coworker.name,
    transcript: session.transcript,
    todos: session.todos.items.isEmpty ? '' : session.todos.read(),
    mentionBlock: '',
    preserveThinking: session.preserveThinking,
    pathMode: session.pathMode,
    mode: session.mode,
  );
  return waifuMeasureRequest(
    systemPrompt: buildWaifuCoworkerPrompt(session.coworker),
    prompt: waifuMessagesMeterText(messages),
    budget: session.contextBudget,
    tools: waifuAdvertisedTools(
      exploreOnly: false,
      includeWebSearch: false,
      mcpOptIn: session.mcpOptIn,
      mcpTools: const [],
      includeTask: true,
      pathMode: session.pathMode,
      mode: session.mode,
    ),
  ).used;
}

/// Remeter then persist so sit-down is never saved as 0/N.
void waifuArmSessionMeter({
  required WaifuSession session,
  WaifuHarness? harness,
  WaifuStore? store,
}) {
  if (session.tokensUsed == 0 && !session.tokensFromApi) {
    session.tokensUsed = waifuIdleRequestTokens(session);
  }
  harness?.refreshMeter();
  store?.saveLast(session);
}

/// Both production constructor copies live here so the page never writes
/// `WaifuHarness(`.
WaifuHarness? waifuBindSessionHarness({
  required WaifuSession session,
  WaifuLlm? llm,
  LLMProvider? provider,
  StorageService? storage,
  OpenCodeManager? manager,
  WaifuStore? store,
  void Function()? onChanged,
  WaifuAskFn? onAsk,
  WaifuQuestionFn? onQuestion,
  WaifuMcpOf? mcpOf,
  WaifuWebSearchFn? webSearch,
  WaifuSkillHub? skills,
}) {
  OpenCodePorchBackend? backend;
  if (provider != null) {
    try {
      backend = openCodeBackendFromProvider(provider);
    } catch (_) {}
  }
  if (llm == null && manager == null && backend == null) return null;
  return WaifuHarness(
    session: session,
    llm: llm,
    manager: manager,
    backend: backend,
    store: store,
    onChanged: onChanged,
    onAsk: onAsk,
    onQuestion: onQuestion,
    mcpToolsOf: mcpOf == null ? null : () => mcpOf().tools,
    mcpCallOf: mcpOf == null ? null : () => mcpOf().call,
    mcpOptIn: session.mcpOptIn,
    webSearch: webSearch,
    skills: skills,
  );
}

WaifuMcpOf waifuLiveMcpOf(BuildContext context) =>
    () => waifuMcpBind(context);
