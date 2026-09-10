// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live GLM 5.3 incidents: thinking 400s between writes. Chat remaps
// Low→High on that family; Waifu must omit effort and cap think at 512.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/openrouter_structured_eval.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

const _tools = [
  {
    'type': 'function',
    'function': {'name': 'read'},
  },
];

const _sseTool =
    'data: {"choices":[{"delta":{"reasoning_content":"plan the edit"}}]}\n\n'
    'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"read","arguments":"{\\"path\\":\\"a.swift\\"}"}}]}}]}\n\n'
    'data: [DONE]\n';

void main() {
  setUpAll(() => HttpOverrides.global = null);
  setUp(clearReasoningEffortCatalog);
  tearDown(clearReasoningEffortCatalog);
  setUp(ToolChoiceStyleProbe.instance.resetForTest);

  test('GLM 5.3 requested low wires high, never none or exclude', () {
    expect(wireReasoningEffort('z-ai/glm-5.3', 'low'), 'high');
    expect(wireReasoningEffort('z-ai/glm5.3', 'low'), 'high');
    expect(reasoningCannotDisable('z-ai/glm-5.3'), isFalse);
    expect(reasoningEffortHintForModel('z-ai/glm-5.3'), kHighMaxEffortHint);
  });

  test('eval routing is off for Waifu required+think-on', () {
    expect(
      shouldApplyOpenRouterEvalToolRouting(
        reasoningEnabled: true,
        reasoningMaxTokens: kWaifuThinkCapTokens,
        toolChoice: kToolChoiceRequired,
      ),
      isFalse,
    );
    expect(
      shouldApplyOpenRouterEvalToolRouting(
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        toolChoice: 'report_relationship',
      ),
      isTrue,
    );
  });

  test('applyOpenRouterToolRouting keeps a live think object', () {
    final kept = applyOpenRouterToolRouting({
      'max_tokens': 8000,
      'min_p': 0.05,
      'reasoning': {
        'enabled': true,
        'effort': 'high',
        'max_tokens': kWaifuThinkCapTokens,
      },
    }, mandatoryReasoning: false);
    expect(kept['reasoning'], {
      'enabled': true,
      'effort': 'high',
      'max_tokens': kWaifuThinkCapTokens,
    });
    expect(kept['max_tokens'], 8000);
    expect(kept.containsKey('provider'), isFalse);
  });

  test(
    'Waifu OpenRouter tools omit effort, cap think at 512, required, wrap',
    () async {
      Map<String, dynamic>? payload;
      final chunks = <String>[];
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'z-ai/glm-5.3',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          _sseTool,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final resp = await LlmServiceWaifuLlm(() => remote).generate(
        systemPrompt: 's',
        prompt: 'p',
        tools: _tools,
        onChunk: chunks.add,
      );

      final reasoning = payload!['reasoning'] as Map;
      expect(reasoning['enabled'], isTrue);
      expect(reasoning.containsKey('effort'), isFalse);
      expect(reasoning['max_tokens'], 512);
      expect(reasoning['max_tokens'], kWaifuThinkCapTokens);
      expect(reasoning.containsKey('exclude'), isFalse);
      expect(payload!['tool_choice'], kToolChoiceRequired);
      expect(payload!.containsKey('provider'), isFalse);
      expect(payload!['max_tokens'], isNot(0));
      expect(payload!['max_tokens'], isNot(kOpenRouterStructuredEvalMinTokens));
      expect(chunks.join(), contains('<think>'));
      expect(chunks.join(), contains('plan the edit'));
      expect(resp!.calls.single.name, 'read');
    },
  );

  test(
    'unhinted effort 400 retries tools without dropping the think cap',
    () async {
      final seen = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final body =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        seen.add(body);
        final effort = (body['reasoning'] as Map?)?['effort'];
        if (effort == 'low') {
          req.response
            ..statusCode = 400
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'error': {
                  'message':
                      'Invalid value for reasoning.effort on model '
                      '"acme/custom-reasoner": "low". Supported values are: '
                      'none, high, max.',
                },
              }),
            );
          await req.response.close();
          return;
        }
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream');
        req.response.write(_sseTool);
        await req.response.close();
      });

      final svc = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'acme/custom-reasoner',
      );
      final resp = await svc.generateWithTools(
        GenerationParams(
          prompt: 'p',
          systemPrompt: 's',
          reasoningEnabled: true,
          reasoningEffort: 'low',
          reasoningMaxTokens: kWaifuThinkCapTokens,
          toolChoice: kToolChoiceRequired,
          onChunk: (_) {},
        ),
        _tools,
      );

      expect(seen, hasLength(2));
      expect((seen[0]['reasoning'] as Map)['effort'], 'low');
      expect((seen[0]['reasoning'] as Map)['max_tokens'], kWaifuThinkCapTokens);
      expect((seen[1]['reasoning'] as Map)['effort'], 'high');
      expect((seen[1]['reasoning'] as Map)['max_tokens'], kWaifuThinkCapTokens);
      expect((seen[1]['reasoning'] as Map)['enabled'], isTrue);
      expect(resp!.calls, isNotEmpty);
    },
  );

  test('local GLM think-on sends thinking_budget 512, never 0', () async {
    Map<String, dynamic>? last;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      last =
          jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream');
      req.response.write(_sseTool);
      await req.response.close();
    });

    final svc = OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}/v1',
      modelName: 'z-ai/glm-5.3',
    );
    await LlmServiceWaifuLlm(
      () => svc,
    ).generate(systemPrompt: 's', prompt: 'p', tools: _tools, onChunk: (_) {});
    expect(last!['thinking_budget'], kWaifuThinkCapTokens);
    expect(last!['thinking_budget'], isNot(0));
    expect(last!['chat_template_kwargs'], {'enable_thinking': true});
    expect((last!['reasoning'] as Map)['max_tokens'], kWaifuThinkCapTokens);
  });

  test('Kobold stream tools start at required and cap think at 512', () async {
    Map<String, dynamic>? last;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      last =
          jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream');
      req.response.write(_sseTool);
      await req.response.close();
    });

    await postOpenAiChatWithTools(
      'http://127.0.0.1:${server.port}',
      GenerationParams(
        prompt: 'p',
        reasoningEnabled: true,
        reasoningEffort: 'low',
        reasoningMaxTokens: kWaifuThinkCapTokens,
        toolChoice: kToolChoiceRequired,
        onChunk: (_) {},
      ),
      _tools,
    );
    expect(last!['tool_choice'], kToolChoiceRequired);
    expect(last!['thinking_budget'], kWaifuThinkCapTokens);
    expect(last!['chat_template_kwargs'], {'enable_thinking': true});
  });
}
