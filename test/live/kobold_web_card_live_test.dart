// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the phone's Local model card and preset picker set, against a real
// KoboldCpp: a preset picked on the phone is loaded in place, and a run of
// context taps is loaded once, after the taps stop. Run with:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_web_card_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../golden/support/fakes_services.dart';
import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 10));

class _Engine extends BackendManager {
  _Engine(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The model list is not what is tested; the header is read for real.
class _Models extends FakeModelManager {
  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late HardwareService hardware;
  late BackendFacade facade;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai web card live');
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
    facade = BackendFacade(provider, storage, _Models(), hardware);
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

  test(
    'a preset picked on the phone is loaded in place, and the card names it',
    () async {
      await start();
      final preset = File(p.join(storage.binDir.path, 'Long chats.kcpps'))
        ..writeAsStringSync(
          jsonEncode({'model_param': liveEngineModel, 'contextsize': 8192}),
        );

      expect(await facade.setChatPreset(preset.path), isTrue);

      expect(await liveContextSize(port), 8192);
      expect(storage.backendSettings.engineContextSize, 8192);
      final card = await facade.localModel();
      expect((card['preset'] as Map)['name'], 'Long chats');
      expect(card['auto'], isNull);

      // Back to the app's own settings, loaded in place too.
      expect(await facade.setChatPreset(null), isTrue);
      expect(await liveContextSize(port), storage.backendSettings.contextSize);
      expect((await facade.localModel())['preset'], isNull);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a run of context taps on the phone is loaded once, after they stop',
    () async {
      await start();
      final before = await liveUptime(port);
      expect(before, isNotNull);

      expect(await facade.setLocalContext(6144), isTrue);
      expect(await facade.setLocalContext(8192), isTrue);

      int? context;
      for (var i = 0; i < 120 && context != 8192; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        context = await liveContextSize(port);
      }
      expect(context, 8192);
      expect(storage.backendSettings.engineContextSize, 8192);
      // One reload: the engine's model process is younger than the taps,
      // and was not replaced again for the first tap's 6,144.
      final up = await liveUptime(port);
      expect(up, isNotNull);
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(await liveContextSize(port), 8192);
      expect(await liveUptime(port), greaterThan(up!));
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
