// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

void main() {
  group('StreamHub (WebSocket fan-out)', () {
    late StreamController<String> tokens;
    late StreamHub hub;
    late dynamic server; // HttpServer
    late int port;

    setUp(() async {
      tokens = StreamController<String>.broadcast();
      hub = StreamHub(tokens.stream, () => false);
      final handler = webSocketHandler(
        (WebSocketChannel ch) => hub.register(ch),
      );
      server = await shelf_io.serve(handler, 'localhost', 0);
      port = server.port as int;
    });

    tearDown(() async {
      await hub.dispose();
      await tokens.close();
      await server.close(force: true);
    });

    test('sends a connected event then relays tokens and done', () async {
      final client =
          WebSocketChannel.connect(Uri.parse('ws://localhost:$port/api/ws'));
      await client.ready;

      final events = <Map<String, dynamic>>[];
      final got = Completer<void>();
      client.stream.listen((msg) {
        events.add(jsonDecode(msg as String) as Map<String, dynamic>);
        if (events.length >= 3) got.complete();
      });

      // Give the server a tick to register + send 'connected'.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tokens.add('Hello');
      tokens.add('__DONE__');

      await got.future.timeout(const Duration(seconds: 5));
      expect(events[0]['event'], 'connected');
      expect(events[1], {'event': 'token', 'data': 'Hello'});
      expect(events[2]['event'], 'done');

      await client.sink.close();
    });

    test('__ERROR__ sentinel becomes an error event', () async {
      final client =
          WebSocketChannel.connect(Uri.parse('ws://localhost:$port/api/ws'));
      await client.ready;
      final got = Completer<Map<String, dynamic>>();
      client.stream.listen((msg) {
        final e = jsonDecode(msg as String) as Map<String, dynamic>;
        if (e['event'] == 'error') got.complete(e);
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      tokens.add('__ERROR__');
      final e = await got.future.timeout(const Duration(seconds: 5));
      expect(e['event'], 'error');
      await client.sink.close();
    });
  });
}
