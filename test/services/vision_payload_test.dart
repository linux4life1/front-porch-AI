// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proof tests for the Vision QC payload widening — the single highest-risk
// edit of the phase: BOTH chat-payload builders (streamOpenAiChat for
// KoboldCpp/pseudo-remote, OpenRouterService for every remote provider) feed
// EVERY chat generation and eval in the app.
// - No images (null OR empty) → the user message content must stay a plain
//   String and the messages array must deep-equal the pre-change shape.
// - Images present → OpenAI multimodal content array: text part first, then
//   one image_url part per image with a data: PNG URI; the system message
//   and sampler/reasoning fields are untouched.
// Exercised against a real loopback HTTP server (same pattern as
// sampler_payload_test.dart) so the assertions cover the actual wire JSON.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';

void main() {
  setUpAll(() => HttpOverrides.global = null);

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
      req.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      // A single terminating SSE frame satisfies the streaming parser; the
      // tools path tolerates the non-JSON body by returning null.
      req.response.write('data: [DONE]\n');
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  const twoImages = ['QUFB', 'QkJC'];
  const expectedMultimodalContent = [
    {'type': 'text', 'text': 'look at this'},
    {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,QUFB'},
    },
    {
      'type': 'image_url',
      'image_url': {'url': 'data:image/png;base64,QkJC'},
    },
  ];

  group('local payload (streamOpenAiChat → KoboldCpp/pseudo-remote)', () {
    test('no images → messages deep-equal the legacy string-content shape',
        () async {
      final params = GenerationParams(
        prompt: 'hello',
        systemPrompt: 'be brief',
      );
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final messages = lastRequest!['messages'] as List;
      expect(messages, [
        {'role': 'system', 'content': 'be brief'},
        {'role': 'user', 'content': 'hello'},
      ]);
      // The load-bearing detail: content is a plain String, not an array.
      expect((messages[1] as Map)['content'], isA<String>());
    });

    test('EMPTY images list behaves exactly like null (string content)',
        () async {
      final params = GenerationParams(prompt: 'hello', images: const []);
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final messages = lastRequest!['messages'] as List;
      expect(messages, [
        {'role': 'user', 'content': 'hello'},
      ]);
    });

    test('two images → multimodal array; system + samplers untouched',
        () async {
      final params = GenerationParams(
        prompt: 'look at this',
        systemPrompt: 'be brief',
        temperature: 0.85,
        repeatPenalty: 1.25,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        images: twoImages,
      );
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final r = lastRequest!;
      final messages = r['messages'] as List;
      expect(messages, hasLength(2));
      expect(messages[0], {'role': 'system', 'content': 'be brief'});
      expect((messages[1] as Map)['role'], 'user');
      expect((messages[1] as Map)['content'], expectedMultimodalContent);
      // Sampler + reasoning fields ride exactly as before.
      expect(r['temperature'], 0.85);
      expect(r['rep_pen'], 1.25);
      // Local (KoboldCpp) reasoning uses Kobold-native fields, NOT the
      // OpenRouter `reasoning` object (which Kobold ignores). reasoningMaxTokens
      // == 0 is the "suppress thinking" signal (Continue / evals).
      expect(r.containsKey('reasoning'), isFalse);
      expect(r['chat_template_kwargs'], {'enable_thinking': false});
      expect(r['reasoning_effort'], 'none');
    });

    test('reasoning OFF authoritatively disables thinking (not just omitted)',
        () async {
      // reasoningEnabled false, no suppress signal (maxTokens null): the toggle
      // must still force thinking OFF so a thinking-model launch default can't
      // keep thinking on despite the toggle.
      final params = GenerationParams(prompt: 'hi', systemPrompt: 'be brief');
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();
      final r = lastRequest!;
      expect(r.containsKey('reasoning'), isFalse);
      expect(r['chat_template_kwargs'], {'enable_thinking': false});
      expect(r['reasoning_effort'], 'none');
      expect(r.containsKey('encapsulate_thinking'), isFalse);
    });

    test('reasoning enabled → Kobold-native thinking fields', () async {
      final params = GenerationParams(
        prompt: 'think about this',
        systemPrompt: 'be brief',
        reasoningEnabled: true,
        reasoningEffort: 'high',
      );
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final r = lastRequest!;
      expect(r.containsKey('reasoning'), isFalse); // no OpenRouter object
      expect(r['chat_template_kwargs'], {'enable_thinking': true});
      expect(r['reasoning_effort'], 'high');
      // No encapsulate_thinking: in --jinja mode Kobold returns reasoning in the
      // standard reasoning_content field (which streamOpenAiChat now consumes),
      // so we no longer force thinking to stay inline in `content`.
      expect(r.containsKey('encapsulate_thinking'), isFalse);
    });
  });

  group('remote payload (OpenRouterService)', () {
    // generateWithTools shares _chatPayload with the streaming path (see
    // sampler_payload_test.dart) — easiest non-streaming capture; its null
    // return on the fake SSE body is irrelevant here.
    const tools = [
      {
        'type': 'function',
        'function': {'name': 'noop'},
      },
    ];

    OpenRouterService service() => OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}/v1',
      modelName: 'test-model', // local URL → no API key required
    );

    test('no images → messages deep-equal the legacy string-content shape',
        () async {
      final params = GenerationParams(
        prompt: 'hello',
        systemPrompt: 'be brief',
      );
      await service().generateWithTools(params, tools);

      final messages = lastRequest!['messages'] as List;
      expect(messages, [
        {'role': 'system', 'content': 'be brief'},
        {'role': 'user', 'content': 'hello'},
      ]);
      expect((messages[1] as Map)['content'], isA<String>());
    });

    test('EMPTY images list behaves exactly like null (string content)',
        () async {
      final params = GenerationParams(prompt: 'hello', images: const []);
      await service().generateWithTools(params, tools);

      final messages = lastRequest!['messages'] as List;
      expect(messages, [
        {'role': 'user', 'content': 'hello'},
      ]);
    });

    test('two images → multimodal array; system + samplers untouched',
        () async {
      final params = GenerationParams(
        prompt: 'look at this',
        systemPrompt: 'be brief',
        temperature: 0.85,
        repeatPenalty: 1.25,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        images: twoImages,
      );
      await service().generateWithTools(params, tools);

      final r = lastRequest!;
      final messages = r['messages'] as List;
      expect(messages, hasLength(2));
      expect(messages[0], {'role': 'system', 'content': 'be brief'});
      expect((messages[1] as Map)['role'], 'user');
      expect((messages[1] as Map)['content'], expectedMultimodalContent);
      expect(r['temperature'], 0.85);
      expect(r['repetition_penalty'], 1.25);
      expect(r['reasoning'], {
        'enabled': false,
        'max_tokens': 0,
        'exclude': true,
      });
    });
  });
}
