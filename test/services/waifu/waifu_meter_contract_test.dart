// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';

void main() {
  test('constructor keeps resumed API usage instead of clobbering', () {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    )
      ..tokensUsed = 30490
      ..tokensFromApi = true
      ..contextBudget = 277518;
    WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
    );
    expect(session.tokensUsed, 30490);
    expect(session.tokensFromApi, isTrue);
  });

  test('idle bind still meters when usage is empty', () {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris', personality: 'dry'),
    );
    expect(session.tokensUsed, 0);
    WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
    );
    expect(session.tokensUsed, greaterThan(0));
  });

  test('photo payload is counted in the request snapshot', () {
    final text = waifuMeasureRequest(
      systemPrompt: 'sys',
      prompt: 'see this',
      budget: 8192,
    );
    final photo = waifuMeasureRequest(
      systemPrompt: 'sys',
      prompt: 'see this',
      budget: 8192,
      images: [List.filled(400, 'a').join()],
    );
    expect(photo.used, greaterThan(text.used));
    expect(waifuEstimateImageTokens(['abcd']), 85);
  });

  test('unmetered bar is not a real 0 fill', () {
    expect(
      waifuContextBarLabel(used: 0, budget: 8192, fromApi: false),
      '— / 8192',
    );
    expect(
      waifuContextBarLabel(used: 100, budget: 8192, fromApi: false),
      '100 / 8192',
    );
  });

  test('child generate remaining is not the parent bind closure', () async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    )..tokensUsed = 7000;
    final parent = LlmServiceWaifuLlm(
      () => throw StateError('unused'),
      remainingTokensOf: () => waifuOutputTokenBudget(
        budget: session.contextBudget,
        used: session.tokensUsed,
      ),
    );
    // Scripted path: harness passes maxTokens from its own live measure.
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'hi'),
    ]);
    final childSession = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: childSession, llm: llm).send('hey');
    expect(llm.calls, isNotEmpty);
    expect(llm.calls.first.maxTokens, isNotNull);
    expect(
      llm.calls.first.maxTokens,
      isNot(waifuOutputTokenBudget(budget: 8192, used: 7000)),
    );
    expect(parent, isNotNull);
  });
}
