// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proof tests for sampler DELIVERY — the fix for "changing samplers has no
// effect": every slider must actually appear in the HTTP request body.
// - Local (KoboldCpp/pseudo-remote via streamOpenAiChat): native fields
//   min_p / rep_pen / rep_pen_range / top_k / xtc_* / dynatemp_range /
//   dry_* / banned_tokens, and NO lossy frequency_penalty conversion.
// - Remote (OpenRouterService): repetition_penalty + min_p + top_k for
//   OpenRouter-compatible providers; the conservative legacy payload only
//   for strict api.openai.com URLs.
// Exercised against a real loopback HTTP server (Stoop-test pattern).

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

  group('local payload (streamOpenAiChat → KoboldCpp)', () {
    test('delivers the native sampler set; no fake frequency_penalty',
        () async {
      final params = GenerationParams(
        prompt: 'hello',
        maxLength: 512,
        temperature: 0.85,
        topP: 0.95,
        minP: 0.07,
        topK: 60,
        repeatPenalty: 1.25,
        repPenTokens: 256,
        xtcThreshold: 0.12,
        xtcProbability: 0.4,
        dynatempRange: 0.5,
        dryMultiplier: 0.8,
        bannedPhrases: const ['shivers down'],
      );
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final r = lastRequest!;
      expect(r['temperature'], 0.85);
      expect(r['top_p'], 0.95);
      expect(r['min_p'], 0.07);
      expect(r['top_k'], 60);
      expect(r['rep_pen'], 1.25);
      expect(r['rep_pen_range'], 256);
      expect(r['xtc_threshold'], 0.12);
      expect(r['xtc_probability'], 0.4);
      expect(r['dynatemp_range'], 0.5);
      expect(r['dry_multiplier'], 0.8);
      expect(r['dry_sequence_breakers'], isNotEmpty);
      expect(r['banned_tokens'], ['shivers down']);
      // The lossy conversion is gone — rep_pen rides natively instead.
      expect(r.containsKey('frequency_penalty'), isFalse);
    });

    test('neutral knobs stay out of the payload (0 = off)', () async {
      final params = GenerationParams(prompt: 'hello');
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).drain<void>();

      final r = lastRequest!;
      expect(r.containsKey('top_k'), isFalse); // 0 = disabled
      expect(r.containsKey('dry_multiplier'), isFalse);
      expect(r.containsKey('dynatemp_range'), isFalse);
      expect(r.containsKey('banned_tokens'), isFalse);
      expect(r['xtc_probability'], 0.0); // default OFF now that it arrives
    });
  });

  group('remote payload (OpenRouterService)', () {
    final params = GenerationParams(
      prompt: 'hello',
      temperature: 0.8,
      topP: 0.92,
      minP: 0.05,
      topK: 40,
      repeatPenalty: 1.2,
    );
    const tools = [
      {
        'type': 'function',
        'function': {'name': 'noop'},
      },
    ];

    test('OpenRouter-compatible providers get native repetition_penalty, '
        'min_p, top_k', () async {
      final service = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'test-model',
      );
      // generateWithTools shares _chatPayload with the streaming path —
      // easiest non-streaming capture (its null return on the fake SSE body
      // is irrelevant here; the request body is the test subject).
      await service.generateWithTools(params, tools);

      final r = lastRequest!;
      expect(r['top_p'], 0.92);
      expect(r['min_p'], 0.05);
      expect(r['top_k'], 40);
      expect(r['repetition_penalty'], 1.2);
      expect(r.containsKey('frequency_penalty'), isFalse);
    });

    test('strict api.openai.com URLs keep the conservative legacy payload',
        () async {
      // The guard is a URL substring check; pointing the path at the
      // loopback server keeps the request capturable.
      final service = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/openai.com/v1',
        apiKey: 'k',
        modelName: 'gpt-x',
      );
      await service.generateWithTools(params, tools);

      final r = lastRequest!;
      expect(r['frequency_penalty'], closeTo(0.2, 1e-9)); // 1.2 → 0.2
      expect(r.containsKey('repetition_penalty'), isFalse);
      expect(r.containsKey('min_p'), isFalse);
      expect(r.containsKey('top_k'), isFalse);
    });
  });
}
