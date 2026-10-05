// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app's own launch path against a REAL KoboldCpp: KoboldService starts
// the engine from the config it stages, and the engine is asked what it
// actually loaded. Skipped unless KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL are
// set; see kobold_engine_live_test.dart.

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

const _slow = Timeout(Duration(minutes: 8));

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai launch live');
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
    kobold = KoboldService(storage);
    exe = await copyEngineInto(storage.binDir);
    port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  Map<String, dynamic> staged() =>
      (jsonDecode(
                File(
                  p.join(koboldAdminDirFor(storage), kStagedChatConfig),
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, dynamic>();

  bool printed(Pattern what) => kobold.logs.any((l) => l.contains(what));

  Future<void> start({String? preset}) async {
    final b = storage.backendSettings;
    await kobold.startKobold(
      exe,
      liveEngineModel,
      kcppsPath: preset,
      port: port,
      gpuLayers: b.gpuLayers,
      contextSize: b.contextSize,
      useMetal: Platform.isMacOS,
    );
    await waitForLiveModel(port);
  }

  test(
    'with nothing but Settings, the engine starts from the app\'s staged '
    'config: Settings\' context and batch size, automatic fit, and the old '
    'batch override file gone',
    () async {
      final b = storage.backendSettings;
      await b.setContextSize(4096);
      await b.setBlasBatchSize(1536);
      final legacy = File(
        p.join(storage.binDir.path, 'fpai_batch_override.kcpps'),
      )..writeAsStringSync('{"blasbatchsize": 8192}');

      await start();

      expect(await liveContextSize(port), 4096);
      expect(printed(RegExp(r'n_ubatch\s*=\s*1536')), isTrue);
      expect(legacy.existsSync(), isFalse);

      final config = staged();
      expect(config['gpulayers'], -1, reason: 'KoboldCpp fits the model');
      expect(config.containsKey('autofit'), isFalse);
      expect(config['model_param'], liveEngineModel);
      expect(config['jinja'], isTrue);

      final reply = await livePost(port, '/api/v1/generate', {
        'prompt': 'Count: one, two, three,',
        'max_length': 8,
      });
      expect(
        ((reply as Map)['results'] as List).single['text'],
        isNotEmpty,
        reason: 'the model the app loaded really generates',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    '"Set layers myself" reaches the real engine as that number of layers',
    () async {
      final b = storage.backendSettings;
      await b.setContextSize(4096);
      await b.setGpuLayers(10);
      await b.setGpuLayersManual(true);

      await start();

      expect(staged()['gpulayers'], 10);
      expect(
        printed(RegExp(r'offloaded 10/\d+ layers')),
        isTrue,
        reason: 'the engine reports how many layers it put on the card',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset is run as its author wrote it, with the model and the chat '
    'template the app adds',
    () async {
      // A hand-made preset: no model, a context size unlike Settings'.
      final preset = File(p.join(storage.binDir.path, 'mine.kcpps'))
        ..writeAsStringSync('{"contextsize": 2048, "noswa": true}');
      await storage.backendSettings.setContextSize(8192);

      await start(preset: preset.path);

      expect(await liveContextSize(port), 2048);
      final config = staged();
      expect(config['model_param'], liveEngineModel);
      expect(config['jinja'], isTrue);
      // The author's file is untouched.
      expect(preset.readAsStringSync(), '{"contextsize": 2048, "noswa": true}');
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset\'s own settings reach the real engine as written, including '
    'ones the app has no control for',
    () async {
      // A MoE layer count beside a layer count, a cache size past the app's
      // own range, and context shift off with fast forward on. The launch
      // used to turn these into "all layers", 20, and on.
      final preset = File(p.join(storage.binDir.path, 'tuned.kcpps'))
        ..writeAsStringSync(
          jsonEncode({
            'contextsize': 2048,
            'gpulayers': 7,
            'moecpu': 12,
            'smartcache': 30,
            'noswa': true,
            'noshift': true,
            'defaultgenamt': 300,
          }),
        );

      await start(preset: preset.path);

      // KoboldCpp lists the settings it was started with.
      String? received(String name) => RegExp(
        '\\b${RegExp.escape(name)}=([^,)]+)',
      ).firstMatch(kobold.logs.join('\n'))?.group(1);
      expect(received('moecpu'), '12');
      expect(received('smartcache'), '30');
      expect(received('noshift'), 'True');
      expect(received('nofastforward'), 'False');
      expect(received('gpulayers'), '7');
      expect(received('defaultgenamt'), '300');
      expect(printed(RegExp(r'offloaded 7/\d+ layers')), isTrue);
      expect(await liveContextSize(port), 2048);

      // Staged beside the app's own files: the author's file plus the model,
      // the chat template, the listen address and KoboldCpp's own idle unload
      // switched off, and nothing else.
      expect(staged(), {
        'contextsize': 2048,
        'gpulayers': 7,
        'moecpu': 12,
        'smartcache': 30,
        'noswa': true,
        'noshift': true,
        'defaultgenamt': 300,
        'model_param': liveEngineModel,
        'jinja': true,
        'host': '127.0.0.1',
        'adminunloadtimeout': 0,
      });
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset that asks for KoboldCpp\'s own idle unload is launched with it '
    'off: the staged config starts the real engine, which reports 0',
    () async {
      // 300 would unload the model behind the app's back after five idle
      // minutes, and nothing would load it again.
      final body = jsonEncode({
        'contextsize': 2048,
        'noswa': true,
        'adminunloadtimeout': 300,
      });
      final preset = File(p.join(storage.binDir.path, 'sleepy.kcpps'))
        ..writeAsStringSync(body);

      await start(preset: preset.path);

      expect(staged()['adminunloadtimeout'], 0);
      expect(
        printed(RegExp(r'\badminunloadtimeout=0\b')),
        isTrue,
        reason: 'the engine lists the settings it started with',
      );
      expect(printed(RegExp(r'\badminunloadtimeout=300\b')), isFalse);
      expect(await liveContextSize(port), 2048, reason: 'it loaded and ran');
      expect(preset.readAsStringSync(), body);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset that owns its model: the real engine loads that model, and '
    'the app records it as the one in use',
    () async {
      // The same model under another name, so the engine's answer shows
      // which path it was given.
      final owned = Link(p.join(root.path, 'owned-by-preset.gguf'))
        ..createSync(liveEngineModel);
      final b = storage.backendSettings;
      await b.setLastUsedModelPath(liveEngineModel);
      await b.setActiveKcppsPath(
        (File(p.join(storage.binDir.path, 'owner.kcpps'))..writeAsStringSync(
              jsonEncode({
                'model_param': owned.path,
                'contextsize': 2048,
                'noswa': true,
              }),
            ))
            .path,
      );

      final result = await kobold.launch(exe, port: port);
      expect(result.started, isTrue);
      expect(result.message, isNull);
      await waitForLiveModel(port);

      expect(await liveLoadedModel(port), contains('owned-by-preset'));
      expect(await liveContextSize(port), 2048);
      expect(b.lastUsedModelPath, owned.path);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a preset made on another computer: the real engine loads the model '
    'chosen here with the preset\'s settings, and the app says why',
    () async {
      final b = storage.backendSettings;
      await b.setActiveKcppsPath(
        (File(p.join(storage.binDir.path, 'theirs.kcpps'))..writeAsStringSync(
              jsonEncode({
                'model_param': '/another/computer/big.gguf',
                'contextsize': 2048,
                'noswa': true,
              }),
            ))
            .path,
      );

      final result = await kobold.launch(
        exe,
        pickedModel: liveEngineModel,
        port: port,
      );
      await waitForLiveModel(port);

      expect(result.message, contains('big.gguf'));
      expect(await liveContextSize(port), 2048);
      expect(b.lastUsedModelPath, liveEngineModel);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
