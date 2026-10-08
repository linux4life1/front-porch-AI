// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ComfyUI started after the desk was opened, on a port other than the one
// saved, is found by itself while the desk stays open; the desk says it once
// when ComfyUI goes down and once when it comes up, not on every try; and it
// stops looking when it is closed. A real loopback ComfyUI comes up mid-test.

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

/// Just enough of ComfyUI for the desk: who it is, and an empty node list.
Future<HttpServer> _comfy() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/system_stats') {
      request.response.write(
        jsonEncode({
          'system': {'comfyui_version': '0.3.60'},
        }),
      );
    } else if (path == '/object_info') {
      request.response.write('{}');
    } else {
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
    final dir = Directory.systemTemp.createTempSync('desk-comfy-find');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
    logged = [];
    looks = 0;
    runningPort = null;
  });

  /// Looks only where the test says ComfyUI is running.
  ComfyUrlFinder finder() => ComfyUrlFinder(
    processes: () async {
      looks++;
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

  /// Lets real network work finish, a little at a time.
  Future<void> settleReal(WidgetTester tester, [int rounds = 15]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
  }

  int said(String what) => logged.where((l) => l.contains(what)).length;

  testWidgets('ComfyUI that comes up later is found, and said once each way', (
    tester,
  ) async {
    final dead = (await tester.runAsync(_deadPort))!;
    await storage.imageGenSettings.setImageGenBackend('comfyui');
    await storage.imageGenSettings.adoptFoundComfyUiUrl(
      'http://127.0.0.1:$dead',
    );
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
    try {
      await openDesk(tester);
      await settleReal(tester);
      expect(said('ComfyUI: not answering'), 1);

      // A few tries go by with nothing there: still said only once.
      for (final wait in [2, 4, 8]) {
        await tester.pump(Duration(seconds: wait));
        await settleReal(tester, 5);
      }
      final triedWhileDown = looks;
      expect(triedWhileDown, greaterThanOrEqualTo(3));
      expect(said('ComfyUI: not answering'), 1);

      // ComfyUI starts, on a port nobody saved.
      final server = (await tester.runAsync(_comfy))!;
      addTearDown(() => server.close(force: true));
      runningPort = server.port;
      await tester.pump(const Duration(seconds: 16));
      await settleReal(tester, 30);

      final url = 'http://127.0.0.1:${server.port}';
      expect(storage.imageGenSettings.comfyUiUrl, url);
      expect(storage.imageGenSettings.comfyUiUrlExplicit, isFalse);
      expect(said('ComfyUI: answering'), 1);
      expect(said('ComfyUI: not answering'), 1);

      // Up: no more looking.
      final whenUp = looks;
      await tester.pump(const Duration(seconds: 60));
      await settleReal(tester, 5);
      expect(looks, whenUp);
    } finally {
      debugPrint = original;
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the desk stops the looking', (tester) async {
    final dead = (await tester.runAsync(_deadPort))!;
    await storage.imageGenSettings.setImageGenBackend('comfyui');
    await storage.imageGenSettings.adoptFoundComfyUiUrl(
      'http://127.0.0.1:$dead',
    );
    await openDesk(tester);
    await settleReal(tester);
    await tester.pump(const Duration(seconds: 2));
    await settleReal(tester, 5);
    expect(looks, greaterThanOrEqualTo(2), reason: 'open, then one retry');

    // Closed with nothing to wait for: the test framework fails a test that
    // ends with a timer still pending, so the retry must have been cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a listing that failed is tried again on the next look, not '
      'kept as done', (tester) async {
    var objectInfoAsks = 0;
    var answering = false;
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/object_info') {
        objectInfoAsks++;
        if (answering) {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
        } else {
          request.response.statusCode = 500;
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final settings = storage.imageGenSettings;
    await settings.setImageGenBackend('comfyui');
    await settings.setComfyUiUrl('http://127.0.0.1:${server.port}');

    await openDesk(tester);
    await settleReal(tester);
    final whileDown = objectInfoAsks;
    expect(whileDown, greaterThan(0));

    // ComfyUI comes up; the next look (any settings change) lists it.
    answering = true;
    await settings.setImageGenSize('768x768');
    await tester.pump();
    await settleReal(tester);
    expect(objectInfoAsks, greaterThan(whileDown));

    await tester.pumpWidget(const SizedBox());
  });
}
