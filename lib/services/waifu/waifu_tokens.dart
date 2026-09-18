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

/// Chrome meter helpers. Not an in-process Dart compact loop.
const kWaifuCompactAt = 0.75;
const kWaifuDefaultContextTokens = 8192;
const kWaifuCompactPrefix = '[Session compact]';

/// Fallback only — the bar prefers server usage when the backend sent it.
int waifuEstimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

/// OpenCode native tools (read/write/edit/bash/glob/grep/list/todo/skill).
const kWaifuOpenCodeNativeToolTokens = 2800;

/// Rough schema cost per MCP tool OpenCode injects into the prompt.
const kWaifuMcpToolSchemaTokens = 160;

/// What OpenCode actually sends is card + speech + native tools + MCP.
int waifuOpenCodePromptEstimate({
  required String systemPrompt,
  required String speech,
  int mcpToolCount = 0,
}) {
  final mcp = mcpToolCount < 0 ? 0 : mcpToolCount;
  return waifuEstimateTokens(systemPrompt) +
      waifuEstimateTokens(speech) +
      kWaifuOpenCodeNativeToolTokens +
      mcp * kWaifuMcpToolSchemaTokens;
}

bool waifuLooksLikeOmlxUrl(String url) {
  final u = url.toLowerCase();
  return u.contains('localhost:8000') || u.contains('127.0.0.1:8000');
}

/// kcpps / remote n_ctx is not the oMLX window (dashboard ~40k).
int waifuResolveContextBudget({
  required int porchContextSize,
  required String? apiUrl,
}) {
  final porch = porchContextSize < 1
      ? kWaifuDefaultContextTokens
      : porchContextSize;
  if (apiUrl != null && waifuLooksLikeOmlxUrl(apiUrl) && porch > 65536) {
    return 40960;
  }
  return porch;
}

/// Same number the sidebar bar shows: API usage when we have it.
int waifuFillUsed({
  required int tokensUsed,
  required bool fromApi,
  required int estimated,
}) => fromApi && tokensUsed > 0 ? tokensUsed : estimated;
