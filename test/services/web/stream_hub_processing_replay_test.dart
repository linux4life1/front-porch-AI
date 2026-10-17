// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

// A web client that connects while a goal check is already running (a page
// reload, a phone waking) must still get the evaluation overlay.
void main() {
  late StreamController<String> tokens;
  late StreamHub hub;
  late dynamic server; // HttpServer

  setUp(() async {
    tokens = StreamController<String>.broadcast();
    hub = StreamHub(tokens.stream, () => false);
    server = await shelf_io.serve(
      webSocketHandler((WebSocketChannel ch, String? _) => hub.register(ch)),
      'localhost',
      0,
    );
  });

  tearDown(() async {
    await hub.dispose();
    await tokens.close();
    await server.close(force: true);
  });

  Future<List<Map<String, dynamic>>> connectAndCollect() async {
    final client = WebSocketChannel.connect(
      Uri.parse('ws://localhost:${server.port}/api/ws'),
    );
    await client.ready;
    final events = <Map<String, dynamic>>[];
    client.stream.listen(
      (msg) => events.add(jsonDecode(msg as String) as Map<String, dynamic>),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.sink.close();
    return events;
  }

  const checking = {
    'event': 'processing',
    'active': true,
    'realism': false,
    'objective': true,
    'greeting': false,
    'verifying': false,
    'text': '',
  };

  test(
    'a socket opened mid-check is sent the active processing frame',
    () async {
      hub.broadcastProcessing(Map<String, dynamic>.of(checking));
      final events = await connectAndCollect();
      expect(events.map((e) => e['event']), ['connected', 'processing']);
      expect(events[1], checking);
    },
  );

  test('a socket opened after the check ended gets no stale overlay', () async {
    hub.broadcastProcessing(Map<String, dynamic>.of(checking));
    hub.broadcastProcessing({'event': 'processing', 'active': false});
    final events = await connectAndCollect();
    expect(events.map((e) => e['event']), ['connected']);
  });
}
