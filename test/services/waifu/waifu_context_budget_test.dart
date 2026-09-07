// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';

void main() {
  test('waifuMeasurePrompt adds system tokens to the user prompt', () {
    final system = 'SYSTEM_BLOCK ' * 40;
    final prompt = 'USER_BLOCK ' * 10;
    final snap = waifuMeasurePrompt(
      systemPrompt: system,
      prompt: prompt,
      budget: 8192,
    );
    expect(snap.used, waifuEstimateTokens(system) + waifuEstimateTokens(prompt));
    expect(snap.used, greaterThan(waifuEstimateTokens(prompt)));
  });

  test('harness tokensUsed includes the coworker system prompt', () async {
    final root = await Directory.systemTemp.createTemp('waifu_budget_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'Hmph.'),
    ]);
    final coworker = CharacterCard(
      name: 'Iris',
      personality: 'dry, does the work',
    );
    final session = WaifuSession(folderRoot: root.path, coworker: coworker);
    await WaifuHarness(session: session, llm: llm).send('hi');
    expect(llm.calls, hasLength(1));
    final request = waifuMeasurePrompt(
      systemPrompt: llm.calls.first.systemPrompt,
      prompt: llm.calls.first.prompt,
      budget: session.contextBudget,
    );
    // Meter is the payload just sent, plus the spoken reply now in the
    // transcript (counted after the turn so the bar matches the next send).
    expect(session.tokensUsed, greaterThanOrEqualTo(request.used));
    expect(
      session.tokensUsed,
      greaterThan(waifuEstimateTokens(llm.calls.first.prompt)),
    );
    expect(llm.calls.first.systemPrompt, contains(kWaifuPreamble));
  });
}
