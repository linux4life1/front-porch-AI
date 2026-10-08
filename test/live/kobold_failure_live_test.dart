// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the app says when a REAL KoboldCpp stops on its own. The engine is
// killed from outside in the middle of a reply (the way a driver crash
// ends it), and the app must say it stopped while answering; a stop the
// app asks for must not be taken for a failure. Skipped unless
// KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL are set; see
// kobold_engine_live_test.dart.

@Tags(['kobold_live'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 8));

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai failure live');
    root = Directory(temp.resolveSymbolicLinksSync());
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setContextSize(4096);
    kobold = KoboldService(storage);
    exe = await copyEngineInto(storage.binDir);
    port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');

    expect(
      (await kobold.launch(
        exe,
        pickedModel: liveEngineModel,
        port: port,
      )).started,
      isTrue,
    );
    await waitForLiveModel(port);
    for (var i = 0; i < 120 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(kobold.modelReady, isTrue);
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  Future<void> until(bool Function() done, String what) async {
    for (var i = 0; i < 240 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(done(), isTrue, reason: what);
  }

  test(
    'killed in the middle of a reply: the app says it stopped while '
    'answering',
    () async {
      final before = kobold.logs.length;
      unawaited(
        livePost(port, '/api/v1/generate', {
          'prompt': 'Write a long story about a lighthouse keeper.',
          'max_length': 800,
        }),
      );
      await until(
        () => kobold.logs.skip(before).any((l) => l.contains('Generating (')),
        'the engine starts writing',
      );

      for (final pid in await livePidsStartedFrom(exe)) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
      await until(() => !kobold.isRunning, 'the app notices the exit');

      expect(kobold.lastFailure?.kind, KoboldFailureKind.diedWhileAnswering);
      expect(kobold.logs.last, contains('stopped while answering'));
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a stop the app asks for is not a failure',
    () async {
      await kobold.stopKobold();
      expect(kobold.isRunning, isFalse);
      expect(kobold.lastFailure, isNull);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
