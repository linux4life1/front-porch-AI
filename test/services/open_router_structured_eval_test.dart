// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OpenRouter named evals must use response_format json_schema. PR #230
// kept forced tool_choice; providers that advertise tools still return
// empty tool_calls after a think, and require_parameters + reasoning
// routed only to those endpoints.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openrouter_structured_eval.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

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

  group('openRouterEvalJsonSchema', () {
    test('named judge uses that tool even when the list has three', () {
      final schema = openRouterEvalJsonSchema(
        tools: kJudgeEvalTools,
        toolChoice: kRelationshipTool,
      )!;
      expect(schema['name'], kRelationshipTool);
      expect(schema['strict'], isTrue);
      final body = schema['schema'] as Map;
      expect(body['additionalProperties'], isFalse);
      expect(
        body['required'],
        containsAll(['relationship_delta', 'trust_delta']),
      );
      expect((body['properties'] as Map).containsKey('emotion'), isFalse);
    });

    test('Journal-style auto choice does not mint a schema', () {
      expect(
        openRouterEvalJsonSchema(
          tools: kRelationshipEvalTools,
          toolChoice: null,
        ),
        isNull,
      );
      expect(
        openRouterEvalJsonSchema(tools: kRelationshipEvalTools, toolChoice: ''),
        isNull,
      );
    });
  });

  group('applyOpenRouterStructuredEvalRouting', () {
    test(
      'drops tools, samplers, and reasoning so only json_schema is required',
      () {
        final payload = applyOpenRouterStructuredEvalRouting(
          {
            'max_tokens': 512,
            'tools': const [],
            'tool_choice': {
              'type': 'function',
              'function': {'name': kRelationshipTool},
            },
            'reasoning': {'enabled': false, 'exclude': true},
            'repetition_penalty': 1.15,
            'min_p': 0.05,
            'top_k': 40,
          },
          jsonSchema: openRouterEvalJsonSchema(
            tools: kRelationshipEvalTools,
            toolChoice: kRelationshipTool,
          )!,
          mandatoryReasoning: false,
        );
        expect(payload.containsKey('tools'), isFalse);
        expect(payload.containsKey('tool_choice'), isFalse);
        expect(payload.containsKey('reasoning'), isFalse);
        expect(payload.containsKey('min_p'), isFalse);
        expect(payload['provider'], {'require_parameters': true});
        expect(payload['max_tokens'], kOpenRouterStructuredEvalMinTokens);
        expect(payload['response_format']['type'], 'json_schema');
      },
    );

    test('mandatory thinking adds the same headroom the text evals use', () {
      final payload = applyOpenRouterStructuredEvalRouting(
        {'max_tokens': 512},
        jsonSchema: const {
          'name': 'n',
          'strict': true,
          'schema': {'type': 'object'},
        },
        mandatoryReasoning: true,
      );
      expect(
        payload['max_tokens'],
        kOpenRouterStructuredEvalMinTokens +
            kMandatoryReasoningThinkHeadroomTokens,
      );
    });
  });

  group('toolResponseFromStructuredEvalContent', () {
    test('empty content with JSON in reasoning is a usable call', () {
      final resp = toolResponseFromStructuredEvalContent(
        content: '\n',
        reasoning:
            'draft 99 then {"relationship_delta":3,"trust_delta":1,"bond_reason":"none","trust_reason":"none"}',
        toolName: kRelationshipTool,
      )!;
      expect(resp.calls.single.name, kRelationshipTool);
      expect(resp.calls.single.arguments['relationship_delta'], 3);
      expect(resp.calls.single.arguments['trust_delta'], 1);
    });

    test('prose without a JSON object is not a success', () {
      expect(
        toolResponseFromStructuredEvalContent(
          content: 'bond went up a bit',
          reasoning: '',
          toolName: kRelationshipTool,
        ),
        isNull,
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

    test('OpenRouter named eval sends json_schema, not tools', () async {
      Map<String, dynamic>? payload;
      var toolPosts = 0;
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'x-ai/grok-4',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        if (payload!.containsKey('tools')) toolPosts++;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"relationship_delta":4,"trust_delta":2,"bond_reason":"none","trust_reason":"none"}',
                },
              },
            ],
          }),
          200,
        );
      });

      final resp = await remote.generateStructuredJson(named, tools);
      expect(toolPosts, 0);
      expect(payload!['response_format']['type'], 'json_schema');
      expect(payload!.containsKey('tools'), isFalse);
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

    test('schema 404 falls through to the existing tools door', () async {
      final payloads = <Map<String, dynamic>>[];
      final remote = OpenRouterService(
        apiUrl: 'https://openrouter.ai/api/v1',
        apiKey: 'test-key',
        modelName: 'fallback-model',
      );
      remote.httpClientFactory = () => MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        payloads.add(body);
        if (body.containsKey('response_format')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message': 'No endpoints found that support structured outputs',
              },
            }),
            404,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'tool_calls': [
                    {
                      'function': {
                        'name': 'report_relationship',
                        'arguments': '{"relationship_delta":5,"trust_delta":1}',
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
      expect(payloads, hasLength(2));
      expect(payloads.first.containsKey('response_format'), isTrue);
      expect(payloads.last['tools'], isNotEmpty);
      expect(resp!.calls.single.arguments['relationship_delta'], 5);
    });

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
      'empty content + reasoning JSON does not take the tools fallback',
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
                  'finish_reason': 'length',
                  'message': {
                    'content': '',
                    'reasoning': '{"relationship_delta":7,"trust_delta":0}',
                  },
                },
              ],
            }),
            200,
          );
        });

        final resp = await remote.generateStructuredJson(named, tools);
        expect(posts, 1);
        expect(resp!.calls.single.arguments['relationship_delta'], 7);
      },
    );
  });

  group('eval door call site', () {
    test(
      'named judges go through generateStructuredJson on a buffered POST',
      () {
        final wiring = File(
          'lib/services/chat/chat_service_wiring_evals.dart',
        ).readAsStringSync();
        expect(wiring, contains('generateStructuredJson('));
        expect(wiring, contains('onChunk: named ? null : spec.onChunk'));
        expect(
          wiring,
          contains('named || spec.maxLength > kScalarToolMaxTokens'),
        );
      },
    );
  });
}
