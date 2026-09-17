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

  test(
    'noteAdminLoadedPair stamps paths but version 200 is not ready',
    () async {
      expect(kobold.isReady, isFalse);
      kobold.markModelNotReady();
      await kobold.noteAdminLoadedPair(
        modelPath: '/tmp/worker.gguf',
        kcppsPath: '/tmp/worker.kcpps',
      );
      expect(
        kobold.isReady,
        isFalse,
        reason: 'version-only 200 must not unlock evals or mouth generate',
      );
      expect(kobold.loadedModelPath, '/tmp/worker.gguf');
      expect(kobold.loadedKcppsPath, '/tmp/worker.kcpps');
    },
  );

  test('version-only waitUntilReadyAfterSwap does not mark ready', () async {
    kobold.markModelNotReady();
    await expectLater(
      kobold.waitUntilReadyAfterSwap(attempts: 2, delay: Duration.zero),
      throwsStateError,
    );
    expect(kobold.isReady, isFalse);
  });

  test(
    'admin restore with version-only ready does not start and stays unready',
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
        waitUntilReady: () =>
            kobold.waitUntilReadyAfterSwap(attempts: 2, delay: Duration.zero),
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

      await expectLater(host.restore(), throwsStateError);
      expect(kobold.isReady, isFalse);
      expect(
        starts,
        0,
        reason: 'generation-ready miss is not a process restart',
      );
      expect(stops, 0);
    },
  );

  test('tiny completion after admin restore marks generation-ready', () async {
    await version.close(force: true);
    final ready = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => ready.close(force: true));
    ready.listen((req) async {
      req.response.headers.contentType = ContentType.json;
      if (req.uri.path.contains('chat/completions')) {
        req.response.write(
          '{"choices":[{"message":{"content":"ok"}}],'
          '"usage":{"completion_tokens":1}}',
        );
      } else {
        req.response.write('{"result":"KoboldCpp","version":"1.90"}');
      }
      await req.response.close();
    });
    kobold.setBaseUrl('http://127.0.0.1:${ready.port}');
    kobold.markModelNotReady();
    var starts = 0;
    var stops = 0;
    final host = KoboldProcessHost(
      baseUrl: kobold.baseUrl,
      requestedModelPath: '/tmp/worker.gguf',
      requestedKcppsPath: '/tmp/worker.kcpps',
      markNotReady: kobold.markModelNotReady,
      noteLoadedPair: (model, kcpps) =>
          kobold.noteAdminLoadedPair(modelPath: model, kcppsPath: kcpps),
      waitUntilReady: () =>
          kobold.waitUntilReadyAfterSwap(attempts: 4, delay: Duration.zero),
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
    await host.restore();
    expect(kobold.isReady, isTrue);
    expect(starts, 0);
    expect(stops, 0);
  });
}
