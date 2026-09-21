// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Dedicated public-OpenRouter tools path: one HTTP POST per named eval,
// no json_schema-then-tools double bill, no tool_choice style roulette,
// at most one payload-fix retry.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openrouter_tool_support.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  const tools = [
    {
      'type': 'function',
      'function': {
        'name': 'report_relationship',
        'parameters': {
          'type': 'object',
          'properties': {
            'relationship_delta': {'type': 'integer'},
            'trust_delta': {'type': 'integer'},
          },
          'required': ['relationship_delta', 'trust_delta'],
        },
      },
    },
  ];

  const named = GenerationParams(
    prompt: 'score this',
    maxLength: 512,
    temperature: 0.1,
    toolChoice: 'report_relationship',
    salvageReasoning: true,
    reasoningEnabled: false,
    reasoningMaxTokens: 0,
  );

  const toolOk = {
    'choices': [
      {
        'finish_reason': 'tool_calls',
        'message': {
          'tool_calls': [
            {
              'function': {
                'name': 'report_relationship',
                'arguments': '{"relationship_delta":4,"trust_delta":2}',
              },
            },
          ],
        },
      },
    ],
  };

  setUp(() {
    OpenRouterToolSupport.instance.resetForTest();
    ToolChoiceStyleProbe.instance.resetForTest();
  });

  OpenRouterService orService({
    required Future<http.Response> Function(http.Request request) onRequest,
    String modelName = 'x-ai/grok-4.6',
  }) {
    final remote = OpenRouterService(
      apiUrl: 'https://openrouter.ai/api/v1',
      apiKey: 'test-key',
      modelName: modelName,
    );
    remote.httpClientFactory = () => MockClient(onRequest);
    return remote;
  }

  group('OpenRouterToolSupport', () {
    test(
      'missing supported_parameters stays unknown and still sends tools',
      () {
        expect(toolsAdvertisedFromParameters(null), isNull);
        expect(toolsAdvertisedFromParameters('tools'), isNull);
        expect(
          OpenRouterToolSupport.instance.shouldSendTools('unknown-id'),
          isTrue,
        );
      },
    );

    test('catalog tools list advertises; list without tools never sends', () {
      expect(toolsAdvertisedFromParameters(['temperature', 'TOOLS']), isTrue);
      expect(toolsAdvertisedFromParameters(['temperature', 'top_p']), isFalse);
      OpenRouterToolSupport.instance.rememberFromCatalog(
        'small-model',
        advertised: false,
      );
      expect(
        OpenRouterToolSupport.instance.shouldSendTools('small-model'),
        isFalse,
      );
      OpenRouterToolSupport.instance.rememberFromCatalog(
        'x-ai/grok-4.6',
        advertised: true,
      );
      expect(
        OpenRouterToolSupport.instance.shouldSendTools('x-ai/grok-4.6'),
        isTrue,
      );
    });

    test('400 tools-not-supported is remembered per model id', () {
      OpenRouterToolSupport.instance.rememberRejected('img-only');
      expect(
        OpenRouterToolSupport.instance.shouldSendTools('img-only'),
        isFalse,
      );
      expect(OpenRouterToolSupport.instance.shouldSendTools('other'), isTrue);
    });

    test('OpenRouter catalog tools-only still advertises tools', () {
      final caps = ModelApiCapabilities.fromOpenRouterEntry({
        'id': 'provider/tools-but-no-forced-choice',
        'supported_parameters': ['tools', 'temperature'],
      });
      expect(caps.advertisesTools, isTrue);
      expect(caps.toolCalling, isFalse);
    });
  });

  group('dedicated OpenRouter generateWithTools', () {
    test(
      'named eval is exactly one POST on 200, nested tools, no schema',
      () async {
        final payloads = <Map<String, dynamic>>[];
        final remote = orService(
          onRequest: (request) async {
            payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(jsonEncode(toolOk), 200);
          },
        );

        final resp = await remote.generateStructuredJson(named, tools);
        expect(
          payloads,
          hasLength(1),
          reason: 'json_schema-then-tools is a double bill',
        );
        expect(payloads.single.containsKey('response_format'), isFalse);
        expect(payloads.single['tools'], isNotEmpty);
        expect(payloads.single['tool_choice'], {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        });
        expect(payloads.single['provider'], {'require_parameters': true});
        expect(payloads.single.containsKey('reasoning'), isFalse);
        expect(resp!.calls.single.arguments['relationship_delta'], 4);
      },
    );

    test(
      'empty tool_calls + finish_reason=tool_calls does not POST again',
      () async {
        var posts = 0;
        final remote = orService(
          onRequest: (request) async {
            posts++;
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'tool_calls',
                    'message': {'content': '', 'tool_calls': <dynamic>[]},
                  },
                ],
              }),
              200,
            );
          },
        );

        final resp = await remote.generateStructuredJson(named, tools);
        expect(posts, 1);
        expect(resp, isNotNull);
        expect(resp!.calls, isEmpty);
        expect(resp.finishReason, 'tool_calls');
      },
    );

    test('thinking-off 400 retries once then stops', () async {
      var posts = 0;
      final remote = orService(
        modelName: 'think-off-retry',
        onRequest: (request) async {
          posts++;
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'Kimi K2 Thinking is a mandatory-reasoning model. Use '
                    'reasoning.exclude=true to hide reasoning output.',
              },
            }),
            400,
          );
        },
      );

      final resp = await remote.generateWithTools(named, tools);
      expect(posts, 2, reason: 'one remembered payload fix, never recurse');
      expect(resp, isNull);
      expect(kMandatoryReasoningModels.contains('think-off-retry'), isTrue);
      kMandatoryReasoningModels.remove('think-off-retry');
    });

    test('tool_choice 400 never style-probes required or auto', () async {
      final choices = <Object?>[];
      final remote = orService(
        onRequest: (request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          choices.add(body['tool_choice']);
          return http.Response(
            jsonEncode({
              'error': {'message': 'unknown tool_choice value'},
            }),
            400,
          );
        },
      );

      await remote.generateWithTools(named, tools);
      expect(
        choices,
        hasLength(1),
        reason: 'named → required → auto is a triple bill',
      );
      expect(choices.single, {
        'type': 'function',
        'function': {'name': 'report_relationship'},
      });
    });

    test('catalog no-tools never sends tools or tool_choice', () async {
      OpenRouterToolSupport.instance.rememberFromCatalog(
        'small-no-tools',
        advertised: false,
      );
      var posts = 0;
      final remote = orService(
        modelName: 'small-no-tools',
        onRequest: (request) async {
          posts++;
          return http.Response(jsonEncode(toolOk), 200);
        },
      );

      final resp = await remote.generateWithTools(named, tools);
      expect(posts, 0);
      expect(resp, isNull);
    });

    test(
      'tools-not-supported 400 is remembered so the next eval does not retry',
      () async {
        var posts = 0;
        final remote = orService(
          modelName: 'image-only',
          onRequest: (request) async {
            posts++;
            return http.Response(
              jsonEncode({
                'error': {
                  'message': 'No endpoints found that support tool use',
                },
              }),
              400,
            );
          },
        );

        expect(await remote.generateWithTools(named, tools), isNull);
        expect(posts, 1);
        expect(await remote.generateWithTools(named, tools), isNull);
        expect(posts, 1, reason: 'second eval must not hammer tools');
      },
    );

    test('Journal auto choice stays auto, still one POST', () async {
      final payloads = <Map<String, dynamic>>[];
      final remote = orService(
        onRequest: (request) async {
          payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(toolOk), 200);
        },
      );

      await remote.generateWithTools(
        const GenerationParams(prompt: 'journal', maxLength: 4000),
        tools,
      );
      expect(payloads, hasLength(1));
      expect(payloads.single['tool_choice'], 'auto');
      expect(payloads.single.containsKey('response_format'), isFalse);
    });

    test(
      'Nano-GPT named eval still uses the old soup, not require_parameters',
      () async {
        Map<String, dynamic>? payload;
        var posts = 0;
        final remote = OpenRouterService(
          apiUrl: 'https://nano-gpt.com/api/v1',
          apiKey: 'test-key',
          modelName: 'same-model',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          posts++;
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(toolOk), 200);
        });

        await remote.generateStructuredJson(named, tools);
        expect(posts, 1);
        expect(payload!.containsKey('response_format'), isFalse);
        expect(payload!.containsKey('provider'), isFalse);
        expect(payload!['tools'], isNotEmpty);
      },
    );

    test(
      'Waifu thinking-on keeps reasoning and does not inherit the eval floor',
      () async {
        Map<String, dynamic>? payload;
        final remote = orService(
          onRequest: (request) async {
            payload = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(jsonEncode(toolOk), 200);
          },
        );

        await remote.generateWithTools(
          const GenerationParams(
            prompt: 'sit down',
            maxLength: 800,
            reasoningEnabled: true,
            reasoningEffort: 'low',
            toolChoice: 'required',
          ),
          tools,
        );
        expect(payload!['reasoning'], isA<Map>());
        expect((payload!['reasoning'] as Map)['enabled'], isTrue);
        expect(payload!['max_tokens'], 800);
        expect(payload!['provider'], {'require_parameters': true});
      },
    );
  });

  group('no second generate after native tools', () {
    test(
      'fireStructuredEval does not fire text on unusable tool_calls',
      () async {
        var textCalls = 0;
        final probe = ToolTransportProbe();
        final result = await fireStructuredEval(
          probe: probe,
          backendIdentity: 'Remote API|x-ai/grok-4.6|',
          debugLabel: 'relationship',
          tools: tools,
          toolChoice: 'report_relationship',
          buildPrompt: ({required bool toolsMode}) =>
              toolsMode ? 'TOOLS' : 'TEXT',
          callToText: (resp) =>
              realismToolCallToJson('report_relationship', resp.calls),
          fireToolEval: (_, _) async => const LlmToolResponse(
            calls: [],
            text: '',
            finishReason: 'tool_calls',
          ),
          fireTextEval: (prompt, {onChunk}) async {
            textCalls++;
            return 'TEXT-RESULT';
          },
        );
        expect(result, isNull);
        expect(
          textCalls,
          0,
          reason: 'empty tool_calls must not bill a JSON floor',
        );
      },
    );
  });
}
