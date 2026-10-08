// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// xAI's reasoning models (Grok 4 family) reject `stop` and reasoning
// controls with a 400 instead of ignoring them like OpenRouter. The xAI
// host must get a standard-fields-only body; OpenRouter keeps its extras.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';

GenerationParams _params() => GenerationParams(
  prompt: 'hello',
  maxLength: 400,
  temperature: 0.8,
  topP: 0.9,
  minP: 0.05,
  topK: 40,
  repeatPenalty: 1.1,
  stopSequences: const ['\nUser:'],
  reasoningEnabled: false,
  reasoningMaxTokens: 0,
);

Map<String, dynamic> _body(String url) => OpenRouterService(
  apiUrl: url,
  apiKey: 'k',
  modelName: 'grok-4',
).chatRequestPayload(_params());

void main() {
  test('xAI gets only standard fields', () {
    final body = _body(kXaiApiV1);
    expect(body['model'], 'grok-4');
    expect(body['temperature'], 0.8);
    expect(body['top_p'], 0.9);
    expect(body['max_tokens'], 400);
    for (final banned in [
      'stop',
      'reasoning',
      'reasoning_effort',
      'repetition_penalty',
      'min_p',
      'top_k',
      'frequency_penalty',
      'presence_penalty',
    ]) {
      expect(body.containsKey(banned), isFalse, reason: banned);
    }
  });

  test('OpenRouter keeps stops, samplers, and the reasoning switch', () {
    final body = _body(kOpenRouterApiV1);
    expect(body['stop'], ['\nUser:']);
    expect(body['repetition_penalty'], 1.1);
    expect(body['min_p'], 0.05);
    expect(body['top_k'], 40);
    expect(body['reasoning'], isA<Map<String, dynamic>>());
  });
}
