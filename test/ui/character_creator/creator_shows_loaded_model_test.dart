// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The character creator's model picker shows the model that loaded.
//
// A launch loads the active preset's own model when it has one on this
// computer, whatever was picked. The creator used to show the picked model
// as loaded even then. It now shows the model the launch recorded.
//
// The launch here is the real one (the real rule for which model loads, the
// real record of it); only the start of the engine process is counted
// instead of run.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:path/path.dart' as p;

import '../../golden/support/fakes.dart';
import '../../services/kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

class _Kobold extends KoboldService {
  _Kobold(super.storage);
  final List<String> startedModels = [];

  @override
  bool get modelReady => startedModels.isNotEmpty;

  @override
  Future<KoboldLaunchResult> startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) async {
    startedModels.add(modelPath);
    return const KoboldLaunchResult.started();
  }
}

class _Llm extends FakeLLMProvider {
  _Llm(this._kobold);
  final KoboldService _kobold;

  @override
  KoboldService get koboldService => _kobold;
}

class _Engine extends ChangeNotifier implements BackendManager {
  _Engine(this.backendPath);

  @override
  final String? backendPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late Directory dir;
  late StorageService storage;
  late _Kobold kobold;
  late CreatorState state;

  String model(String name) => (File(
    p.join(dir.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fpai creator model');
    storage = await createStorageService();
    kobold = _Kobold(storage);
    state = CreatorState();
  });

  tearDown(() {
    state.dispose();
    kobold.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> reload(String picked) => state.reloadKoboldWithModel(
    picked,
    _Llm(kobold),
    storage,
    _Engine(p.join(dir.path, 'koboldcpp')),
  );

  test('with a preset that owns another model, the creator shows that '
      'model, not the one picked', () async {
    final picked = model('picked.gguf');
    final owned = model('owned-by-preset.gguf');
    final preset = File(p.join(dir.path, 'owner.kcpps'))
      ..writeAsStringSync('{"model_param": "$owned", "noswa": true}');
    await storage.backendSettings.setActiveKcppsPath(preset.path);

    await reload(picked);

    expect(kobold.startedModels, [owned], reason: 'the preset\'s own model');
    expect(state.selectedLocalModelPath, owned);
    expect(state.koboldStatus, 'Model loaded successfully!');
  });

  test('with no preset, the creator shows the model picked', () async {
    final picked = model('picked.gguf');

    await reload(picked);

    expect(kobold.startedModels, [picked]);
    expect(state.selectedLocalModelPath, picked);
  });
}
