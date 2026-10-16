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

import 'package:front_porch_ai/services/llm_provider/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router/open_router.dart';
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

  group('oMLX payload (Repeat Penalty Tokens + DRY Strength)', () {
    // oMLX's repetition penalty looks back 20 tokens unless told otherwise,
    // and it has no DRY, so both sliders were dead there: a local model
    // copied a whole earlier paragraph thirty times in one reply. The
    // builder now sends oMLX's own fields — and only to oMLX.
    final params = GenerationParams(
      prompt: 'hello',
      repeatPenalty: 1.1,
      repPenTokens: 1024,
      dryMultiplier: 0.8,
    );

    test('the oMLX address gets the look-back and the repeat block', () {
      final r = OpenRouterService(
        apiUrl: kOmlxApiUrl,
        modelName: 'mlx-model',
      ).chatRequestPayload(params);
      expect(r['repetition_penalty'], 1.1);
      expect(r['repetition_context_size'], 1024);
      expect(r['no_repeat_ngram_size'], 20);
    });

    test('DRY off sends no repeat block; stronger DRY allows shorter runs', () {
      final off = OpenRouterService(
        apiUrl: '$kOmlxApiUrl/',
        modelName: 'mlx-model',
      ).chatRequestPayload(GenerationParams(prompt: 'hello'));
      expect(off.containsKey('no_repeat_ngram_size'), isFalse);
      expect(omlxNoRepeatNgramSize(2.0), kOmlxNoRepeatNgramMin);
      expect(omlxNoRepeatNgramSize(0.1), kOmlxNoRepeatNgramMax);
    });

    test('every other host keeps the payload it had', () {
      final r = OpenRouterService(
        apiUrl: 'http://127.0.0.1:${server.port}/v1',
        modelName: 'test-model',
      ).chatRequestPayload(params);
      expect(r.containsKey('repetition_context_size'), isFalse);
      expect(r.containsKey('no_repeat_ngram_size'), isFalse);
      expect(r['repetition_penalty'], 1.1);
    });
  });

  group('the sampler table matches the wire', () {
    // Settings shows a generation setting only where samplerKnobsFor says the
    // backend's requests carry it. Here every knob is turned on and each
    // real payload builder is read: a knob the table lists that the wire
    // drops is a dead slider, and one the wire sends that the table hides is
    // a setting the user cannot reach.
    final everythingOn = GenerationParams(
      prompt: 'hello',
      minP: 0.05,
      topK: 40,
      repeatPenalty: 1.2,
      repPenTokens: 512,
      xtcThreshold: 0.1,
      xtcProbability: 0.5,
      dryMultiplier: 0.8,
      dynatempRange: 0.5,
      bannedPhrases: const ['shivers down'],
    );
    const wireKeys = {
      SamplerKnob.minP: ['min_p'],
      SamplerKnob.topK: ['top_k'],
      SamplerKnob.repeatPenalty: [
        'rep_pen',
        'repetition_penalty',
        'frequency_penalty',
      ],
      SamplerKnob.repeatPenaltyTokens: [
        'rep_pen_range',
        'repetition_context_size',
      ],
      SamplerKnob.xtc: ['xtc_probability'],
      SamplerKnob.dry: ['dry_multiplier', 'no_repeat_ngram_size'],
      SamplerKnob.dynamicTemp: ['dynatemp_range'],
      SamplerKnob.bannedPhrases: ['banned_tokens'],
    };
    Set<SamplerKnob> onTheWire(Map<String, dynamic> body) => {
      for (final MapEntry(key: knob, value: keys) in wireKeys.entries)
        if (keys.any(body.containsKey)) knob,
    };

    test('KoboldCpp', () async {
      await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        everythingOn,
      ).drain<void>();
      expect(
        onTheWire(lastRequest!),
        samplerKnobsFor(BackendType.kobold, remoteApiUrl: ''),
      );
    });

    for (final (host, backend, url) in [
      ('oMLX', BackendType.omlx, kOmlxApiUrl),
      ('a remote API', BackendType.openRouter, 'https://openrouter.ai/api/v1'),
      ('api.openai.com', BackendType.openRouter, 'https://api.openai.com/v1'),
      ('xAI', BackendType.openRouter, 'https://api.x.ai/v1'),
    ]) {
      test(host, () {
        final body = OpenRouterService(
          apiUrl: url,
          apiKey: 'k',
          modelName: 'm',
        ).chatRequestPayload(everythingOn);
        expect(
          onTheWire(body),
          samplerKnobsFor(
            backend,
            remoteApiUrl: backend == BackendType.omlx ? '' : url,
          ),
        );
      });
    }
  });
}
