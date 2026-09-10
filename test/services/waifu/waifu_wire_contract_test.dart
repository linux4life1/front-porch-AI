// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wrap-up must not POST tools: []. Think-cap / required pins live in
// waifu_harness_loop_wire_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_tool_payload.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('Waifu wrap-up omits empty tools on OpenRouter', () async {
    Map<String, dynamic>? payload;
    final remote = OpenRouterService(
      apiUrl: 'https://openrouter.ai/api/v1',
      apiKey: 'test-key',
      modelName: 'z-ai/glm-5.3',
    );
    remote.httpClientFactory = () => MockClient((request) async {
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        'data: {"choices":[{"delta":{"content":"done"}}]}\n\n'
        'data: [DONE]\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    await LlmServiceWaifuLlm(() => remote).generate(
      systemPrompt: 's',
      prompt: 'p',
      tools: const [],
      onChunk: (_) {},
    );
    expect(payload!.containsKey('tools'), isFalse);
    expect(payload!.containsKey('tool_choice'), isFalse);
    expect((payload!['reasoning'] as Map)['enabled'], isTrue);
    expect((payload!['reasoning'] as Map)['max_tokens'], kWaifuWrapThinkCapTokens);
    expect((payload!['reasoning'] as Map).containsKey('exclude'), isFalse);
  });

  test('attachTools with no tools omits tools and tool_choice', () {
    final payload = attachTools(<String, dynamic>{}, tools: const []);
    expect(payload.containsKey('tools'), isFalse);
    expect(payload.containsKey('tool_choice'), isFalse);
  });
}
