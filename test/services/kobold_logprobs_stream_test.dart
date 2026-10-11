// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The KoboldCpp chat transport for token alternatives, end to end against a
// loopback SSE server (same pattern as reasoning_stream_test.dart):
//   * a reply that wants word odds asks for them, and one that does not,
//     does not;
//   * the extra final chunk KoboldCpp streams with ALL the logprobs (shape
//     from koboldcpp.py: an empty assistant delta plus `logprobs.content`)
//     reaches the caller without changing the text;
//   * a rewrite's trailing assistant message is sent as the last message,
//     which KoboldCpp continues, and on a model with no system role the
//     system text rides the user message instead of being dropped.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/openai_chat_stream.dart';

void main() {
  late HttpServer server;
  late Map<String, dynamic> lastBody;
  const sse =
      'data: {"choices":[{"index":0,"finish_reason":null,"delta":{"content":"She sat"}}]}\n'
      'data: {"choices":[{"index":0,"finish_reason":"stop","delta":{"content":" down."}}]}\n'
      'data: {"choices":[{"index":0,"finish_reason":null,"delta":{"role":"assistant","content":""},'
      '"logprobs":{"content":[{"token":"She","logprob":-0.1,"top_logprobs":[]},'
      '{"token":" sat","logprob":-0.9,"top_logprobs":[{"token":" sat","logprob":-0.9},{"token":" knelt","logprob":-1.2}]},'
      '{"token":" down.","logprob":-0.05,"top_logprobs":[]}]}}]}\n'
      'data: [DONE]\n';

  setUp(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      lastBody = jsonDecode(await utf8.decoder.bind(req).join());
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write(sse);
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<String> run(GenerationParams p, {bool fold = false}) async =>
      (await streamOpenAiChat(
        'http://127.0.0.1:${server.port}',
        p,
        foldSystemIntoUser: fold,
      ).toList()).join();

  test('asks for word odds and hands back the final chunk', () async {
    final got = <Object?>[];
    final text = await run(
      GenerationParams(prompt: 'q', onLogprobs: got.addAll),
    );

    expect(text, 'She sat down.');
    expect(lastBody['logprobs'], isTrue);
    expect(lastBody['top_logprobs'], kTopLogprobs);
    expect(got, hasLength(3));
    expect((got[1]! as Map)['token'], ' sat');
  });

  test('a reply that does not want odds does not ask for them', () async {
    await run(const GenerationParams(prompt: 'q'));
    expect(lastBody.containsKey('logprobs'), isFalse);
    expect(lastBody.containsKey('top_logprobs'), isFalse);
  });

  test('a rewrite ends with the assistant text KoboldCpp continues', () async {
    await run(
      const GenerationParams(
        prompt: 'the chat so far',
        systemPrompt: 'You are Nia.',
        chatMessages: [
          {'role': 'user', 'content': 'the chat so far'},
          {'role': 'assistant', 'content': 'She knelt'},
        ],
      ),
    );
    final messages = (lastBody['messages'] as List).cast<Map>();
    expect(messages.map((m) => m['role']), ['system', 'user', 'assistant']);
    expect(messages.last['content'], 'She knelt');
  });

  test('no system role: the system text rides the user message', () async {
    await run(
      const GenerationParams(
        prompt: 'the chat so far',
        systemPrompt: 'You are Nia.',
        chatMessages: [
          {'role': 'user', 'content': 'the chat so far'},
          {'role': 'assistant', 'content': 'She knelt'},
        ],
      ),
      fold: true,
    );
    final messages = (lastBody['messages'] as List).cast<Map>();
    expect(messages.map((m) => m['role']), ['user', 'assistant']);
    expect(messages.first['content'], contains('You are Nia.'));
    expect(messages.first['content'], contains('the chat so far'));
  });
}
