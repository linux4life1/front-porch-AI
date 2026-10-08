// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Save and use now" makes the saved preset chat's and links it to its model
// before it asks the running KoboldCpp to load it. When KoboldCpp could not
// load it and the old model is kept running, the choice goes back to what
// runs: the preset stays saved, but it is not chat's, and the link the save
// wrote for the running model is the running preset again.
//
// The real editor controller on the real reload (see
// kobold_reload_puts_choice_back_test), against a KoboldCpp on loopback that
// goes back to its own model for a config it cannot load.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

import '../../golden/support/fakes_services.dart';
import '../../services/kobold/loopback_kobold.dart';

void main() {
  late Directory root;
  late KoboldRig rig;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai editor kept reload');
    rig = await KoboldRig.start(root);
  });

  tearDown(() async {
    await rig.close();
    root.deleteSync(recursive: true);
  });

  test('the saved preset is not chat\'s after a reload that was refused, and '
      'the running model has its own preset back', () async {
    final oldModel = rig.gguf('old.gguf');
    final oldPreset = rig.preset('Old.kcpps', {'contextsize': 8192}).path;
    // Not a GGUF: a fresh start would be refused, so the engine is kept.
    final broken = (File(
      p.join(root.path, 'broken.gguf'),
    )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;
    final edited = rig.preset('Edited.kcpps', {
      'model_param': broken,
      'contextsize': 16384,
    });
    final b = rig.storage.backendSettings;
    await b.setLastUsedModelPath(oldModel);
    await b.setActiveKcppsPath(oldPreset);
    await rig.storage.presetSettings.setModelPreset(oldModel, oldPreset);
    rig.kobold.noteAdminLoadedPair(modelPath: oldModel, kcppsPath: oldPreset);
    rig.engine.model = rig.engine.startupModel = 'koboldcpp/old';
    rig.engine.failing.add(kStagedChatConfig);

    final c = KcppsEditorController(
      storage: rig.storage,
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4090',
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      ),
      kobold: rig.kobold,
      reloadChat: rig.provider.reloadChatKobold,
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (_) async => (info: null, bytes: 0),
      unified: false,
      threads: () async => 4,
    );
    addTearDown(c.dispose);
    await c.init();
    await c.select(edited.path);
    expect(c.path, edited.path);

    final result = await c.saveAndUse();

    expect(result.name, 'notLoaded');
    expect(c.problem, contains('The previous one is still running'));
    expect(File(edited.path).existsSync(), isTrue, reason: 'it is saved');
    expect(b.lastUsedModelPath, oldModel);
    expect(b.activeKcppsPath, oldPreset);
    expect(rig.storage.presetSettings.modelPresetMap[oldModel], oldPreset);
  });
}
