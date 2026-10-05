// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor and auto mode against a real KoboldCpp. Run with:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_presets_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
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
    final temp = await Directory.systemTemp.createTemp('fpai presets live');
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

    // Detection waits for the app's first frame, which a test never has.
    hardware = HardwareService();
    await hardware.detectHardware();
    expect(hardware.hardwareInfo, isNotNull);
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

  KcppsEditorController editor() => KcppsEditorController(
    storage: storage,
    hardware: hardware,
    kobold: kobold,
    reloadChat: provider.reloadChatKobold,
    loadTrial: provider.loadKoboldTrial,
    models: [liveEngineModel],
  );

  /// The staged chat config the engine was given.
  Map<String, dynamic> stagedChat() => readKcpps(
    File(
      p.join(koboldAdminDirFor(storage), kStagedChatConfig),
    ).readAsStringSync(),
  ).let((r) => (r as KcppsOk).raw);

  test(
    'auto mode: the batch and slots it picks for this Mac run, and chat\'s '
    'prompts are held to the context the engine really has',
    () async {
      await start();
      final staged = stagedChat();
      // A small model on this Mac fits with plenty of room.
      expect(staged['batchsize'], 2048);
      expect(staged['smartcache'], 3);
      expect(await liveContextSize(port), 4096);
      expect(storage.backendSettings.engineContextSize, 4096);
      expect(storage.backendSettings.promptContext(32768), 4096);
      expect(kobold.freeBeforeLaunch?.system, isNotNull);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset placed by hand loads with exactly those layers on the card',
    () async {
      final c = editor();
      addTearDown(c.dispose);
      await c.init();
      c.edit(
        (d) => d.copyWith(
          name: 'By hand',
          modelPath: liveEngineModel,
          contextSize: 4096,
          manual: true,
          gpuLayers: 10,
        ),
      );
      expect(await c.saveAndUse(), KcppsSaveResult.saved);
      expect(storage.backendSettings.activeKcppsPath, c.path);

      await start();
      expect(
        kobold.logs.join('\n'),
        contains('offloaded 10/'),
        reason: 'KoboldCpp put exactly 10 layers on the card',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    '"Save and use now" while KoboldCpp runs loads the preset in place',
    () async {
      await start();
      final engines = await livePidsStartedFrom(root.path);
      final c = editor();
      addTearDown(c.dispose);
      await c.init();
      c.edit(
        (d) => d.copyWith(
          name: 'Short',
          modelPath: liveEngineModel,
          contextSize: 2048,
        ),
      );
      expect(await c.saveAndUse(), KcppsSaveResult.saved);
      expect(await liveContextSize(port), 2048);
      // A reload replaces KoboldCpp's model process; the process the app
      // started stays. A restart would replace it too.
      expect(
        await livePidsStartedFrom(root.path),
        contains(engines.reduce((a, b) => a < b ? a : b)),
        reason: 'a reload, not a new engine',
      );
      expect(storage.backendSettings.engineContextSize, 2048);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'timing MMQ loads the preset each way, times a fresh prompt, keeps the '
    'faster and puts chat back',
    () async {
      await start();
      final c = editor();
      addTearDown(c.dispose);
      await c.init();
      c.edit(
        (d) => d.copyWith(
          name: 'Timed',
          modelPath: liveEngineModel,
          contextSize: 4096,
        ),
      );
      await c.timeMmq();
      expect(c.mmqStatus, startsWith('On: '));
      expect(c.draft.mmq, isNotNull);
      expect(
        storage.backendSettings.mmqFor(
          hardware.hardwareInfo!.gpuName,
          c.engineVersion,
        ),
        c.draft.mmq,
      );
      // Chat is back on its own config.
      expect(stagedChat()['contextsize'], 4096);
      expect(await liveContextSize(port), 4096);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'the speed line KoboldCpp prints after a reply is the one auto mode '
    'learns from',
    () async {
      await start();
      await livePost(port, '/api/v1/generate', {
        'prompt': koboldTimingPrompt(1),
        'max_length': 24,
      });
      // The app's own small checks print speed lines too; the timing
      // prompt's is the long one, printed once the reply is done.
      List<KoboldSpeed> long() => [
        for (final line in kobold.logs.join('\n').split('\n'))
          if (parseKoboldSpeed(line) case final s? when s.read > 1024) s,
      ];
      for (var i = 0; i < 60 && long().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(long(), isNotEmpty);
      expect(long().last.readSeconds, greaterThan(0));
      expect(long().last.written, greaterThan(0));
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}

extension<T> on T {
  R let<R>(R Function(T it) f) => f(this);
}
