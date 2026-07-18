// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the OpenAI tool-calling doors (phase 4 of the Journal):
// - llm_tool_parsing.dart — response-body → LlmToolResponse (pure)
// - OpenRouterService.generateWithTools (remote door) and
//   postOpenAiChatWithTools (the shared LOCAL door KoboldService
//   delegates to) — request shape +
//   null-on-failure contract, exercised against a real loopback HTTP
//   server (same pattern as the Stoop relay tests).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_tool_parsing.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';

void main() {
  // The test binding stubs HttpClient (every request would 400 without a
  // network call) — clear the override so the loopback server is reachable
  // (same escape the Stoop relay tests use).
  setUpAll(() => HttpOverrides.global = null);

  group('parseOpenAiToolResponse', () {
    test('parses tool_calls with JSON-string and map arguments', () {
      final body = jsonEncode({
        'choices': [
          {
            'message': {
              'content': 'noted.',
              'tool_calls': [
                {
                  'function': {
                    'name': 'add_memory',
                    'arguments': '{"content": "He was kind.", "msgs": [2]}',
                  },
                },
                {
                  'function': {
                    'name': 'write_recap',
                    'arguments': {'text': 'All is well.'}, // map variant
                  },
                },
              ],
            },
          },
        ],
      });
      final resp = parseOpenAiToolResponse(body)!;
      expect(resp.calls, hasLength(2));
      expect(resp.calls[0].name, 'add_memory');
      expect(resp.calls[0].arguments['content'], 'He was kind.');
      expect(resp.calls[1].arguments['text'], 'All is well.');
      expect(resp.text, 'noted.');
    });

    test('malformed arguments become {} and garbage bodies become null', () {
      final resp = parseOpenAiToolResponse(
        jsonEncode({
          'choices': [
            {
              'message': {
                'tool_calls': [
                  {
                    'function': {'name': 'add_memory', 'arguments': '{broken'},
                  },
                  {
                    'function': {'name': '', 'arguments': '{}'}, // nameless
                  },
                ],
              },
            },
          ],
        }),
      )!;
      expect(resp.calls.single.name, 'add_memory');
      expect(resp.calls.single.arguments, isEmpty);
      expect(resp.text, '');

      expect(parseOpenAiToolResponse('not json at all'), isNull);
      expect(parseOpenAiToolResponse(jsonEncode({'choices': []})), isNull);
    });
  });

  group('OpenRouterService.generateWithTools', () {
    late HttpServer server;
    Map<String, dynamic>? lastRequest;
    int statusCode = 200;
    String responseBody = '';

    setUp(() async {
      lastRequest = null;
      statusCode = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        lastRequest =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        req.response.statusCode = statusCode;
        req.response.headers.contentType = ContentType.json;
        req.response.write(responseBody);
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    OpenRouterService service() => OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}/v1',
      modelName: 'test-model', // local URL → no API key required
    );

    final params = GenerationParams(
      prompt: 'update your journal',
      maxLength: 4000,
      temperature: 0.1,
      reasoningEnabled: false,
    );
    const tools = [
      {
        'type': 'function',
        'function': {'name': 'add_memory'},
      },
    ];

    test('sends a non-streaming request with tools and parses the calls',
        () async {
      responseBody = jsonEncode({
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'function': {
                    'name': 'add_memory',
                    'arguments': '{"content": "It rained all night."}',
                  },
                },
              ],
            },
          },
        ],
      });

      final resp = await service().generateWithTools(params, tools);

      expect(lastRequest!['stream'], false);
      expect(lastRequest!['tools'], isNotEmpty);
      expect(lastRequest!['tool_choice'], 'auto');
      expect(lastRequest!['model'], 'test-model');
      // Same reasoning posture as the streaming eval path: with reasoning
      // off and no budget, the shared payload builder omits the key.
      expect(lastRequest!.containsKey('reasoning'), isFalse);
      expect(resp!.calls.single.name, 'add_memory');
      expect(resp.calls.single.arguments['content'], 'It rained all night.');
    });

    test('non-200 (provider without tool support) returns null', () async {
      statusCode = 404;
      responseBody = jsonEncode({
        'error': {'message': 'No endpoints found that support tool use'},
      });
      expect(await service().generateWithTools(params, tools), isNull);
    });

    test('unready service returns null without making a request', () async {
      final unready = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: '', // no model → not ready
      );
      expect(await unready.generateWithTools(params, tools), isNull);
      expect(lastRequest, isNull);
    });

    test('local door (postOpenAiChatWithTools) — same shape, same contract',
        () async {
      // The shared function KoboldService delegates to,
      // pointed at the KoboldCpp-style root (no /v1 — the helper appends).
      responseBody = jsonEncode({
        'choices': [
          {
            'message': {
              'tool_calls': [
                {
                  'function': {
                    'name': 'pin_memory',
                    'arguments': '{"id": 2}',
                  },
                },
              ],
            },
          },
        ],
      });
      final resp = await postOpenAiChatWithTools(
        'http://127.0.0.1:${server.port}',
        params,
        tools,
      );
      expect(lastRequest!['stream'], false);
      expect(lastRequest!['tools'], isNotEmpty);
      expect(lastRequest!['tool_choice'], 'auto');
      expect(lastRequest!['model'], 'koboldcpp'); // Kobold ignores the name
      expect(resp!.calls.single.name, 'pin_memory');
      expect(resp.calls.single.arguments['id'], 2);

      // An old KoboldCpp that rejects the tools field → null → XML fallback.
      statusCode = 400;
      responseBody = '';
      expect(
        await postOpenAiChatWithTools(
          'http://127.0.0.1:${server.port}',
          params,
          tools,
        ),
        isNull,
      );
    });
  });
}
