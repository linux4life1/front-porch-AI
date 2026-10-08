// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// KoboldService keeps ONE abort handle (its KoboldWire) for the whole
// backend. The request that finished first used to null that handle
// unconditionally, so a later Stop closed nothing and the still-running
// generation kept streaming.
//
// Requests now go to the engine one at a time (see KoboldRequestQueue), so
// the next request can no longer be open while the one before it finishes:
// the first test pins what is left of that rule, that Stop still reaches a
// request that started right after another one ended. The rule that a
// finished request lets go only of its own hold can no longer be reached
// through the service; kobold_wire_test.dart pins it on the wire itself.
//
// The second test pins the other half of the startKobold work: the
// re-entrancy slot is now claimed BEFORE the stop ladder, so every early
// return has to hand it back. Leave one out and the Start button is dead for
// the rest of the session.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart'
    show GenerationParams, KoboldService, StorageService;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The test binding installs an HttpOverrides that answers every request 400
  // without touching the network — which is exactly the transport this guard
  // has to exercise. Real sockets for these two tests only; restored after.
  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = null);
  tearDown(() => HttpOverrides.global = savedOverrides);

  final tmp = Directory.systemTemp.createTempSync('fpai_kobold_abort_');
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') return tmp.path;
        return null;
      });

  Future<StorageService> makeStorage() async {
    // Remote backend selected: the constructor's reconnect probe must never
    // pkill a KoboldCpp the developer happens to be running on :5001.
    SharedPreferences.setMockInitialValues({'backend_type': 'openRouter'});
    final storage = StorageService();
    await storage.initialized;
    return storage;
  }

  test('a request that follows a finished one can be stopped', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final firstOpen = Completer<HttpResponse>();
    final secondOpen = Completer<void>();
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      final res = req.response;
      if (!req.uri.path.endsWith('/v1/chat/completions')) {
        // Housekeeping calls (the server-side abort POST) — answered so a
        // change there can never be mistaken for a generation.
        await res.close();
        return;
      }
      res.bufferOutput = false;
      res.headers.set('Content-Type', 'text/event-stream');
      res.write('data: {"choices":[{"delta":{"content":"tok"}}]}\n');
      await res.flush();
      if (body.contains('FIRST-REQUEST')) {
        firstOpen.complete(res);
      } else {
        // Held open deliberately: this is the generation Stop must reach.
        secondOpen.complete();
      }
    });

    final storage = await makeStorage();
    final kobold = KoboldService(storage);
    addTearDown(kobold.dispose);
    kobold.setBaseUrl('http://127.0.0.1:${server.port}');

    final firstDone = Completer<void>();
    void endFirst([Object? _, StackTrace? _]) {
      if (!firstDone.isCompleted) firstDone.complete();
    }

    kobold
        .generateStream(const GenerationParams(prompt: 'FIRST-REQUEST'))
        .listen((_) {}, onDone: endFirst, onError: endFirst);
    final firstRes = await firstOpen.future;

    final secondDone = Completer<void>();
    void endSecond([Object? _, StackTrace? _]) {
      if (!secondDone.isCompleted) secondDone.complete();
    }

    kobold
        .generateStream(const GenerationParams(prompt: 'SECOND-REQUEST'))
        .listen((_) {}, onDone: endSecond, onError: endSecond);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      secondOpen.isCompleted,
      isFalse,
      reason: 'the engine takes one request at a time: the second waits',
    );

    // The first request finishes normally and the second takes its turn.
    firstRes.write('data: [DONE]\n');
    await firstRes.close();
    await firstDone.future.timeout(const Duration(seconds: 8));
    await secondOpen.future.timeout(const Duration(seconds: 8));
    expect(secondDone.isCompleted, isFalse);

    kobold.abortGeneration();
    await secondDone.future.timeout(const Duration(seconds: 8));
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('a rejected model path hands the start slot back', () async {
    final storage = await makeStorage();
    final kobold = KoboldService(storage);
    addTearDown(kobold.dispose);

    await kobold.startKobold(
      p.join(tmp.path, 'koboldcpp-does-not-exist'),
      p.join(tmp.path, 'missing-model.gguf'),
    );

    expect(
      kobold.isStarting,
      isFalse,
      reason: 'the pre-flight bail must release the slot it claimed, or no '
          'launch is possible again this session',
    );
    expect(kobold.logs.any((l) => l.contains('Model file not found')), isTrue);
  });
}
