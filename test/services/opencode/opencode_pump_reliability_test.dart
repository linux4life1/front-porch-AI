// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A turn must end: a dead serve, a lost wrap-up or a stalled voice pass
/// may not leave Waifu Coder "running" forever, and speech split across
/// network chunks must arrive whole.
void main() {
  const idle =
      'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n\n';
  String delta(String text) =>
      'data: ${jsonEncode({
        'type': 'message.part.delta',
        'properties': {'sessionID': 'ses_1', 'field': 'text', 'delta': text},
      })}\n\n';

  OpenCodeClient clientFor(
    Stream<List<int>> Function() events, {
    Duration voiceSettle = const Duration(seconds: 90),
  }) {
    return OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: '/tmp/porch',
      voiceSettle: voiceSettle,
      clientFactory: () => MockClient.streaming((req, body) async {
        if (req.url.path == '/event') {
          return http.StreamedResponse(
            events(),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (req.url.path.endsWith('/prompt_async')) {
          return http.StreamedResponse(const Stream.empty(), 204);
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      }),
    );
  }

  Future<void> pump(OpenCodeClient client, _Sink sink) {
    return client.promptAndPump(
      sessionId: 'ses_1',
      parts: [
        {'type': 'text', 'text': 'hi'},
      ],
      sink: sink,
    );
  }

  test(
    'a character split across two chunks still reaches the bubble',
    () async {
      const speech = 'Hmph ✨ ありがとう (｡•̀ᴗ-)✧';
      final bytes = utf8.encode(idle + delta(speech) + idle);
      // Cut inside the first multi-byte character of the speech.
      final cut = bytes.indexOf(0xE2) + 1;
      final sink = _Sink();
      await pump(
        clientFor(
          () =>
              Stream.fromIterable([bytes.sublist(0, cut), bytes.sublist(cut)]),
        ),
        sink,
      );
      expect(sink.deltas.join(), speech);
      expect(sink.idle, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    'the serve dropping the stream mid-coding ends the turn with an error',
    () async {
      final sink = _Sink();
      final run = pump(
        clientFor(() => Stream.value(utf8.encode(delta('Reading…')))),
        sink,
      );
      await expectLater(run, throwsA(isA<OpenCodeStreamClosed>()));
      expect(
        const OpenCodeStreamClosed().toString(),
        isNot(contains('Bad state')),
      );
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test('the stream closing after coding idle ends the turn normally', () async {
    final sink = _Sink();
    await pump(clientFor(() => Stream.value(utf8.encode(idle))), sink);
    expect(sink.idle, isTrue);
  }, timeout: const Timeout(Duration(seconds: 5)));

  test(
    'a voice pass that stalls without idle ends after the settle window',
    () async {
      final sink = _Sink();
      final events = StreamController<List<int>>();
      addTearDown(events.close);
      final watch = Stopwatch()..start();
      final run = pump(
        clientFor(
          () => events.stream,
          voiceSettle: const Duration(milliseconds: 300),
        ),
        sink,
      );
      events.add(utf8.encode(idle));
      // Voice keeps talking: each event pushes the window out.
      for (final word in ['Done', ' — ', 'tests pass']) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        events.add(utf8.encode(delta(word)));
      }
      await run;
      expect(sink.deltas.join(), 'Done — tests pass');
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(450));
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );
}

class _Sink implements OpenCodeEventSink {
  final deltas = <String>[];
  var idle = false;

  @override
  void onTextDelta(
    String delta, {
    String messageId = '',
    bool thinking = false,
  }) => deltas.add(delta);

  @override
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
    String callId = '',
  }) {}

  @override
  void onPermissionAsk(OpenCodePermissionAsked ask) {}

  @override
  void onTodo(List<OpenCodeTodoItem> todos) {}

  @override
  void onIdle() => idle = true;

  @override
  void onError(String message) {}

  @override
  void onTokens({required int promptTokens, required int outputTokens}) {}
}
