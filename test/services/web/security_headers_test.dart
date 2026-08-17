// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pins the baseline security headers on every response, including a
// Content-Security-Policy that forbids eval and framing. Does not construct
// payloads or demonstrate a bypass — it only asserts the header is present
// and names the directives the PWA needs.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/middleware/security_headers.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

void _mockPathProvider() {
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
  _mockPathProvider();
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late SecurityHeaders headers;

  setUp(() {
    db = AppDatabase.forTesting();
    headers = SecurityHeaders(
      WebServerDeps(storage: StorageService(), db: db, auth: AuthService(db)),
    );
  });
  tearDown(() => db.close());

  Future<shelf.Response> get(String url) async {
    return headers.middleware((_) async => shelf.Response.ok('ok'))(
      shelf.Request('GET', Uri.parse(url)),
    );
  }

  test(
    'every response carries CSP and the clickjacking / sniff headers',
    () async {
      final res = await get('http://localhost/index.html');
      expect(
        res.headers['content-security-policy'],
        SecurityHeaders.contentSecurityPolicy,
      );
      expect(res.headers['x-content-type-options'], 'nosniff');
      expect(res.headers['x-frame-options'], 'DENY');
      expect(res.headers['referrer-policy'], 'no-referrer');
    },
  );

  test(
    'CSP is same-origin, forbids eval, and names the PWA directives',
    () async {
      const csp = SecurityHeaders.contentSecurityPolicy;
      expect(csp, contains("default-src 'self'"));
      expect(csp, contains("script-src 'self'"));
      expect(csp, contains("connect-src 'self'"));
      expect(csp, contains("worker-src 'self'"));
      expect(csp, contains("frame-ancestors 'none'"));
      expect(csp, contains("base-uri 'self'"));
      expect(csp, contains("form-action 'self'"));
      expect(csp.contains('unsafe-eval'), isFalse);
    },
  );

  test('HSTS is omitted on plain HTTP', () async {
    final res = await get('http://localhost/');
    expect(res.headers.containsKey('strict-transport-security'), isFalse);
  });
}
