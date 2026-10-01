// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A ComfyUI that answered and then was closed is noticed by an open desk
// within 30 s (it stops saying Reachable), and when it comes back on another
// port that is picked up within 30 s more. Pressing Check again and again
// runs one look, not one each. Real loopback servers stand in for ComfyUI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/comfy_url_probe.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

Future<HttpServer> _comfy() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    switch (request.uri.path) {
      case '/system_stats':
        request.response.write(
          jsonEncode({
            'system': {'comfyui_version': '0.3.60'},
          }),
        );
      case '/object_info':
        request.response.write('{}');
      default:
        request.response.statusCode = 404;
    }
    await request.response.close();
  });
  return server;
}

Future<int> _deadPort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

void main() {
  late StorageService storage;
  late List<String> logged;
  late int looks;
  int? runningPort;

  setUp(() {
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('desk-comfy-restart');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
    logged = [];
    looks = 0;
    runningPort = null;
  });

  ComfyUrlFinder finder() => ComfyUrlFinder(
    processes: () async {
      looks++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final port = runningPort;
      return [
        if (port != null)
          ComfyProcessSnapshot(command: 'python main.py --port $port'),
      ];
    },
    desktopPort: () async => null,
    fallbackPorts: const [],
  );

  Future<void> openDesk(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          Provider<ComfyUrlFinder?>.value(value: finder()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StudioDesk())),
        ),
      ),
    );
  }

  Future<void> settleReal(WidgetTester tester, [int rounds = 15]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
  }

  int said(String what) => logged.where((l) => l.contains(what)).length;
  final reachable = find.textContaining('Reachable ·');

  testWidgets('a closed ComfyUI is noticed within 30 s, and its restart on '
      'another port within 30 s more', (tester) async {
    final first = (await tester.runAsync(_comfy))!;
    await storage.imageGenSettings.setImageGenBackend('comfyui');
    await storage.imageGenSettings.adoptFoundComfyUiUrl(
      'http://127.0.0.1:${first.port}',
    );
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    try {
      await openDesk(tester);
      await settleReal(tester);
      expect(reachable, findsOneWidget);
      expect(said('ComfyUI: answering'), 1);

      await tester.runAsync(() => first.close(force: true));
      await tester.pump(const Duration(seconds: 30));
      await settleReal(tester);
      expect(said('ComfyUI: not answering'), 1);
      expect(reachable, findsNothing);

      final second = (await tester.runAsync(_comfy))!;
      addTearDown(() => second.close(force: true));
      runningPort = second.port;
      for (final wait in [2, 4, 8, 16]) {
        await tester.pump(Duration(seconds: wait));
        await settleReal(tester, 8);
      }
      expect(
        storage.imageGenSettings.comfyUiUrl,
        'http://127.0.0.1:${second.port}',
      );
      expect(said('ComfyUI: answering'), 2);
      expect(said('ComfyUI: not answering'), 1);
      expect(reachable, findsOneWidget);
    } finally {
      debugPrint = original;
    }
    // Closing the desk with ComfyUI up leaves no check pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ten taps on Check run one look', (tester) async {
    final dead = (await tester.runAsync(_deadPort))!;
    await storage.imageGenSettings.setImageGenBackend('comfyui');
    await storage.imageGenSettings.adoptFoundComfyUiUrl(
      'http://127.0.0.1:$dead',
    );
    await openDesk(tester);
    await settleReal(tester);
    final before = looks;

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('Check'));
    }
    await settleReal(tester);
    expect(looks, before + 1);

    await tester.pumpWidget(const SizedBox());
  });
}
