// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Local think-off against templates that `{% set enable_thinking = true %}`
// (heretic / uncensored Gemma-4 forks). enable_thinking:false is overwritten
// at render; oMLX / llama.cpp honour thinking_budget: 0 as a force-close.
// Stock templates that already honour the kwarg must NOT receive the field.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);
  setUp(clearReasoningEffortCatalog);
  tearDown(clearReasoningEffortCatalog);

  group('thinkingBudgetClampForThinkOff', () {
    test('null when thinking is on, even for a hard-on model', () {
      rememberHardOnThinking('heretic-gemma');
      expect(
        thinkingBudgetClampForThinkOff('heretic-gemma', thinkOn: true),
        isNull,
      );
    });

    test('0 when the app asked think-off AND the template hard-sets it', () {
      rememberHardOnThinking('heretic-gemma');
      expect(
        thinkingBudgetClampForThinkOff('heretic-gemma', thinkOn: false),
        0,
      );
    });

    test('null on a stock model so Gemma-4 does not get a closer leak', () {
      expect(
        thinkingBudgetClampForThinkOff('gemma-4-31b-it', thinkOn: false),
        isNull,
      );
    });
  });

  group('wire payload (OpenRouterService local OpenAI-compat)', () {
    late HttpServer server;
    Map<String, dynamic>? lastRequest;

    setUp(() async {
      lastRequest = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        lastRequest =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write('data: [DONE]\n');
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    const tools = [
      {
        'type': 'function',
        'function': {'name': 'noop'},
      },
    ];

    test(
      'hard-on + think off → thinking_budget 0 next to enable_thinking false',
      () async {
        rememberHardOnThinking('heretic-gemma');
        final svc = OpenRouterService(
          apiUrl: 'http://127.0.0.1:${server.port}/v1',
          modelName: 'heretic-gemma',
        );
        await svc.generateWithTools(
          const GenerationParams(
            prompt: '1: YES or NO',
            reasoningEnabled: false,
            reasoningMaxTokens: 0,
          ),
          tools,
        );
        final r = lastRequest!;
        expect(r['chat_template_kwargs'], {'enable_thinking': false});
        expect(r['thinking_budget'], 0);
      },
    );

    test(
      'Continue-shaped params (think-off, not an eval) still send thinking_budget 0',
      () async {
        rememberHardOnThinking('heretic-gemma');
        final svc = OpenRouterService(
          apiUrl: 'http://127.0.0.1:${server.port}/v1',
          modelName: 'heretic-gemma',
        );
        await svc.generateWithTools(
          const GenerationParams(
            prompt: 'she kept talking',
            reasoningEnabled: false,
            reasoningMaxTokens: 0,
          ),
          tools,
        );
        expect(lastRequest!['thinking_budget'], 0);
        expect(lastRequest!['chat_template_kwargs'], {
          'enable_thinking': false,
        });
      },
    );

    test('Request-thinking-on reply does not send thinking_budget', () async {
      rememberHardOnThinking('heretic-gemma');
      final svc = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'heretic-gemma',
      );
      await svc.generateWithTools(
        const GenerationParams(prompt: 'hi', reasoningEnabled: true),
        tools,
      );
      expect(lastRequest!.containsKey('thinking_budget'), isFalse);
      expect(lastRequest!['chat_template_kwargs'], {'enable_thinking': true});
    });

    test('stock local think off does not send thinking_budget', () async {
      final svc = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'gemma-4-31b-it',
      );
      await svc.generateWithTools(
        const GenerationParams(
          prompt: 'hi',
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
        ),
        tools,
      );
      final r = lastRequest!;
      expect(r['chat_template_kwargs'], {'enable_thinking': false});
      expect(r.containsKey('thinking_budget'), isFalse);
    });

    test('LAN LM Studio / llama.cpp is local; cloud OpenRouter is not', () {
      // The old contains('localhost') gate left LAN servers on the
      // OpenRouter reasoning object they ignore.
      expect(isLocalRemoteUrl('http://192.168.1.10:1234/v1'), isTrue);
      expect(isLocalRemoteUrl('http://10.0.0.5:8080/v1'), isTrue);
      expect(isLocalRemoteUrl('http://host.local:1234/v1'), isTrue);
      expect(isLocalRemoteUrl('https://openrouter.ai/api/v1'), isFalse);
    });
  });

  group('wire payload (Kobold / llama.cpp via streamOpenAiChat)', () {
    late HttpServer server;
    Map<String, dynamic>? lastRequest;

    setUp(() async {
      lastRequest = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        lastRequest =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write('data: [DONE]\n');
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('GGUF path hard-on + think off → thinking_budget 0', () async {
      const path = '/models/heretic-gemma.gguf';
      rememberHardOnThinking(path);
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        const GenerationParams(
          prompt: 'hi',
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
        ),
        thinkingModelKey: path,
      ).drain<void>();
      expect(lastRequest!['chat_template_kwargs'], {'enable_thinking': false});
      expect(lastRequest!['thinking_budget'], 0);
      expect(lastRequest!['reasoning_effort'], 'none');
    });

    test('stock GGUF think off does not send thinking_budget', () async {
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        const GenerationParams(
          prompt: 'hi',
          reasoningEnabled: false,
          reasoningMaxTokens: 0,
        ),
        thinkingModelKey: '/models/plain.gguf',
      ).drain<void>();
      expect(lastRequest!['chat_template_kwargs'], {'enable_thinking': false});
      expect(lastRequest!.containsKey('thinking_budget'), isFalse);
    });
  });
}
