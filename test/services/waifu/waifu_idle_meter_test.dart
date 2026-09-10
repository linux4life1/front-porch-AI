// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('idle harness meters system prompt and tools before any send', () {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris', personality: 'dry, does the work'),
    );
    expect(session.tokensUsed, 0);
    WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
    );
    expect(session.tokensUsed, greaterThan(0));
    expect(
      session.tokensUsed,
      greaterThan(waifuEstimateTokens(kWaifuPreamble)),
    );
  });
}
