// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Two transport guards for OpenRouterService, both against a real loopback
// server (same pattern as open_router_tools_test.dart):
//
// 1. /models answering with a PLAIN STRING list — the shape the parser's
//    `m is String` branch exists for — must produce models, not an empty
//    picker. Reading `m['pricing']` on a String threw and aborted the loop.
// 2. abortGeneration() (Cancel / cancelRealismEval) must reach EVERY call in
//    flight. This service is one shared instance and the app overlaps calls on
//    it (staggered realism judges, post-gen needs + reply-facts), so a single
//    "active client" slot meant the first call to finish disarmed Cancel for
//    all the others, which then streamed on (and kept billing).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding stubs HttpClient — clear it so loopback is reachable.
  setUpAll(() => HttpOverrides.global = null);

  test('a plain-string /models list still fills the picker', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      // The LM-Studio-ish shape: names only, no pricing, no maps at all.
      req.response.write(
        jsonEncode({
          'models': ['llama-3', 'qwen3'],
        }),
      );
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final service = OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}/v1',
      modelName: 'llama-3', // local URL → no API key required
    );

    final models = await service.fetchAvailableModels();
    expect(models.map((m) => m.id), ['llama-3', 'qwen3']);
    expect(models.first.name, 'llama-3');
    expect(models.first.promptCostPerMillion, isNull);
  });

  test('abortGeneration cancels a stream that another call outlived', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var seen = 0;
    server.listen((req) async {
      await req.drain<void>();
      req.response.headers.contentType = ContentType('text', 'event-stream');
      seen++;
      if (seen == 1) {
        // The long call: headers only, then silence until the client is torn
        // down (a reasoning model that has not emitted a first token yet).
        req.response.write(': open\n\n');
        await req.response.flush();
        return; // deliberately never closed
      }
      // The short call: one chunk and done, so its teardown runs first.
      req.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'hi'},
            },
          ],
        })}\n\n',
      );
      req.response.write('data: [DONE]\n\n');
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final service = OpenRouterService(
      apiUrl: 'http://127.0.0.1:${server.port}/v1',
      modelName: 'test-model',
    );
    const params = GenerationParams(
      prompt: 'judge this turn',
      maxLength: 64,
      temperature: 0.1,
      reasoningEnabled: false,
    );

    final longCallDone = Completer<void>();
    final sub = service
        .generateStream(params)
        .listen(
          (_) {},
          onError: (_) {
            if (!longCallDone.isCompleted) longCallDone.complete();
          },
          onDone: () {
            if (!longCallDone.isCompleted) longCallDone.complete();
          },
        );
    addTearDown(sub.cancel);

    // Let the long call reach the server and register itself.
    while (seen < 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // A second, overlapping call that finishes normally.
    expect(await service.generateStream(params).join(), 'hi');

    service.abortGeneration();

    await longCallDone.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail(
        'Cancel did not reach the in-flight call — it was disarmed by the '
        'overlapping call that finished first',
      ),
    );
  });

  test('abortGeneration from another zone cuts a call still connecting '
      'without an uncaught error in the caller\'s zone', () async {
    // The connect never finishes on its own, so the abort lands mid-connect:
    // the background tool-support ping a chat switch cut at the end of a
    // macOS E2E suite, which then failed after it had passed.
    final service = OpenRouterService(
      apiUrl: 'http://127.0.0.1:9/v1',
      modelName: 'test-model',
    );
    service.httpClientFactory = () => IOClient(
      HttpClient()
        ..connectionFactory = (uri, proxyHost, proxyPort) {
          final socket = Completer<Socket>();
          return Future.value(
            ConnectionTask.fromSocket(
              socket.future,
              () => socket.completeError(
                const SocketException('Connection attempt cancelled'),
              ),
            ),
          );
        },
    );
    const params = GenerationParams(
      prompt: 'Call the report_ping tool.',
      maxLength: 16,
      temperature: 0.1,
      reasoningEnabled: false,
      toolChoice: 'report_ping',
    );

    final uncaught = <Object>[];
    final caught = Completer<Object?>();
    runZonedGuarded(() {
      service
          .generateWithTools(params, const [
            {
              'type': 'function',
              'function': {'name': 'report_ping', 'parameters': {}},
            },
          ])
          .then((_) => caught.complete(null), onError: caught.complete);
    }, (e, _) => uncaught.add(e));

    // Let the call reach its connect before the abort.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    service.abortGeneration();

    final error = await caught.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the abort did not end the connecting call'),
    );
    expect(error, isNotNull, reason: 'the cut call must fail to its caller');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      uncaught,
      isEmpty,
      reason:
          'the cancelled connect escaped as uncaught in the zone that '
          'opened the call, though that call caught it',
    );
  });
}
