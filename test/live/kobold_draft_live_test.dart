// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The editor's draft settings against a real KoboldCpp: a preset made in the
// editor with a draft model and tokens guessed each step is launched and
// writes, and the model's own draft heads turned on for a model without
// them still loads and writes. Run with:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_draft_live_test.dart

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

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late HardwareService hardware;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai draft live');
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
  });

  tearDown(() async {
    await kobold.stopKobold();
    hardware.dispose();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  /// A preset made and saved in the editor, chosen for chat.
  Future<void> editorPreset(
    String name,
    KcppsDraft Function(KcppsDraft d) change,
  ) async {
    final c = KcppsEditorController(
      storage: storage,
      hardware: hardware,
      kobold: kobold,
      models: [liveEngineModel],
    );
    addTearDown(c.dispose);
    await c.init();
    c.edit(
      (d) => change(
        d.copyWith(name: name, modelPath: liveEngineModel, contextSize: 4096),
      ),
    );
    expect(await c.save(), KcppsSaveResult.saved);
    await storage.backendSettings.setActiveKcppsPath(c.path);
  }

  /// Starts KoboldCpp on chat's preset and has it write a few tokens.
  Future<String> startAndWrite() async {
    expect((await kobold.launch(exe, port: port)).started, isTrue);
    await waitForLiveModel(port);
    for (var i = 0; i < 120 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(kobold.modelReady, isTrue);
    final reply = await livePost(port, '/api/v1/generate', {
      'prompt': 'The porch light hums. Count from one to ten: one, two,',
      'max_length': 24,
      'temperature': 0.1,
    });
    final text = ((reply as Map?)?['results'] as List?)?.first['text'];
    return text?.toString() ?? '';
  }

  Map<String, dynamic> stagedChat() =>
      (readKcpps(
                File(
                  p.join(koboldAdminDirFor(storage), kStagedChatConfig),
                ).readAsStringSync(),
              )
              as KcppsOk)
          .raw;

  test(
    'a draft model with 3 tokens guessed each step: launched, and it writes',
    () async {
      await editorPreset(
        'Drafting',
        (d) => d.copyWith(draftModelPath: liveEngineModel, draftAmount: 3),
      );

      final text = await startAndWrite();

      final staged = stagedChat();
      expect(staged['draftmodel'], liveEngineModel);
      expect(staged['draftamount'], 3);
      expect(text.trim(), isNotEmpty);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'the draft heads turned on for a model without them: it still loads '
    'and writes',
    () async {
      await editorPreset(
        'Heads',
        (d) => d.copyWith(useMtp: true, draftAmount: 2),
      );

      final text = await startAndWrite();

      final staged = stagedChat();
      expect(staged['usemtp'], isTrue);
      expect(staged['draftamount'], 2);
      expect(text.trim(), isNotEmpty);
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
