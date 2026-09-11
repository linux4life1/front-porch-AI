// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('SSE parser yields text delta then idle', () {
    const raw =
        'data: {"type":"message.part.delta","properties":{"sessionID":"ses_1","messageID":"msg_1","partID":"prt_1","field":"text","delta":"Hi"}}\n'
        '\n'
        'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n'
        '\n';
    final events = parseOpenCodeSse(raw);
    expect(events, hasLength(2));
    expect(events[0], isA<OpenCodeTextDelta>());
    expect((events[0] as OpenCodeTextDelta).delta, 'Hi');
    expect(events[1], isA<OpenCodeSessionIdle>());
    expect((events[1] as OpenCodeSessionIdle).sessionId, 'ses_1');
  });

  test('SSE parser maps tool and permission events', () {
    const raw =
        'data: {"type":"message.part.updated","properties":{"sessionID":"ses_1","time":1,"part":{"type":"tool","tool":"write","callID":"c1","state":{"status":"completed","output":"ok"}}}}\n'
        '\n'
        'data: {"type":"permission.asked","properties":{"id":"per_1","sessionID":"ses_1","permission":"edit","patterns":["src/a.dart"],"metadata":{},"always":[]}}\n'
        '\n';
    final events = parseOpenCodeSse(raw);
    expect(events[0], isA<OpenCodeToolEvent>());
    final tool = events[0] as OpenCodeToolEvent;
    expect(tool.name, 'write');
    expect(tool.ok, isTrue);
    expect(events[1], isA<OpenCodePermissionAsked>());
    expect((events[1] as OpenCodePermissionAsked).permissionId, 'per_1');
  });

  test('health hits GET /global/health', () async {
    final hits = <http.Request>[];
    final client = OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      clientFactory: () => MockClient((req) async {
        hits.add(req);
        return http.Response('{"healthy":true,"version":"1.18.30"}', 200);
      }),
    );
    final health = await client.health();
    expect(health.healthy, isTrue);
    expect(health.version, '1.18.30');
    expect(hits.single.method, 'GET');
    expect(hits.single.url.path, '/global/health');
  });

  test('createSession posts directory query and title', () async {
    final hits = <http.Request>[];
    final client = OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: '/tmp/porch',
      clientFactory: () => MockClient((req) async {
        hits.add(req);
        return http.Response(
          '{"id":"ses_abc","title":"Count","directory":"/tmp/porch"}',
          200,
        );
      }),
    );
    final session = await client.createSession(title: 'Count', agent: 'waifu');
    expect(session.id, 'ses_abc');
    expect(hits.single.method, 'POST');
    expect(hits.single.url.path, '/session');
    expect(hits.single.url.queryParameters['directory'], '/tmp/porch');
    final body = jsonDecode(hits.single.body) as Map;
    expect(body['title'], 'Count');
    expect(body['agent'], 'waifu');
  });

  test('promptAsync sends text parts and does not wait', () async {
    final hits = <http.Request>[];
    final client = OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: '/tmp/porch',
      clientFactory: () => MockClient((req) async {
        hits.add(req);
        return http.Response('', 204);
      }),
    );
    await client.promptAsync(
      sessionId: 'ses_abc',
      parts: [
        {'type': 'text', 'text': 'count the files'},
      ],
      agent: 'waifu',
    );
    expect(hits.single.method, 'POST');
    expect(hits.single.url.path, '/session/ses_abc/prompt_async');
    final body = jsonDecode(hits.single.body) as Map;
    expect(body['agent'], 'waifu');
    expect(body['parts'][0]['text'], 'count the files');
  });

  test(
    'promptAndPump streams assistant text into a dumb sink until idle',
    () async {
      final sink = _RecordingSink();
      final client = OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: '/tmp/porch',
        clientFactory: () => MockClient.streaming((req, body) async {
          if (req.url.path == '/event') {
            final chunk = utf8.encode(
              'data: {"type":"message.part.delta","properties":{"sessionID":"ses_1","messageID":"msg_1","partID":"prt_1","field":"text","delta":"Hmph."}}\n'
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
      expect(sink.deltas.join(), 'Hmph.');
      expect(sink.idle, isTrue);
    },
  );
}

class _RecordingSink implements OpenCodeEventSink {
  final deltas = <String>[];
  var idle = false;

  @override
  void onTextDelta(String delta) => deltas.add(delta);

  @override
  void onTool({
    required String name,
    required String detail,
    required bool ok,
    bool pending = false,
  }) {}

  @override
  void onPermissionAsk(OpenCodePermissionAsked ask) {}

  @override
  void onTodo(List<OpenCodeTodoItem> todos) {}

  @override
  void onIdle() => idle = true;

  @override
  void onError(String message) {}
}
