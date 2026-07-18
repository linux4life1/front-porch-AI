// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the Stoop web relay (WebStoopRoutes + StoopFacade) against a fake
// upstream backend on loopback: verbatim status/body passthrough, the
// X-Stoop-Token → Authorization: Bearer translation, the 401 guard when the
// browser sends no token, upstream verb mapping (follow/unfollow), report
// characterId injection, the remembered-token fallback for <img> asset
// requests, the bundled AUP endpoint, and the 503 guard when the library
// isn't wired for imports.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/backporch/stoop_aup.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/stoop_facade.dart';
import 'package:front_porch_ai/services/web/routes/stoop_routes.dart';

/// One recorded upstream hit.
class UpstreamHit {
  UpstreamHit(this.method, this.path, this.query, this.auth, this.body);
  final String method;
  final String path;
  final String query;
  final String? auth;
  final String body;
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_test_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();
  SharedPreferences.setMockInitialValues({});
  // flutter_test stubs out HttpClient (every request answers 400); these tests
  // relay to a real loopback upstream, so restore real networking.
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer upstream;
  late List<UpstreamHit> hits;
  late AppDatabase db;
  late Router router;

  // Canned upstream reply for the next request(s).
  var upstreamStatus = 200;
  var upstreamBody = '{"ok":true}';
  var upstreamContentType = 'application/json';

  setUp(() async {
    hits = [];
    upstreamStatus = 200;
    upstreamBody = '{"ok":true}';
    upstreamContentType = 'application/json';

    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      hits.add(
        UpstreamHit(
          req.method,
          req.uri.path,
          req.uri.query,
          req.headers.value('authorization'),
          body,
        ),
      );
      req.response
        ..statusCode = upstreamStatus
        ..headers.contentType = ContentType.parse(upstreamContentType)
        ..write(upstreamBody);
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
  }) async {
    return await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: headers,
        body: jsonBody == null ? null : jsonEncode(jsonBody),
      ),
    );
  }

  test('login relays the body and passes upstream status/body through', () async {
    upstreamStatus = 401;
    upstreamBody = '{"error":"two_factor_required"}';
    final res = await send(
      'POST',
      '/api/stoop/auth/login',
      jsonBody: {'email': 'a@b.c', 'password': 'hunter22'},
    );
    expect(res.statusCode, 401);
    expect(await res.readAsString(), '{"error":"two_factor_required"}');
    expect(hits.single.method, 'POST');
    expect(hits.single.path, '/auth/login');
    expect(hits.single.auth, isNull);
    expect(jsonDecode(hits.single.body), {'email': 'a@b.c', 'password': 'hunter22'});
  });

  test('token-required routes answer 401 locally when no token is sent', () async {
    final res = await send('GET', '/api/stoop/me');
    expect(res.statusCode, 401);
    expect(jsonDecode(await res.readAsString()), {'error': 'stoop_not_signed_in'});
    expect(hits, isEmpty, reason: 'the upstream must never be hit');
  });

  test('browse forwards the query string and the bearer token', () async {
    upstreamBody = '{"total":0,"page":0,"items":[]}';
    final res = await send(
      'GET',
      '/api/stoop/browse?sort=top&type=group&q=%23fantasy&page=2&take=24',
      headers: {'x-stoop-token': 'tok-1'},
    );
    expect(res.statusCode, 200);
    expect(hits.single.path, '/characters');
    expect(hits.single.query, contains('sort=top'));
    expect(hits.single.query, contains('q=%23fantasy'));
    expect(hits.single.auth, 'Bearer tok-1');
  });

  test('report injects the card id from the path into the upstream body', () async {
    final res = await send(
      'POST',
      '/api/stoop/cards/c42/report',
      headers: {'x-stoop-token': 'tok-1'},
      jsonBody: {'category': 'SPAM', 'reason': 'ad bot'},
    );
    expect(res.statusCode, 200);
    expect(hits.single.path, '/reports');
    expect(jsonDecode(hits.single.body), {
      'characterId': 'c42',
      'category': 'SPAM',
      'reason': 'ad bot',
    });
  });

  test('follow=false maps to an upstream DELETE', () async {
    await send(
      'POST',
      '/api/stoop/creators/u7/follow',
      headers: {'x-stoop-token': 'tok-1'},
      jsonBody: {'follow': false},
    );
    expect(hits.single.method, 'DELETE');
    expect(hits.single.path, '/creators/u7/follow');
  });

  test('asset requests fall back to the token remembered from earlier calls',
      () async {
    // No token known yet → 401, upstream untouched.
    final cold = await send('GET', '/api/stoop/assets/a1');
    expect(cold.statusCode, 401);
    expect(hits, isEmpty);

    // An authenticated call teaches the facade the token…
    await send('GET', '/api/stoop/me', headers: {'x-stoop-token': 'tok-9'});

    // …then a header-less <img> fetch succeeds with it.
    upstreamContentType = 'image/png';
    upstreamBody = 'PNGBYTES';
    final warm = await send('GET', '/api/stoop/assets/a1');
    expect(warm.statusCode, 200);
    expect(warm.headers['content-type'], startsWith('image/png'));
    expect(hits.last.path, '/assets/a1/raw');
    expect(hits.last.auth, 'Bearer tok-9');
  });

  test('aup serves the bundled policy document', () async {
    final res = await send('GET', '/api/stoop/aup');
    expect(res.statusCode, 200);
    final doc = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    expect(doc['id'], kStoopAupId);
    expect(doc['intro'], kStoopAupIntro);
    expect((doc['sections'] as List).length, kStoopAupSections.length);
    expect(hits, isEmpty, reason: 'served locally, never proxied');
  });

  test('download answers 503 when the library repositories are not wired',
      () async {
    final res = await send(
      'POST',
      '/api/stoop/cards/c1/download',
      headers: {'x-stoop-token': 'tok-1'},
      jsonBody: {'type': 'SOLO'},
    );
    expect(res.statusCode, 503);
    expect(jsonDecode(await res.readAsString()), {'error': 'library_unavailable'});
    expect(hits, isEmpty);
  });
}
