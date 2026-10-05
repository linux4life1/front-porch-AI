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

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_controller.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';
import 'loopback_kobold.dart';

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
    late KoboldRig rig;
    late String oldModel;
    late String newModel;

    setUp(() async {
      rig = await KoboldRig.start(root);
      oldModel = rig.gguf('old-model.gguf');
      newModel = rig.gguf('new-model.gguf');
      await rig.storage.backendSettings.setLastUsedModelPath(oldModel);
    });

    tearDown(() => rig.close());

    /// A preset that names [newModel], written in the engine folder and
    /// chosen.
    Future<void> presetOwningTheNewModel() async {
      final file = rig.preset('Owns.kcpps', {
        'model_param': newModel,
        'contextsize': 8192,
      });
      await rig.storage.backendSettings.setActiveKcppsPath(file.path);
    }

    test('that loads a preset naming another model makes it the model in '
        'use', () async {
      await presetOwningTheNewModel();
      expect(rig.storage.backendSettings.lastUsedModelPath, oldModel);

      await rig.provider.reloadChatKobold();

      expect(rig.engine.model, 'koboldcpp/new-model');
      expect(rig.storage.backendSettings.lastUsedModelPath, newModel);
      expect(rig.kobold.requestModel, newModel);
    });

    test('that KoboldCpp could not load leaves the model in use as it '
        'was', () async {
      await presetOwningTheNewModel();
      rig.engine.failing.add(kStagedChatConfig);

      await rig.provider.reloadChatKobold();

      expect(rig.engine.model, 'koboldcpp/startup-model');
      expect(
        rig.kobold.launches,
        1,
        reason: 'a failed reload falls back to a start',
      );
      expect(rig.storage.backendSettings.lastUsedModelPath, oldModel);
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
