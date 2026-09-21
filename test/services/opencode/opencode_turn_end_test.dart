// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// OpenCode 1.18.30 halt() publishes session.error then idle. The pump
/// must wait for idle and must not throw abort as a Dart error.
void main() {
  test('MessageAbortedError is parsed, not Map.toString, and not spoken', () {
    const raw =
        'data: {"type":"session.error","properties":{"sessionID":"ses_1","error":{"name":"MessageAbortedError","data":{"message":"Aborted"}}}}\n'
        '\n'
        'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n'
        '\n';
    final events = parseOpenCodeSse(raw);
    expect(events, hasLength(2));
    final err = events[0] as OpenCodeErrorEvent;
    expect(err.aborted, isTrue);
    expect(err.name, 'MessageAbortedError');
    expect(err.message, 'Aborted');
    expect(err.message, isNot(contains('{')));
    final sink = _Sink();
    dispatchOpenCodeEvent(err, sink);
    expect(sink.errors, isEmpty);
    dispatchOpenCodeEvent(events[1], sink);
    expect(sink.idle, isTrue);
  });

  test('legacy Map.toString abort dump still counts as abort', () {
    expect(
      openCodeErrorIsAbort(
        name: '',
        message: '{name: MessageAbortedError, data: {message: Aborted}}',
      ),
      isTrue,
    );
  });

  test('non-abort session.error still reaches the sink', () {
    const raw =
        'data: {"type":"session.error","properties":{"sessionID":"ses_1","error":{"name":"APIError","data":{"message":"HTTP 400"}}}}\n'
        '\n';
    final events = parseOpenCodeSse(raw);
    final err = events.single as OpenCodeErrorEvent;
    expect(err.aborted, isFalse);
    expect(err.message, 'HTTP 400');
    final sink = _Sink();
    dispatchOpenCodeEvent(err, sink);
    expect(sink.errors, ['HTTP 400']);
  });

  test('promptAndPump completes on idle after abort, and does not throw', () async {
    final sink = _Sink();
    final client = OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: '/tmp/porch',
      clientFactory: () => MockClient.streaming((req, body) async {
        if (req.url.path == '/event') {
          final chunk = utf8.encode(
            'data: {"type":"session.error","properties":{"sessionID":"ses_1","error":{"name":"MessageAbortedError","data":{"message":"Aborted"}}}}\n'
            '\n'
            'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n'
            '\n',
          );
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([chunk]),
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
    await client.promptAndPump(
      sessionId: 'ses_1',
      parts: [
        {'type': 'text', 'text': 'hi'},
      ],
      sink: sink,
    );
    expect(sink.errors, isEmpty);
    expect(sink.idle, isTrue);
  });

  test(
    'promptAndPump waits for voice wrap-up idle, not the first coding idle',
    () async {
      final sink = _Sink();
      final client = OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: '/tmp/porch',
        clientFactory: () => MockClient.streaming((req, body) async {
          if (req.url.path == '/event') {
            final controller = StreamController<List<int>>();
            unawaited(() async {
              controller.add(
                utf8.encode(
                  'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n'
                  '\n'
                  'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n'
                  '\n',
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 50));
              controller.add(
                utf8.encode(
                  'data: {"type":"message.part.delta","properties":{"sessionID":"ses_1","field":"text","delta":"Hmph. Listed the folder."}}\n'
                  '\n'
                  'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n'
                  '\n',
                ),
              );
              await controller.close();
            }());
            return http.StreamedResponse(
              controller.stream,
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
      await client.promptAndPump(
        sessionId: 'ses_1',
        parts: [
          {'type': 'text', 'text': 'hi'},
        ],
        sink: sink,
      );
      expect(sink.deltas.join(), 'Hmph. Listed the folder.');
      expect(sink.idle, isTrue);
    },
  );
}

class _Sink implements OpenCodeEventSink {
  final errors = <String>[];
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
  void onError(String message) => errors.add(message);

  @override
  void onTokens({required int promptTokens, required int outputTokens}) {}
}
