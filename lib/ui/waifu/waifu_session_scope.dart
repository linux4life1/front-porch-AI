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

/// Sit-down estimate. OpenCode owns the real window; this is chrome only.
int waifuIdleRequestTokens(WaifuSession session) {
  final sys = buildWaifuOpenCodeAgentPrompt(session.coworker);
  final speech = [for (final m in session.transcript) m.text].join('\n');
  return waifuEstimateTokens(sys) + waifuEstimateTokens(speech);
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

/// Bind OpenCode manager + Porch backend. Null when neither is available.
WaifuHarness? waifuBindSessionHarness({
  required WaifuSession session,
  LLMProvider? provider,
  OpenCodeManager? manager,
  WaifuStore? store,
  void Function()? onChanged,
  WaifuAskFn? onAsk,
  WaifuQuestionFn? onQuestion,
  Map<String, dynamic> Function()? mcpConfigOf,
}) {
  OpenCodePorchBackend? backend;
  if (provider != null) {
    try {
      backend = openCodeBackendFromProvider(provider.activeService);
    } catch (_) {}
  }
  if (manager == null && backend == null) return null;
  return WaifuHarness(
    session: session,
    manager: manager,
    backend: backend,
    store: store,
    onChanged: onChanged,
    onAsk: onAsk,
    onQuestion: onQuestion,
    mcpOptIn: session.mcpOptIn,
    mcpConfigOf: mcpConfigOf,
  );
}
