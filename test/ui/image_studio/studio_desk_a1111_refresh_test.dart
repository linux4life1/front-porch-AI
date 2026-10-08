// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Automatic1111 lists the LoRAs it found when it started. A file downloaded
// since is only in its list once it is asked to look at the folder again, so a
// re-check asks before it lists. Talks to a real loopback server that behaves
// that way.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

/// An Automatic1111 whose LoRA list is stale until `refresh-loras` is asked.
class _A1111 {
  _A1111._(this.server);

  final HttpServer server;
  final List<String> asked = [];
  bool refreshed = false;

  String get url => 'http://127.0.0.1:${server.port}';

  static Future<_A1111> start() async {
    final a = _A1111._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    a.server.listen((request) async {
      a.asked.add('${request.method} ${request.uri.path}');
      Object? body;
      switch ((request.method, request.uri.path)) {
        case ('GET', '/sdapi/v1/sd-models'):
          body = [
            {'title': 'portrait.safetensors'},
          ];
        case ('GET', '/sdapi/v1/loras'):
          body = [
            {'name': 'old'},
            if (a.refreshed) {'name': 'downloaded'},
          ];
        case ('POST', '/sdapi/v1/refresh-loras'):
          a.refreshed = true;
          body = {};
        case ('GET', '/sdapi/v1/samplers'):
          body = [
            {'name': 'Euler a'},
          ];
        case ('GET', '/sdapi/v1/schedulers'):
          body = [
            {'name': 'Automatic'},
          ];
        default:
          request.response.statusCode = 404;
      }
      if (body != null) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(body));
      }
      await request.response.close();
    });
    return a;
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  late StorageService storage;
  late _A1111 a1111;

  setUp(() async {
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('desk-a1111-refresh');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
    a1111 = await _A1111.start();
    addTearDown(a1111.stop);
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setLocalImageGenUrl(a1111.url);
  });

  test(
    'the service asks the server to look at its Lora folder again',
    () async {
      final service = ImageGenService(storage);
      expect(await service.refreshA1111Loras(a1111.url), isTrue);
      expect(a1111.asked, ['POST /sdapi/v1/refresh-loras']);
    },
  );

  test('a server that does not answer is left as it was', () async {
    final service = ImageGenService(storage);
    final url = a1111.url;
    await a1111.stop();
    expect(await service.refreshA1111Loras(url), isFalse);
  });

  testWidgets('a re-check asks first, so a file downloaded since is listed', (
    tester,
  ) async {
    final service = ImageGenService(storage);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>.value(value: service),
          ],
          child: const Scaffold(
            body: SingleChildScrollView(child: StudioDesk()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check'));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.textContaining('2 LoRAs').evaluate().isNotEmpty) break;
    }

    expect(a1111.asked, contains('POST /sdapi/v1/refresh-loras'));
    expect(
      a1111.asked.indexOf('POST /sdapi/v1/refresh-loras'),
      lessThan(a1111.asked.lastIndexOf('GET /sdapi/v1/loras')),
      reason: 'asked before it was listed',
    );
    expect(find.textContaining('2 LoRAs'), findsOneWidget);
  });
}
