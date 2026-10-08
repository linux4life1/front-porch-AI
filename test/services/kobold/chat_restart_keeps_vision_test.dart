// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Putting chat back after a swap by starting the engine again (the reload
// failed, or was not acted on) must start the same thing a reload would
// have: chat's model as the launch rule gives it now, with its vision file.
// When the active preset names its own model, that is not the last model
// picked, and the restart used to leave the vision file out.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// Records the start a swap asks for instead of running an engine.
class _Service extends KoboldService {
  _Service(super.storage);
  final List<({String model, String? mmproj})> starts = [];

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
    starts.add((model: modelPath, mmproj: mmprojPath));
    return const KoboldLaunchResult.started();
  }
}

class _Engine extends BackendManager {
  _Engine(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory dir;

  String file(String name, [List<int>? bytes]) {
    final f = File(p.join(dir.path, name))..createSync(recursive: true);
    f.writeAsBytesSync(bytes ?? 'GGUF'.codeUnits + List.filled(32, 0));
    return f.path;
  }

  setUp(() async {
    storage = await createStorageService();
    dir = Directory.systemTemp.createTempSync('fpai chat restart');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('a restart that puts chat back on a preset\'s own model keeps its '
      'vision file', () async {
    final owned = file('owned.gguf');
    final picked = file('picked-earlier.gguf');
    final vision = file('owned-mmproj.gguf');
    final preset = file(
      'owner.kcpps',
      utf8.encode(jsonEncode({'model_param': owned, 'contextsize': 2048})),
    );
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await b.setLastUsedModelPath(picked);
    await b.setActiveKcppsPath(preset);
    await storage.presetSettings.setModelMmproj(owned, vision);

    final kobold = _Service(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Engine(storage, file('koboldcpp')),
    );
    addTearDown(provider.dispose);

    await provider.ensureManagedBackendIsRunning(
      forGpuSwap: true,
      modelPath: owned,
      kcppsPath: preset,
    );

    expect(kobold.starts.single, (model: owned, mmproj: vision));
  });
}
