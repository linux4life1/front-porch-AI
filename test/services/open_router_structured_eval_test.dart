// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Public OpenRouter named evals use nested tools (one POST). Nano-GPT
// keeps the probe soup. json_schema-then-tools was a double bill.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openrouter_structured_eval.dart';
import 'package:front_porch_ai/services/openrouter_tool_support.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('isOpenRouterApiUrl', () {
    test('only the public OpenRouter hosts match', () {
      expect(isOpenRouterApiUrl('https://openrouter.ai/api/v1'), isTrue);
      expect(isOpenRouterApiUrl('https://eu.openrouter.ai/api/v1'), isTrue);
      expect(isOpenRouterApiUrl('https://nano-gpt.com/api/v1'), isFalse);
      expect(isOpenRouterApiUrl('http://127.0.0.1:1234/v1'), isFalse);
      expect(isOpenRouterApiUrl('http://192.168.1.10:8080/v1'), isFalse);
    });
  });

  group('applyOpenRouterToolRouting', () {
    test('forces require_parameters and strips OR-hostile samplers', () {
      final payload = applyOpenRouterToolRouting({
        'max_tokens': 512,
        'repetition_penalty': 1.15,
        'min_p': 0.05,
        'top_k': 40,
        'reasoning': {'enabled': false},
      }, mandatoryReasoning: false);
      expect(payload.containsKey('min_p'), isFalse);
      expect(payload.containsKey('top_k'), isFalse);
      expect(payload.containsKey('repetition_penalty'), isFalse);
      expect(payload.containsKey('reasoning'), isFalse);
      expect(payload['provider'], {'require_parameters': true});
      expect(payload['max_tokens'], kOpenRouterStructuredEvalMinTokens);
    });

    test('thinking models get the same headroom as text evals', () {
      final payload = applyOpenRouterToolRouting({
        'max_tokens': 512,
      }, mandatoryReasoning: true);
      expect(
        payload['max_tokens'],
        kOpenRouterStructuredEvalMinTokens +
            kMandatoryReasoningThinkHeadroomTokens,
      );
    });
  });

  group('OpenRouterService.generateStructuredJson', () {
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

    setUp(OpenRouterToolSupport.instance.resetForTest);

    test('OpenRouter named eval sends nested tools, not json_schema', () async {
      Map<String, dynamic>? payload;
      var posts = 0;
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'x-ai/grok-4',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        posts++;
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
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
          }),
          200,
        );
      });

      final resp = await remote.generateStructuredJson(named, tools);
      expect(posts, 1);
      expect(payload!.containsKey('response_format'), isFalse);
      expect(payload!['tools'], isNotEmpty);
      expect(payload!['tool_choice'], {
        'type': 'function',
        'function': {'name': 'report_relationship'},
      });
      expect(payload!.containsKey('reasoning'), isFalse);
      expect(payload!['provider'], {'require_parameters': true});
      expect(payload!['max_tokens'], kOpenRouterStructuredEvalMinTokens);
      expect(resp!.calls.single.arguments['relationship_delta'], 4);
    });

    test(
      'Nano-GPT named eval keeps tools and never sends json_schema',
      () async {
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://nano-gpt.com/api/v1',
          apiKey: 'test-key',
          modelName: 'same-model',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'report_relationship',
                          'arguments':
                              '{"relationship_delta":1,"trust_delta":0}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        });

        final resp = await remote.generateStructuredJson(named, tools);
        expect(payload!.containsKey('response_format'), isFalse);
        expect(payload!['tools'], isNotEmpty);
        expect(payload!.containsKey('provider'), isFalse);
        expect(resp!.calls.single.arguments['relationship_delta'], 1);
      },
    );

    test('OpenRouter Journal (no named tool) stays on tools', () async {
      Map<String, dynamic>? payload;
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'openai/gpt-4o',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'name': 'add_memory',
                        'arguments': '{"content":"rain"}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      });

      await remote.generateStructuredJson(
        const GenerationParams(prompt: 'journal', maxLength: 4000),
        tools,
      );
      expect(payload!.containsKey('response_format'), isFalse);
      expect(payload!['tools'], isNotEmpty);
      expect(payload!['provider'], {'require_parameters': true});
    });

    test(
      'named eval never sends json_schema even if tools would 404',
      () async {
        final payloads = <Map<String, dynamic>>[];
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'fallback-model',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          payloads.add(body);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'report_relationship',
                          'arguments':
                              '{"relationship_delta":5,"trust_delta":1}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        });

        final resp = await remote.generateStructuredJson(named, tools);
        expect(payloads, hasLength(1));
        expect(payloads.single.containsKey('response_format'), isFalse);
        expect(payloads.single['tools'], isNotEmpty);
        expect(resp!.calls.single.arguments['relationship_delta'], 5);
      },
    );

    test(
      'Nano-GPT tools door still sends the thinking-off reasoning block',
      () async {
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://nano-gpt.com/api/v1',
          apiKey: 'test-key',
          modelName: 'same-model',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'report_relationship',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        });

        await remote.generateWithTools(
          const GenerationParams(
            prompt: 'score',
            maxLength: 512,
            reasoningEnabled: false,
            reasoningMaxTokens: 0,
            salvageReasoning: true,
            toolChoice: 'report_relationship',
          ),
          tools,
        );
        expect(payload!['reasoning'], {'enabled': false, 'max_tokens': 0});
        expect(payload!.containsKey('provider'), isFalse);
        expect(payload!['tools'], isNotEmpty);
      },
    );

    test(
      'OpenRouter tools door strips reasoning so require_parameters can route',
      () async {
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'x-ai/grok-4',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'tool_calls': [
                      {
                        'function': {
                          'name': 'report_relationship',
                          'arguments': '{}',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        });

        await remote.generateWithTools(
          const GenerationParams(
            prompt: 'journal or fallback',
            maxLength: 4000,
            reasoningEnabled: false,
            reasoningMaxTokens: 0,
            salvageReasoning: true,
          ),
          tools,
        );
        expect(payload!.containsKey('reasoning'), isFalse);
        expect(payload!['provider'], {'require_parameters': true});
        expect(payload!['tools'], isNotEmpty);
      },
    );

    test(
      'empty tool_calls is one POST — no json_schema then tools fallback',
      () async {
        var posts = 0;
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'thinker',
        );
        remote.httpClientFactory = () => MockClient((request) async {
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
        });

        final resp = await remote.generateStructuredJson(named, tools);
        expect(posts, 1);
        expect(resp!.calls, isEmpty);
        expect(resp.finishReason, 'tool_calls');
      },
    );
  });

  group('OpenRouterService.generateWithTools streaming', () {
    const tools = [
      {
        'type': 'function',
        'function': {
          'name': 'report_relationship',
          'parameters': {
            'type': 'object',
            'properties': {
              'relationship_delta': {'type': 'integer'},
            },
          },
        },
      },
    ];

    const sseOk =
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"report_relationship","arguments":"{}"}}]}}]}\n\n'
        'data: [DONE]\n';

    GenerationParams liveJudge() => GenerationParams(
      prompt: 'score this',
      maxLength: 512,
      temperature: 0.1,
      minP: 0.05,
      topK: 40,
      repeatPenalty: 1.15,
      toolChoice: 'report_relationship',
      salvageReasoning: true,
      reasoningEnabled: false,
      reasoningMaxTokens: 0,
      onChunk: (_) {},
    );

    setUp(() {
      ToolChoiceStyleProbe.instance.resetForTest();
      OpenRouterToolSupport.instance.resetForTest();
    });

    test(
      'OpenRouter stream forces the named tool, require_parameters, and no OR-hostile samplers',
      () async {
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'x-ai/grok-4',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(sseOk, 200);
        });

        await remote.generateWithTools(liveJudge(), tools);
        expect(payload!['stream'], isTrue);
        expect(payload!['tool_choice'], {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        });
        expect(payload!['provider'], {'require_parameters': true});
        expect(payload!.containsKey('min_p'), isFalse);
        expect(payload!.containsKey('top_k'), isFalse);
        expect(payload!.containsKey('repetition_penalty'), isFalse);
        expect(payload!['max_tokens'], kOpenRouterStructuredEvalMinTokens);
      },
    );

    test(
      'Nano-GPT stream keeps named tool_choice, samplers, and no provider pin',
      () async {
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://nano-gpt.com/api/v1',
          apiKey: 'test-key',
          modelName: 'same-model',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(sseOk, 200);
        });

        await remote.generateWithTools(liveJudge(), tools);
        expect(payload!['stream'], isTrue);
        expect(payload!['tool_choice'], {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        });
        expect(payload!.containsKey('provider'), isFalse);
        expect(payload!['min_p'], 0.05);
        expect(payload!['top_k'], 40);
        expect(payload!['repetition_penalty'], 1.15);
        expect(payload!['max_tokens'], 512);
      },
    );

    test(
      'OpenRouter stream raises the think-headroom floor on mandatory models',
      () async {
        kMandatoryReasoningModels.add('stream-think-test');
        addTearDown(
          () => kMandatoryReasoningModels.remove('stream-think-test'),
        );
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'stream-think-test',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(sseOk, 200);
        });

        await remote.generateWithTools(liveJudge(), tools);
        expect(
          payload!['max_tokens'],
          kOpenRouterStructuredEvalMinTokens +
              kMandatoryReasoningThinkHeadroomTokens,
        );
        expect(payload!['provider'], {'require_parameters': true});
        expect(payload!['tool_choice'], {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        });
      },
    );

    test(
      'OpenRouter named eval stream sends nested tools, not json_schema',
      () async {
        Map<String, dynamic>? payload;
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'x-ai/grok-4',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          payload = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(sseOk, 200);
        });

        final resp = await remote.generateStructuredJson(liveJudge(), tools);
        expect(payload!['stream'], isTrue);
        expect(payload!.containsKey('response_format'), isFalse);
        expect(payload!['tools'], isNotEmpty);
        expect(payload!['tool_choice'], {
          'type': 'function',
          'function': {'name': 'report_relationship'},
        });
        expect(payload!['provider'], {'require_parameters': true});
        expect(resp!.calls.single.name, 'report_relationship');
      },
    );
  });

  group('tool_choice probe must not persist auto for named judges', () {
    const tools = [
      {
        'type': 'function',
        'function': {
          'name': 'report_relationship',
          'parameters': {
            'type': 'object',
            'properties': {
              'relationship_delta': {'type': 'integer'},
            },
          },
        },
      },
    ];

    const sseOk =
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"report_relationship","arguments":"{}"}}]}}]}\n\n'
        'data: [DONE]\n';

    const toolChoice400 = '{"error":{"message":"unknown tool_choice value"}}';
    const postOk =
        '{"choices":[{"message":{"tool_calls":[{"function":{"name":"report_relationship","arguments":"{}"}}]}}]}';

    final isForcedToolChoice = anyOf('required', {
      'type': 'function',
      'function': {'name': 'report_relationship'},
    });

    GenerationParams named({void Function(String)? onChunk}) =>
        GenerationParams(
          prompt: 'score this',
          maxLength: 512,
          minP: 0.05,
          topK: 40,
          repeatPenalty: 1.15,
          toolChoice: 'report_relationship',
          salvageReasoning: true,
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
          onChunk: onChunk,
        );

    http.Response replyFor(Map<String, dynamic> body, {required bool stream}) {
      if (body['tool_choice'] == 'auto') {
        return http.Response(stream ? sseOk : postOk, 200);
      }
      return http.Response(toolChoice400, 400);
    }

    setUp(() {
      ToolChoiceStyleProbe.instance.resetForTest();
      OpenRouterToolSupport.instance.resetForTest();
    });

    test('OpenRouter stream tool_choice 400 never steps to auto', () async {
      final payloads = <Map<String, dynamic>>[];
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'sticky-auto-stream',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        payloads.add(body);
        return replyFor(body, stream: true);
      });

      await remote.generateWithTools(named(onChunk: (_) {}), tools);
      expect(payloads, hasLength(1));
      expect(payloads.single['tool_choice'], isForcedToolChoice);
      expect(payloads.single['tool_choice'], isNot('auto'));

      await remote.generateWithTools(named(onChunk: (_) {}), tools);
      expect(payloads, hasLength(2));
      expect(payloads.last['tool_choice'], isForcedToolChoice);
      expect(payloads.last['provider'], {'require_parameters': true});
    });

    test('OpenRouter POST tool_choice 400 never steps to auto', () async {
      final payloads = <Map<String, dynamic>>[];
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'sticky-auto-post',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        payloads.add(body);
        return replyFor(body, stream: false);
      });

      await remote.generateWithTools(named(), tools);
      expect(payloads, hasLength(1));
      expect(payloads.single['tool_choice'], isForcedToolChoice);

      await remote.generateWithTools(named(), tools);
      expect(payloads.last['tool_choice'], isForcedToolChoice);
      expect(payloads.last['tool_choice'], isNot('auto'));
    });

    test(
      'Journal empty toolChoice still sends auto after a named 400',
      () async {
        final payloads = <Map<String, dynamic>>[];
        final remote = OpenRouterService(
          apiUrl: 'https://openrouter.ai/api/v1',
          apiKey: 'test-key',
          modelName: 'sticky-auto-journal',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          payloads.add(body);
          return replyFor(body, stream: true);
        });

        await remote.generateWithTools(named(onChunk: (_) {}), tools);
        payloads.clear();
        await remote.generateWithTools(
          GenerationParams(prompt: 'journal', maxLength: 4000, onChunk: (_) {}),
          tools,
        );
        expect(payloads, isNotEmpty);
        expect(payloads.first['tool_choice'], 'auto');
      },
    );

    test(
      'Nano stream after a tool_choice 400 still has no provider pin',
      () async {
        final payloads = <Map<String, dynamic>>[];
        final remote = OpenRouterService(
          apiUrl: 'https://nano-gpt.com/api/v1',
          apiKey: 'test-key',
          modelName: 'sticky-auto-nano',
        );
        remote.httpClientFactory = () => MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          payloads.add(body);
          return replyFor(body, stream: true);
        });

        await remote.generateWithTools(named(onChunk: (_) {}), tools);
        final afterFirst = payloads.length;
        await remote.generateWithTools(named(onChunk: (_) {}), tools);
        expect(payloads[afterFirst]['tool_choice'], isForcedToolChoice);
        expect(payloads[afterFirst].containsKey('provider'), isFalse);
        expect(payloads[afterFirst]['min_p'], 0.05);
      },
    );
  });

  group('eval door call site', () {
    test('named judges go through generateStructuredJson and keep overlay', () {
      final wiring = File(
        'lib/services/chat/chat_service_wiring_evals.dart',
      ).readAsStringSync();
      expect(wiring, contains('service is OpenRouterService'));
      expect(wiring, contains('generateStructuredJson'));
      expect(wiring, contains('onChunk: spec.onChunk'));
      expect(wiring, isNot(contains('onChunk: named ? null')));
      expect(
        wiring,
        contains('named || spec.maxLength > kScalarToolMaxTokens'),
      );
    });
  });
}
