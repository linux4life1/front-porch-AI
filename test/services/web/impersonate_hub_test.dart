// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Web Impersonate: tokens must NOT ride the AI-bubble `token` event, and a
// burst of accumulated snapshots must coalesce to the LATEST draft (replace,
// not append). New file — test-integrity blocks edits to existing tests.
//
// Proven red: broadcast as `token` → first test fails; concatenate
// snapshots → second test's data is "ababc".

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

void main() {
  group('StreamHub impersonate coalescing', () {
    late StreamController<String> tokens;
    late StreamHub hub;
    late dynamic server;
    late int port;

    setUp(() async {
      tokens = StreamController<String>.broadcast();
      hub = StreamHub(tokens.stream, () => false);
      final handler = webSocketHandler(
        (WebSocketChannel ch, String? _) => hub.register(ch),
      );
      server = await shelf_io.serve(handler, 'localhost', 0);
      port = server.port as int;
    });

    tearDown(() async {
      await hub.dispose();
      await tokens.close();
      await server.close(force: true);
    });

    Future<(List<Map<String, dynamic>>, WebSocketChannel)> connect() async {
      final client = WebSocketChannel.connect(
        Uri.parse('ws://localhost:$port/api/ws'),
      );
      await client.ready;
      final events = <Map<String, dynamic>>[];
      client.stream.listen(
        (msg) => events.add(jsonDecode(msg as String) as Map<String, dynamic>),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (events, client);
    }

    test('a burst of snapshots is one replace-frame, then done', () async {
      final (events, client) = await connect();

      hub.broadcastImpersonate('I walk');
      hub.broadcastImpersonate('I walk toward');
      hub.broadcastImpersonate('I walk toward the rail');
      hub.broadcastImpersonateDone();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final fills = events.where((e) => e['event'] == 'impersonate').toList();
      expect(fills, hasLength(1));
      expect(fills.single['data'], 'I walk toward the rail');
      expect(
        events.where((e) => e['event'] == 'token'),
        isEmpty,
        reason: 'impersonate must not paint an AI bubble',
      );
      final order = events.map((e) => e['event']).toList();
      expect(
        order.indexOf('impersonate'),
        lessThan(order.indexOf('impersonate_done')),
      );
      await client.sink.close();
    });
  });
}
