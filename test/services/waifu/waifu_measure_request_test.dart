// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  const tools = [
    {
      'type': 'function',
      'function': {
        'name': 'read',
        'description': 'Read a file from the sit-down folder.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
        },
      },
    },
  ];

  test(
    'system prompt and tools count; prompt-only is not the whole request',
    () {
      final system = 'SYSTEM_BLOCK ' * 40;
      final prompt = 'USER_BLOCK ' * 10;
      final snap = waifuMeasureRequest(
        systemPrompt: system,
        prompt: prompt,
        budget: 8192,
        tools: tools,
      );
      final textOnly =
          waifuEstimateTokens(system) + waifuEstimateTokens(prompt);
      expect(snap.used, greaterThan(textOnly));
      expect(snap.used, greaterThan(waifuEstimateTokens(prompt)));
      expect(snap.fromApi, isFalse);
    },
  );

  test('API total_tokens wins over the chars/4 guess', () {
    final snap = waifuMeasureRequest(
      systemPrompt: 'sys',
      prompt: 'hello',
      budget: 8192,
      tools: tools,
      totalTokens: 4242,
    );
    expect(snap.used, 4242);
    expect(snap.fromApi, isTrue);
    expect(snap.used, isNot(waifuEstimateTokens('syshello')));
  });

  test('prompt_tokens plus streamed completion when total is missing', () {
    final snap = waifuMeasureRequest(
      systemPrompt: 'sys',
      prompt: 'hello',
      budget: 8192,
      promptTokens: 1000,
      streamed: 'abcd',
    );
    expect(snap.used, 1000 + waifuEstimateTokens('abcd'));
    expect(snap.fromApi, isTrue);
  });

  test('75% of the window is the compact line', () {
    expect(waifuShouldCompact(used: 6144, budget: 8192), isTrue);
    expect(waifuShouldCompact(used: 1000, budget: 8192), isFalse);
    expect(waifuShouldCompact(used: 17213, budget: 277518), isFalse);
  });
}
