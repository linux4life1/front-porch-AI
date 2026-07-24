// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the OpenAI tool-calling doors (phase 4 of the Journal):
// - llm_tool_parsing.dart — response-body → LlmToolResponse (pure)
// - OpenRouterService.generateWithTools (remote door) and
//   postOpenAiChatWithTools (the shared LOCAL door KoboldService
//   delegates to) — request shape + the transport contract (null = the
//   server answered but the call yielded nothing usable; THROW = transport
//   failure, classified by isToolTransportFailure), exercised against a
//   real loopback HTTP server (same pattern as the Stoop relay tests).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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

    test('429/5xx throws a transport failure — never a capability null',
        () async {
      statusCode = 503;
      responseBody = jsonEncode({
        'error': {'message': 'Server is busy; please try again later.'},
      });
      Object? caught;
      try {
        await service().generateWithTools(params, tools);
        fail('a busy server must throw, not return null');
      } catch (e) {
        caught = e;
      }
      expect(isToolTransportFailure(caught), isTrue);

      // Same contract on the shared local door.
      statusCode = 429;
      try {
        await postOpenAiChatWithTools(
          'http://127.0.0.1:${server.port}',
          params,
          tools,
        );
        fail('a rate-limited server must throw, not return null');
      } catch (e) {
        caught = e;
      }
      expect(isToolTransportFailure(caught), isTrue);
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

    test('client torn down mid-call (abortGeneration) throws a transport '
        'failure', () async {
      // A server that accepts the request and never answers — the call stays
      // in flight until the client is torn down, exactly what an app-side
      // abortGeneration (e.g. character creation clearing stuck state) does
      // to the registered _activeClient during a background pass's tool call.
      final stall = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final release = Completer<void>();
      stall.listen((req) async {
        await release.future; // hold the response open
        req.response.statusCode = 200;
        await req.response.close();
      });
      http.Client? registered;
      final call = postOpenAiChatWithTools(
        'http://127.0.0.1:${stall.port}',
        params,
        tools,
        registerClient: (c) => registered = c,
      );
      await Future.delayed(const Duration(milliseconds: 200));
      registered!.close(); // the abort
      Object? caught;
      try {
        await call;
        fail('a torn-down client must throw, not return a capability null');
      } catch (e) {
        caught = e;
      }
      expect(isToolTransportFailure(caught), isTrue);
      release.complete();
      await stall.close(force: true);
    });
  });
}
