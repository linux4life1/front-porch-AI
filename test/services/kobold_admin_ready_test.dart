// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:http/http.dart' as http;

import 'kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  setUpAll(() {
    HttpOverrides.global = null;
  });

  late StorageService storage;
  late KoboldService kobold;
  late HttpServer version;

  setUp(() async {
    storage = await createStorageService();
    kobold = KoboldService(storage);
    version = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    version.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"result":"KoboldCpp","version":"1.90"}');
      await req.response.close();
    });
    kobold.setBaseUrl('http://127.0.0.1:${version.port}');
    kobold.debugMarkProcessRunning();
  });

  tearDown(() async {
    kobold.dispose();
    await version.close(force: true);
  });

  test('noteAdminLoadedPair re-arms production isReady', () async {
    expect(kobold.isReady, isFalse);
    kobold.markModelNotReady();
    expect(kobold.isReady, isFalse);
    await kobold.noteAdminLoadedPair(
      modelPath: '/tmp/worker.gguf',
      kcppsPath: '/tmp/worker.kcpps',
    );
    expect(kobold.isReady, isTrue);
    expect(kobold.loadedModelPath, '/tmp/worker.gguf');
    expect(kobold.loadedKcppsPath, '/tmp/worker.kcpps');
  });

  test(
    'admin restore sets production isReady without process restart',
    () async {
      var starts = 0;
      var stops = 0;
      final host = KoboldProcessHost(
        baseUrl: kobold.baseUrl,
        requestedModelPath: '/tmp/worker.gguf',
        requestedKcppsPath: '/tmp/worker.kcpps',
        markNotReady: kobold.markModelNotReady,
        noteLoadedPair: (model, kcpps) =>
            kobold.noteAdminLoadedPair(modelPath: model, kcppsPath: kcpps),
        waitUntilReady: kobold.waitUntilReadyAfterSwap,
        isProcessRunning: () => kobold.isProcessRunning,
        stopProcess: () async => stops++,
        startProcess: () async => starts++,
        admin: HttpGpuSwapHost(
          kind: LocalSwapKind.koboldProcess,
          apiUrl: kobold.baseUrl,
          modelId: '/tmp/worker.gguf',
          send: (method, uri, headers, body) async {
            return http.Response('{"success":true}', 200);
          },
        ),
      );

      await host.unload();
      expect(kobold.isReady, isFalse);
      expect(stops, 0);

      await host.restore();
      expect(
        kobold.isReady,
        isTrue,
        reason: 'admin HTTP 200 must re-arm production isReady',
      );
      expect(starts, 0);
      expect(stops, 0);
    },
  );
}
