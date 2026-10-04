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
}
