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

/// Catalog / 400 memory of whether an OpenRouter **model id** speaks tools.
///
/// Public openrouter.ai only. Keyed by model id, never by vendor brand —
/// `x-ai/grok-4.6` and `anthropic/claude-sonnet-4` are separate entries.
enum OpenRouterToolsVerdict { unknown, advertised, confirmed, rejected }

/// `supported_parameters` → advertised tools, or null when the list is
/// missing (unknown: first tools POST is allowed).
bool? toolsAdvertisedFromParameters(dynamic params) {
  if (params is! List) return null;
  return params.map((e) => e.toString().toLowerCase()).contains('tools');
}

/// 400 whose body says this model / route cannot take `tools`.
bool isOpenRouterToolsUnsupportedStatus(int statusCode, String body) {
  if (statusCode != 400 && statusCode != 404) return false;
  final lower = body.toLowerCase();
  if (lower.contains('tool_choice')) return false;
  return lower.contains('tool use') ||
      lower.contains('tools are not') ||
      lower.contains('does not support tool') ||
      (lower.contains('tool calling') && lower.contains('not support')) ||
      lower.contains('no endpoints found that support tool');
}

/// Process-lifetime per-model-id memory. Injectable default singleton so
/// tests cannot leak across cases.
class OpenRouterToolSupport {
  OpenRouterToolSupport();

  static final OpenRouterToolSupport instance = OpenRouterToolSupport();

  final Map<String, OpenRouterToolsVerdict> _verdicts = {};

  OpenRouterToolsVerdict verdictFor(String modelId) =>
      _verdicts[modelId] ?? OpenRouterToolsVerdict.unknown;

  /// Unknown, advertised, or a prior 200 → send tools. Catalog-without-tools
  /// or a remembered 400 → never send `tools` / `tool_choice`.
  bool shouldSendTools(String modelId) => switch (verdictFor(modelId)) {
    OpenRouterToolsVerdict.rejected => false,
    OpenRouterToolsVerdict.unknown ||
    OpenRouterToolsVerdict.advertised ||
    OpenRouterToolsVerdict.confirmed => true,
  };

  /// Seed from OpenRouter `/models` `supported_parameters`.
  void rememberFromCatalog(String modelId, {required bool advertised}) {
    if (modelId.isEmpty) return;
    final current = _verdicts[modelId];
    if (current == OpenRouterToolsVerdict.confirmed ||
        current == OpenRouterToolsVerdict.rejected) {
      return;
    }
    _verdicts[modelId] = advertised
        ? OpenRouterToolsVerdict.advertised
        : OpenRouterToolsVerdict.rejected;
  }

  void rememberConfirmed(String modelId) {
    if (modelId.isEmpty) return;
    if (_verdicts[modelId] == OpenRouterToolsVerdict.rejected) return;
    _verdicts[modelId] = OpenRouterToolsVerdict.confirmed;
  }

  void rememberRejected(String modelId) {
    if (modelId.isEmpty) return;
    _verdicts[modelId] = OpenRouterToolsVerdict.rejected;
  }

  void reset(String modelId) => _verdicts.remove(modelId);

  @visibleForTesting
  void resetForTest() => _verdicts.clear();
}
