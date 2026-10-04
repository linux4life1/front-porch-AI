// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A reload is checked against what the real KoboldCpp loaded: a config it
// cannot load (here, one with a broken vision file) is reported as such,
// and chat's prompts are held to the context the engine really runs. Run:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_reload_check_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 10));

class _Engine extends BackendManager {
  _Engine(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late HardwareService hardware;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai reload live');
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

    hardware = HardwareService();
    await hardware.detectHardware();
    kobold = KoboldService(storage)
      ..hardwareInfo = (() => hardware.hardwareInfo)
      ..readFreeMemory = (() => hardware.readFreeMemory());
    exe = await copyEngineInto(storage.binDir);
    port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Engine(storage, exe),
    );
  });

  tearDown(() async {
    await kobold.stopKobold();
    provider.dispose();
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

  /// A vision file KoboldCpp cannot read.
  String brokenVision() => (File(
    p.join(root.path, 'broken-mmproj.gguf'),
  )..writeAsStringSync('not a vision model')).path;

  String preset(String name, Map<String, dynamic> config) => (File(
    p.join(storage.binDir.path, '$name.kcpps'),
  )..writeAsStringSync(jsonEncode(config))).path;

  test(
    'a trial KoboldCpp could not load did not run, and chat\'s prompts are '
    'held to what still runs',
    () async {
      await start();
      final before = await liveLoadedModel(port);

      final ran = await provider.loadKoboldTrial('fpai-trial.kcpps', {
        'model_param': liveEngineModel,
        'contextsize': 8192,
        'mmproj': brokenVision(),
      });

      expect(ran, isFalse);
      expect(await liveLoadedModel(port), before);
      expect(await liveContextSize(port), 4096);
      expect(storage.backendSettings.engineContextSize, 4096);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a trial that loads ran, and chat goes back with its own context',
    () async {
      await start();

      final ran = await provider.loadKoboldTrial('fpai-trial.kcpps', {
        'model_param': liveEngineModel,
        'contextsize': 8192,
      });

      expect(ran, isTrue);
      expect(await liveContextSize(port), 8192);
      await provider.reloadChatKobold();
      expect(await liveContextSize(port), 4096);
      expect(storage.backendSettings.engineContextSize, 4096);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset with no context: prompts are held to what KoboldCpp runs',
    () async {
      await storage.backendSettings.setActiveKcppsPath(
        preset('No context', {'model_param': liveEngineModel}),
      );
      await start();

      final engine = await liveContextSize(port);
      expect(engine, isNotNull);
      for (var i = 0; i < 40; i++) {
        if (storage.backendSettings.engineContextSize == engine) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(storage.backendSettings.engineContextSize, engine);
      expect(storage.backendSettings.promptContext(1 << 20), engine);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a chat preset with no context loads by reload, and prompts are held to '
    'what KoboldCpp runs (its default differs by version)',
    () async {
      await start();
      await storage.backendSettings.setActiveKcppsPath(
        preset('No context', {'model_param': liveEngineModel}),
      );

      await provider.reloadChatKobold();

      expect(
        kobold.logs.join('\n'),
        isNot(contains('KoboldCpp could not load')),
      );
      final staged = File(
        p.join(koboldAdminDirFor(storage), kStagedChatConfig),
      ).readAsStringSync();
      expect(kobold.isResident(staged), isTrue);
      expect(
        storage.backendSettings.engineContextSize,
        await liveContextSize(port),
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a chat preset KoboldCpp could not load is not recorded as loaded, and '
    'chat starts again',
    () async {
      await start();
      await storage.backendSettings.setActiveKcppsPath(
        preset('Broken vision', {
          'model_param': liveEngineModel,
          'contextsize': 8192,
          'mmproj': brokenVision(),
        }),
      );

      await provider.reloadChatKobold();

      expect(kobold.logs.join('\n'), contains('KoboldCpp could not load'));
      final staged = File(
        p.join(koboldAdminDirFor(storage), kStagedChatConfig),
      ).readAsStringSync();
      expect(kobold.isResident(staged), isFalse);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
