// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proof tests for the KoboldCpp channel-thinking fix. Two layers:
//  1. ReasoningTagWrapper — the pure state machine that re-wraps a split
//     reasoning stream (separate reasoning_content deltas) back into the inline
//     <think>…</think> framing the app's bubble + web UI parse.
//  2. streamOpenAiChat end-to-end against a loopback SSE server (same pattern as
//     vision_payload_test.dart): reasoning_content deltas must surface as a
//     <think>…</think> block when reasoning is on, and be DISCARDED (never
//     leaked into the reply) when reasoning is off or hard-suppressed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';
import 'package:front_porch_ai/services/reasoning_stream_wrapper.dart';

void main() {
  group('ReasoningTagWrapper', () {
    test('wrap:true opens <think> once, closes on first content', () {
      final w = ReasoningTagWrapper(wrap: true);
      expect(w.onReasoning('abc'), '<think>abc');
      expect(w.onReasoning('def'), 'def'); // no second <think>
      expect(w.onContent('answer'), '</think>\nanswer');
      expect(w.onContent(' more'), ' more'); // block already closed
      expect(w.finish(), ''); // nothing left to close
    });

    test('wrap:true reasoning-only response is closed by finish()', () {
      final w = ReasoningTagWrapper(wrap: true);
      expect(w.onReasoning('just thinking'), '<think>just thinking');
      expect(w.finish(), '</think>\n');
      expect(w.finish(), ''); // idempotent, no double close
    });

    test('wrap:false discards reasoning, passes content through', () {
      final w = ReasoningTagWrapper(wrap: false);
      expect(w.onReasoning('secret thoughts'), '');
      expect(w.onContent('answer'), 'answer');
      expect(w.finish(), '');
    });

    test('empty deltas yield nothing and do not open a block', () {
      final w = ReasoningTagWrapper(wrap: true);
      expect(w.onReasoning(''), '');
      expect(w.onContent(''), '');
      expect(w.finish(), ''); // never opened, nothing to close
    });

    test('late/interleaved reasoning re-opens a block, never leaks as content',
        () {
      final w = ReasoningTagWrapper(wrap: true);
      expect(w.onReasoning('r1'), '<think>r1');
      expect(w.onContent('answer'), '</think>\nanswer');
      // reasoning AFTER content must not spill into the visible reply
      expect(w.onReasoning('r2'), '<think>r2');
      expect(w.finish(), '</think>\n');
    });
  });

  group('streamOpenAiChat reasoning framing (loopback SSE)', () {
    late HttpServer server;
    late String sseBody;

    setUp(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await utf8.decoder.bind(req).join(); // drain request
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('text', 'event-stream');
        req.response.write(sseBody);
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    // reasoning_content deltas, then the clean answer, then [DONE] — exactly the
    // shape jinja-mode KoboldCpp returns for a channel-format reasoning model.
    const reasoningThenAnswer =
        'data: {"choices":[{"delta":{"reasoning_content":"step one "}}]}\n'
        'data: {"choices":[{"delta":{"reasoning_content":"step two"}}]}\n'
        'data: {"choices":[{"delta":{"content":"The answer is 5."}}]}\n'
        'data: [DONE]\n';

    Future<String> run(GenerationParams params) async {
      final parts = await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        params,
      ).toList();
      return parts.join();
    }

    test('reasoning ON → reasoning_content becomes a <think> block', () async {
      sseBody = reasoningThenAnswer;
      final out = await run(GenerationParams(
        prompt: 'q',
        reasoningEnabled: true,
        reasoningEffort: 'high',
      ));
      expect(out, '<think>step one step two</think>\nThe answer is 5.');
    });

    test('reasoning OFF → reasoning_content is discarded, not leaked', () async {
      sseBody = reasoningThenAnswer;
      final out = await run(GenerationParams(
        prompt: 'q',
        reasoningEnabled: false,
      ));
      expect(out, 'The answer is 5.'); // no <think>, no reasoning text
    });

    test('suppress signal (reasoningMaxTokens:0) discards reasoning', () async {
      sseBody = reasoningThenAnswer;
      final out = await run(GenerationParams(
        prompt: 'q',
        reasoningEnabled: true,
        reasoningMaxTokens: 0, // Continue/eval hard-suppress
      ));
      expect(out, 'The answer is 5.');
    });

    test('reasoning-only response closes the block at stream end', () async {
      sseBody =
          'data: {"choices":[{"delta":{"reasoning_content":"lonely thought"}}]}\n'
          'data: [DONE]\n';
      final out = await run(GenerationParams(
        prompt: 'q',
        reasoningEnabled: true,
      ));
      expect(out, '<think>lonely thought</think>\n');
    });
  });
}
