// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// <img> tags cannot send X-Stoop-Token, so the relay remembers the Stoop
// token from the last authenticated call. That slot used to be process-wide
// on StoopFacade, so two browsers on the same host shared it and logout
// never forgot it.
//
// Proven red: a process-wide String? _assetToken makes session B's <img>
// fetch with A's token, and logout leaves the slot warm.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/stoop_facade.dart';
import 'package:front_porch_ai/services/web/routes/stoop_routes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_stoop_tok_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer upstream;
  late List<String> auths;
  late AppDatabase db;
  late Router router;

  setUp(() async {
    auths = [];
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      auths.add(req.headers.value('authorization') ?? '');
      final isAsset = req.uri.path.contains('/assets/');
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.parse(
          isAsset ? 'image/png' : 'application/json',
        )
        ..write(isAsset ? 'PNG' : '{"ok":true}');
      await req.response.close();
    });
    db = AppDatabase.forTesting();
    final facade = StoopFacade(
      StorageService(),
      db,
      api: BackporchApi(baseUrl: 'http://127.0.0.1:${upstream.port}'),
    );
    router = Router();
    WebStoopRoutes(facade, router);
  });

  tearDown(() async {
    await upstream.close(force: true);
    await db.close();
  });

  Future<shelf.Response> send(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? jsonBody,
  }) => router.call(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: jsonBody == null ? null : jsonEncode(jsonBody),
    ),
  );

  test(
    'two web sessions do not share a remembered Stoop asset token',
    () async {
      await send(
        'GET',
        '/api/stoop/me',
        headers: {'x-stoop-token': 'tok-A', 'cookie': 'fpa_session=sess-A'},
      );
      await send(
        'GET',
        '/api/stoop/me',
        headers: {'x-stoop-token': 'tok-B', 'cookie': 'fpa_session=sess-B'},
      );

      final imgA = await send(
        'GET',
        '/api/stoop/assets/a1',
        headers: {'cookie': 'fpa_session=sess-A'},
      );
      expect(imgA.statusCode, 200);
      expect(auths.last, 'Bearer tok-A');

      final imgB = await send(
        'GET',
        '/api/stoop/assets/a1',
        headers: {'cookie': 'fpa_session=sess-B'},
      );
      expect(imgB.statusCode, 200);
      expect(auths.last, 'Bearer tok-B');
    },
  );

  test(
    'Stoop logout forgets this session token; the other session stays',
    () async {
      await send(
        'GET',
        '/api/stoop/me',
        headers: {'x-stoop-token': 'tok-A', 'cookie': 'fpa_session=sess-A'},
      );
      await send(
        'GET',
        '/api/stoop/me',
        headers: {'x-stoop-token': 'tok-B', 'cookie': 'fpa_session=sess-B'},
      );

      await send(
        'POST',
        '/api/stoop/auth/logout',
        headers: {'cookie': 'fpa_session=sess-A'},
        jsonBody: {},
      );

      final imgA = await send(
        'GET',
        '/api/stoop/assets/a1',
        headers: {'cookie': 'fpa_session=sess-A'},
      );
      expect(
        imgA.statusCode,
        401,
        reason: 'THE BUG: logout left the process-wide token warm',
      );

      final imgB = await send(
        'GET',
        '/api/stoop/assets/a1',
        headers: {'cookie': 'fpa_session=sess-B'},
      );
      expect(imgB.statusCode, 200);
      expect(auths.last, 'Bearer tok-B');
    },
  );

  test('cookie-less calls never remember a process-wide token', () async {
    await send('GET', '/api/stoop/me', headers: {'x-stoop-token': 'tok-leak'});
    final img = await send('GET', '/api/stoop/assets/a1');
    expect(img.statusCode, 401);
  });
}
