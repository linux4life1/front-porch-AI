// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset written by "Generate preset", launched by the app against a REAL
// KoboldCpp. The dialog's VRAM estimate counts on the graphics memory the
// fit leaves spare (1024 MB, or 32 MB with "Greedy memory allocation");
// KoboldCpp keeps a preset's padding only when the fit is forced, so the
// engine itself is asked what it was started with. Skipped unless
// KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL are set; see
// kobold_engine_live_test.dart.

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
    final temp = await Directory.systemTemp.createTemp('fpai generated live');
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

  /// What KoboldCpp says it was started with: it lists every setting.
  String? received(String name) => RegExp(
    '\\b${RegExp.escape(name)}=([^,)]+)',
  ).firstMatch(kobold.logs.join('\n'))?.group(1);

  /// Writes the preset as the dialog does and launches with it.
  Future<void> launchGenerated({required bool greedy}) async {
    final preset = File(p.join(storage.binDir.path, 'generated.kcpps'))
      ..writeAsStringSync(
        encodeKcpps(
          kcppsMap(
            koboldGeneratedPreset(
              modelPath: liveEngineModel,
              contextSize: 4096,
              batchSize: 512,
              threads: 4,
              greedyAllocation: greedy,
              kvQuant: KvQuant.f16,
              backend: KoboldGpuBackend.none,
              gpuId: null,
              contextMode: ContextManagementMode.fastForwardSmartCache,
              smartCacheSlots: 0,
            ),
          ),
        ),
      );
    await kobold.startKobold(
      exe,
      liveEngineModel,
      kcppsPath: preset.path,
      port: port,
      gpuLayers: storage.backendSettings.gpuLayers,
      contextSize: storage.backendSettings.contextSize,
      useMetal: Platform.isMacOS,
    );
    await waitForLiveModel(port);
  }

  Map<String, dynamic> staged() =>
      (jsonDecode(
                File(
                  p.join(koboldAdminDirFor(storage), kStagedChatConfig),
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, dynamic>();

  test(
    '"Greedy memory allocation": the real engine fits the model itself and '
    'keeps 32 MB spare, as the estimate counted on',
    () async {
      await launchGenerated(greedy: true);

      expect(received('autofit'), 'True');
      expect(received('autofitpadding'), '32');
      expect(received('gpulayers'), isNot('0'));
      expect(staged()['autofitpadding'], 32);
      expect(await liveContextSize(port), 4096);

      final reply = await livePost(port, '/api/v1/generate', {
        'prompt': 'Count: one, two, three,',
        'max_length': 8,
      });
      expect(
        ((reply as Map)['results'] as List).single['text'],
        isNotEmpty,
        reason: 'the model loaded from the generated preset generates',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'without "Greedy", the real engine fits the model and keeps 1024 MB '
    'spare',
    () async {
      await launchGenerated(greedy: false);

      expect(received('autofit'), 'True');
      expect(received('autofitpadding'), '1024');
      expect(await liveContextSize(port), 4096);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
