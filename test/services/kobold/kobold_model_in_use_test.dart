// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The model KoboldCpp was given is the app's one record of "which model"
// (the status card, the vision lookup, the thinking settings, an automatic
// restart and the phone's "loaded" marker all read it). A launch records it.
// So must a live reload of chat's new preset, and Save and use now: a preset
// that names another model used to load it while every screen went on
// naming the old one until the next full launch.
//
// The engine is a real HTTP server on loopback (see loopback_kobold.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_controller.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';
import 'loopback_kobold.dart';

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The app's KoboldCpp service with the process left out. A fresh start
/// (what chat falls back to when a reload fails) is counted, not run.
class _Kobold extends KoboldService {
  _Kobold(super.storage);

  bool running = true;
  int launches = 0;

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  bool get isRunning => running;

  @override
  bool get isProcessRunning => running;

  @override
  Future<void> stopKobold() async => running = false;

  @override
  Future<KoboldLaunchResult> launch(
    String executablePath, {
    String? pickedModel,
    int port = 5001,
  }) async {
    launches++;
    running = true;
    return const KoboldLaunchResult.started();
  }
}

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

void main() {
  late Directory root;

  /// A file with the GGUF magic, enough for the app's model check.
  String gguf(String name) => (File(
    p.join(root.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('fpai model in use');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('a live reload of chat', () {
    late StorageService storage;
    late LoopbackKobold engine;
    late _Kobold kobold;
    late LLMProvider provider;
    late String oldModel;
    late String newModel;

    setUp(() async {
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
      await storage.backendSettings.setBackendType('kobold');
      await storage.binDir.create(recursive: true);
      oldModel = gguf('old-model.gguf');
      newModel = gguf('new-model.gguf');
      await storage.backendSettings.setLastUsedModelPath(oldModel);

      final adminDir = koboldAdminDirFor(storage);
      await Directory(adminDir).create(recursive: true);
      engine = await LoopbackKobold.start(adminDir);
      kobold = _Kobold(storage)..setBaseUrl(engine.baseUrl);
      provider = LLMProvider(
        kobold,
        OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
        storage,
        _Backend(storage, p.join(storage.binDir.path, 'koboldcpp')),
      );
    });

    tearDown(() async {
      provider.dispose();
      await engine.close();
    });

    /// A preset that names [newModel], written in the engine folder and
    /// chosen.
    Future<void> presetOwningTheNewModel() async {
      final file = File(p.join(storage.binDir.path, 'Owns.kcpps'))
        ..writeAsStringSync(
          jsonEncode({'model_param': newModel, 'contextsize': 8192}),
        );
      await storage.backendSettings.setActiveKcppsPath(file.path);
    }

    test('that loads a preset naming another model makes it the model in '
        'use', () async {
      await presetOwningTheNewModel();
      expect(storage.backendSettings.lastUsedModelPath, oldModel);

      await provider.reloadChatKobold();

      expect(engine.model, 'koboldcpp/new-model');
      expect(storage.backendSettings.lastUsedModelPath, newModel);
      expect(kobold.requestModel, newModel);
    });

    test('that KoboldCpp could not load leaves the model in use as it '
        'was', () async {
      await presetOwningTheNewModel();
      engine.failing.add(kStagedChatConfig);

      await provider.reloadChatKobold();

      expect(engine.model, 'koboldcpp/startup-model');
      expect(
        kobold.launches,
        1,
        reason: 'a failed reload falls back to a start',
      );
      expect(storage.backendSettings.lastUsedModelPath, oldModel);
    });
  });

  group('Save and use now', () {
    test('records the model the saved preset names, with no engine '
        'running to reload', () async {
      final oldModel = gguf('old-model.gguf');
      final newModel = gguf('new-model.gguf');
      final bin = Directory(p.join(root.path, 'bin'))..createSync();
      File(p.join(bin.path, 'Owns.kcpps')).writeAsStringSync(
        jsonEncode({'model_param': newModel, 'contextsize': 8192}),
      );
      final storage = _Storage(bin);
      await storage.backendSettings.setLastUsedModelPath(oldModel);
      var reloads = 0;
      final c = KcppsEditorController(
        storage: storage,
        hardware: FakeHardwareService(
          hardwareInfo: HardwareInfo(
            gpuName: 'NVIDIA GeForce RTX 4080',
            vramMb: 16384,
            ramMb: 32768,
            vendor: 'Nvidia',
            hasCuda: true,
          ),
        ),
        kobold: FakeKoboldService(),
        reloadChat: () async => reloads++,
        readFree: () async => (graphics: 15000, system: 28000),
        readModel: (path) async => (info: null, bytes: 1024),
        unified: false,
        threads: () async => 4,
      );
      addTearDown(c.dispose);
      await c.init();
      expect(c.path, endsWith('Owns.kcpps'));

      expect(await c.saveAndUse(), KcppsSaveResult.saved);

      expect(storage.backendSettings.activeKcppsPath, c.path);
      expect(storage.backendSettings.lastUsedModelPath, newModel);
      expect(reloads, 1);
    });
  });
}
