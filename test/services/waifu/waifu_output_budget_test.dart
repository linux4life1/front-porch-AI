// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';

class _CapLlm extends LLMService {
  GenerationParams? last;

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    last = params;
    return const LlmToolResponse(calls: [], text: 'ok');
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'fake';
}

void main() {
  test('output budget is remaining context, not the chat 2048 cap', () {
    expect(waifuOutputTokenBudget(budget: 277518, used: 9855), 277518 - 9855);
    expect(waifuOutputTokenBudget(budget: 2048, used: 3000), 1);
  });

  test('Waifu Coder generate ignores chat Max Output Tokens', () async {
    final backend = _CapLlm();
    final waifu = LlmServiceWaifuLlm(
      () => backend,
      remainingTokensOf: () => 50000,
    );
    await waifu.generate(
      systemPrompt: 'sys',
      prompt: 'write the file',
      tools: const [],
    );
    expect(backend.last, isNotNull);
    expect(backend.last!.maxLength, 50000);
    expect(backend.last!.maxLength, isNot(2048));
    expect(backend.last!.maxLength, isNot(4096));
    expect(backend.last!.minLength, 0);
  });
}
