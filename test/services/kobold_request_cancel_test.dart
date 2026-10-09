// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GenerationParams.cancel calls off ONE request at KoboldCpp. The engine
// takes one request at a time, so the request a caller calls off may still
// be waiting behind another caller's (an earlier turn's pass): that one must
// be left alone, and the called-off one never sent. Once the called-off
// request is the one on the wire, its call is cut.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart'
    show GenerationParams, KoboldService, LlmRequestCancel, StorageService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real sockets: the test binding's HttpOverrides answers every request 400.
  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = savedOverrides);

  final tmp = Directory.systemTemp.createTempSync('fpai_kobold_cancel_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return tmp.path;
        return null;
      });

  /// Loopback server holding every chat completion open; [opened] gets each
  /// request's prompt marker and response as it arrives.
  Future<HttpServer> holdingServer(
    void Function(String marker, HttpResponse res) opened,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final res = req.response;
      if (!req.uri.path.endsWith('/v1/chat/completions')) {
        await res.close();
        return;
      }
      res.bufferOutput = false;
      res.headers.set('Content-Type', 'text/event-stream');
      res.write('data: {"choices":[{"delta":{"content":"tok"}}]}\n');
      await res.flush();
      opened(body.contains('PASS-AHEAD') ? 'PASS-AHEAD' : 'MINE', res);
    });
    return server;
  }

  Future<KoboldService> kobold(HttpServer server) async {
    // Remote backend selected: never touch a real KoboldCpp on :5001.
    SharedPreferences.setMockInitialValues({'backend_type': 'openRouter'});
    final storage = StorageService();
    await storage.initialized;
    final k = KoboldService(storage)
      ..setBaseUrl('http://127.0.0.1:${server.port}');
    addTearDown(k.dispose);
    return k;
  }

  test('calling off a request that waits leaves the pass ahead running and '
      'never sends it', () async {
    final opened = <String>[];
    HttpResponse? aheadRes;
    final server = await holdingServer((marker, res) {
      opened.add(marker);
      if (marker == 'PASS-AHEAD') aheadRes = res;
    });
    addTearDown(() => server.close(force: true));
    final k = await kobold(server);

    var aheadCut = false;
    final aheadDone = Completer<void>();
    k
        .generateStream(const GenerationParams(prompt: 'PASS-AHEAD'))
        .listen(
          (_) {},
          onError: (_) => aheadCut = true,
          onDone: aheadDone.complete,
        );
    while (aheadRes == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final cancel = LlmRequestCancel();
    final mineDone = Completer<void>();
    k
        .generateStream(GenerationParams(prompt: 'MINE', cancel: cancel))
        .listen((_) {}, onError: (_) {}, onDone: mineDone.complete);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cancel.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(aheadCut, isFalse, reason: 'the pass ahead is not the caller\'s');
    expect(aheadDone.isCompleted, isFalse);

    aheadRes!.write('data: [DONE]\n');
    await aheadRes!.close();
    await aheadDone.future.timeout(const Duration(seconds: 8));
    await mineDone.future.timeout(const Duration(seconds: 8));
    expect(aheadCut, isFalse);
    expect(opened, ['PASS-AHEAD'], reason: 'the called-off request waited');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('calling off the request on the wire cuts its call', () async {
    final mineOpen = Completer<void>();
    final server = await holdingServer((marker, _) => mineOpen.complete());
    addTearDown(() => server.close(force: true));
    final k = await kobold(server);

    final cancel = LlmRequestCancel();
    final mineEnded = Completer<void>();
    void end([Object? _]) {
      if (!mineEnded.isCompleted) mineEnded.complete();
    }

    k
        .generateStream(GenerationParams(prompt: 'MINE', cancel: cancel))
        .listen((_) {}, onError: end, onDone: end);
    await mineOpen.future.timeout(const Duration(seconds: 8));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(mineEnded.isCompleted, isFalse, reason: 'held open by the server');

    cancel.cancel();
    await mineEnded.future.timeout(const Duration(seconds: 8));
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('calling off a request that already finished leaves the next caller\'s '
      'call alone', () async {
    final responses = <String, HttpResponse>{};
    final server = await holdingServer(
      (marker, res) => responses[marker] = res,
    );
    addTearDown(() => server.close(force: true));
    final k = await kobold(server);

    final cancel = LlmRequestCancel();
    final mineDone = Completer<void>();
    k
        .generateStream(GenerationParams(prompt: 'MINE', cancel: cancel))
        .listen((_) {}, onError: (_) {}, onDone: mineDone.complete);
    while (responses['MINE'] == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    responses['MINE']!.write('data: [DONE]\n');
    await responses['MINE']!.close();
    await mineDone.future.timeout(const Duration(seconds: 8));

    var aheadCut = false;
    k
        .generateStream(const GenerationParams(prompt: 'PASS-AHEAD'))
        .listen((_) {}, onError: (_) => aheadCut = true);
    while (responses['PASS-AHEAD'] == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    cancel.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(aheadCut, isFalse, reason: 'the call on the wire is not mine');
  }, timeout: const Timeout(Duration(seconds: 40)));
}
