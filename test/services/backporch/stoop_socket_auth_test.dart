// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';

void main() {
  late HttpServer server;
  final sockets = <WebSocket>[];
  late Completer<Uri> requestUri;
  late Completer<Map<String, dynamic>> firstFrame;

  setUp(() async {
    requestUri = Completer<Uri>();
    firstFrame = Completer<Map<String, dynamic>>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/ws' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        requestUri.complete(request.uri);
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        final frame = await socket.first;
        firstFrame.complete(
          jsonDecode(frame as String) as Map<String, dynamic>,
        );
        socket.add(jsonEncode({'type': 'ready'}));
        return;
      }
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"count":0}');
      await request.response.close();
    });
    BackporchApi.overrideBaseUrl =
        'http://${server.address.address}:${server.port}';
  });

  tearDown(() async {
    BackporchApi.overrideBaseUrl = null;
    for (final socket in sockets) {
      await socket.close();
    }
    sockets.clear();
    await server.close(force: true);
  });

  test('desktop authenticates in the first frame, never the URL', () async {
    const token = 'header.payload.signature+/=?';
    final client = StoopMessageSocket(() => token);
    addTearDown(client.dispose);

    final uri = await requestUri.future.timeout(const Duration(seconds: 3));
    expect(uri.path, '/ws');
    expect(
      uri.query,
      isEmpty,
      reason: 'access tokens must never appear in WebSocket request URLs',
    );
    expect(await firstFrame.future.timeout(const Duration(seconds: 3)), {
      'type': 'auth',
      'token': token,
    });
  });
}
