// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Unload when idle, on a REAL KoboldCpp the app started: after the idle time
// (shortened through the service's test hook; Settings turns it on), the
// engine reports no model loaded and the app says so, and the next reply,
// and the next tool call, load the model back by the staged config's name
// and are answered. Run:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_idle_unload_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 10));

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late HardwareService hardware;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai idle live');
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
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await b.setContextSize(4096);
    await b.setLastUsedModelPath(liveEngineModel);
    await b.setIdleUnloadMinutes(10);

    hardware = HardwareService();
    await hardware.detectHardware();
    kobold = KoboldService(storage)
      ..hardwareInfo = (() => hardware.hardwareInfo)
      ..readFreeMemory = (() => hardware.readFreeMemory())
      ..debugIdleUnloadAfter = const Duration(seconds: 3);
    exe = await copyEngineInto(storage.binDir);
    port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    hardware.dispose();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  Future<void> start() async {
    expect((await kobold.launch(exe, port: port)).started, isTrue);
    await waitForLiveModel(port);
    for (var i = 0; i < 120 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(kobold.modelReady, isTrue);
  }

  /// Waits, with nothing asked of it, until the engine has unloaded.
  Future<void> idleUntilUnloaded() async {
    await waitForLiveUnload(port);
    for (var i = 0; i < 100 && kobold.phase != KoboldPhase.unloaded; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  test(
    'idle, the real engine unloads its model and the app says so; the next '
    'reply and the next tool call load it back and are answered',
    () async {
      await start();
      final loaded = await liveLoadedModel(port);
      expect(loaded, isNot('inactive'));

      await idleUntilUnloaded();
      expect(kobold.phase, KoboldPhase.unloaded);
      expect(kobold.modelReady, isFalse);
      expect(
        kobold.modelLoadingStatus,
        'The model was unloaded after 10 idle minutes to free graphics '
        'memory. It loads again with your next message.',
      );
      expect(kobold.isProcessRunning, isTrue, reason: 'the engine stays up');
      // The engine's empty model process says "Please connect…" like a
      // model that came up. It is not one.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(await liveLoadedModel(port), 'inactive');
      expect(kobold.modelReady, isFalse);
      expect(kobold.phase, KoboldPhase.unloaded);

      final reply = await kobold
          .generateStream(
            GenerationParams(
              prompt: 'Say hello in one short sentence.',
              maxLength: 24,
            ),
          )
          .join();

      expect(reply.trim(), isNotEmpty);
      expect(await liveLoadedModel(port), loaded);
      expect(kobold.modelReady, isTrue);
      expect(kobold.phase, KoboldPhase.ready);
      expect(kobold.loadedModelPath, liveEngineModel);
      final staged = File(
        p.join(koboldAdminDirFor(storage), kStagedChatConfig),
      ).readAsStringSync();
      expect(kobold.isResident(staged), isTrue);
      expect(
        kobold.logs.join('\n'),
        contains('Reloading new model/config: $kStagedChatConfig'),
      );

      // Idle again: a tool call (how Realism checks ask) loads it back too.
      await idleUntilUnloaded();
      expect(kobold.modelReady, isFalse);
      final answer = await kobold.generateWithTools(
        GenerationParams(prompt: 'Rate the weather today.', maxLength: 64),
        [
          {
            'type': 'function',
            'function': {
              'name': 'rate_weather',
              'description': 'Rate the weather from 1 to 10.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'score': {'type': 'integer'},
                },
                'required': ['score'],
              },
            },
          },
        ],
      );

      expect(answer, isNotNull);
      expect(answer!.calls.isNotEmpty || answer.text.trim().isNotEmpty, isTrue);
      expect(await liveLoadedModel(port), loaded);
      expect(kobold.modelReady, isTrue);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
