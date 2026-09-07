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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HttpServer upstream;
  late HttpServer relay;
  late AppDatabase db;
  final upstreamSockets = <WebSocket>[];
  late Completer<Uri> upstreamUri;
  late Completer<Map<String, dynamic>> firstUpstreamFrame;
  late Completer<Map<String, dynamic>> secondUpstreamFrame;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fpai_stoop_relay_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);
    SharedPreferences.setMockInitialValues({});

    upstreamUri = Completer<Uri>();
    firstUpstreamFrame = Completer<Map<String, dynamic>>();
    secondUpstreamFrame = Completer<Map<String, dynamic>>();
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path != '/ws' ||
          !WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      upstreamUri.complete(request.uri);
      final socket = await WebSocketTransformer.upgrade(request);
      upstreamSockets.add(socket);
      await for (final raw in socket) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (!firstUpstreamFrame.isCompleted) {
          firstUpstreamFrame.complete(frame);
          if (socket.readyState == WebSocket.open) {
            socket.add(jsonEncode({'type': 'ready', 'thread': 'thread-7'}));
          }
        } else {
          secondUpstreamFrame.complete(frame);
          break;
        }
      }
    });

    db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final facade = StoopFacade(
      storage,
      db,
      api: BackporchApi(
        baseUrl: 'http://${upstream.address.address}:${upstream.port}',
      ),
    );
    final router = Router();
    WebStoopRoutes(facade, router);
    relay = await shelf_io.serve(router.call, InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await relay.close(force: true);
    for (final socket in upstreamSockets) {
      await socket.close();
    }
    upstreamSockets.clear();
    await upstream.close(force: true);
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test(
    'relay authenticates upstream in frame one without a token URL',
    () async {
      const token = 'relay.header.payload+/=?';
      final browser = await WebSocket.connect(
        'ws://${relay.address.address}:${relay.port}/api/stoop/ws',
      );
      addTearDown(browser.close);

      // A cached older web bundle may omit `type`; the relay still normalizes
      // its token frame into the backend's canonical auth envelope.
      browser.add(jsonEncode({'token': token, 'thread': 'thread-7'}));

      final uri = await upstreamUri.future.timeout(const Duration(seconds: 3));
      expect(uri.path, '/ws');
      expect(
        uri.query,
        isEmpty,
        reason: 'the relay must not expose browser JWTs in upstream URLs',
      );
      expect(
        await firstUpstreamFrame.future.timeout(const Duration(seconds: 3)),
        {'type': 'auth', 'token': token, 'thread': 'thread-7'},
      );

      expect(
        jsonDecode(
          await browser.first.timeout(const Duration(seconds: 3)) as String,
        ),
        {'type': 'ready', 'thread': 'thread-7'},
      );

      browser.add(jsonEncode({'type': 'typing', 'isTyping': true}));
      expect(
        await secondUpstreamFrame.future.timeout(const Duration(seconds: 3)),
        {'type': 'typing', 'isTyping': true},
      );
    },
  );
}
