// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What auto mode writes for the machine it launches on: the batch, smart
// cache slots with context shift to match (for a model the app does not
// keep the chats of itself), MMQ while it is being learned, and the context
// chat's prompts are held to. The models are real headers
// grown to their real size (sparse files, so nothing is written).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

Future<String> _model(Directory dir, String fixture) async {
  const fx = 'test/fixtures/gguf_headers';
  final side = jsonDecode(File('$fx/$fixture.json').readAsStringSync()) as Map;
  final file = File(p.join(dir.path, '$fixture.gguf'));
  final raf = await file.open(mode: FileMode.write);
  await raf.writeFrom(File('$fx/$fixture.gguf').readAsBytesSync());
  await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
  await raf.writeByte(0);
  await raf.close();
  return file.path;
}

HardwareInfo _nvidia(int vramMb, int ramMb) => HardwareInfo(
  gpuName: 'NVIDIA GeForce RTX 4080',
  vramMb: vramMb,
  ramMb: ramMb,
  vendor: 'Nvidia',
  hasCuda: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late Directory dir;

  setUp(() async {
    storage = await createStorageService();
    dir = Directory.systemTemp.createTempSync('fpai auto launch');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, dynamic>> launch(
    String model, {
    required HardwareInfo hardware,
    required FreeMemoryMb free,
    int contextSize = 16384,
  }) async {
    final args = await buildKoboldLaunchArgs(
      storage: storage,
      executablePath: p.join(dir.path, 'koboldcpp'),
      modelPath: model,
      kcppsPath: null,
      mmprojPath: null,
      port: 5001,
      gpuLayers: 0,
      contextSize: contextSize,
      useVulkan: false,
      useCublas: true,
      useMetal: false,
      useRocm: false,
      hardware: hardware,
      free: free,
    );
    return (jsonDecode(
              File(args[args.indexOf('--config') + 1]).readAsStringSync(),
            )
            as Map)
        .cast<String, dynamic>();
  }

  test('a model that fits with room gets the largest batch and no smart '
      'cache (the app keeps its chats), and MMQ is timed on first', () async {
    final config = await launch(
      await _model(dir, 'Qwen3-14B'),
      hardware: _nvidia(16384, 32768),
      free: (graphics: 16000, system: 28000),
    );
    expect(config['batchsize'], 2048);
    expect(config.containsKey('smartcache'), isFalse);
    expect(config['noshift'], isFalse);
    expect(
      config['nommq'],
      isFalse,
      reason: "KoboldCpp's default, timed first",
    );
  });

  test('a batch chosen in Settings is kept', () async {
    await storage.backendSettings.setBatchAutomatic(false);
    await storage.backendSettings.setBlasBatchSize(768);
    final config = await launch(
      await _model(dir, 'Qwen3-14B'),
      hardware: _nvidia(16384, 32768),
      free: (graphics: 16000, system: 28000),
    );
    expect(config['batchsize'], 768);
  });

  test('a hybrid model on a machine with no memory to spare gets no slots, '
      'and context shift off so KoboldCpp adds none', () async {
    final config = await launch(
      await _model(dir, 'Qwen3.6-35B-A3B-Q4_K_XL'),
      hardware: _nvidia(6144, 16384),
      free: (graphics: 5222, system: 11063),
    );
    expect(config['batchsize'], 512);
    expect(config.containsKey('smartcache'), isFalse);
    expect(config['noshift'], isTrue);
  });

  test("chat's prompts are held to the context the engine is given", () async {
    await launch(
      await _model(dir, 'Qwen3-14B'),
      hardware: _nvidia(16384, 32768),
      free: (graphics: 16000, system: 28000),
      contextSize: 12288,
    );
    expect(storage.backendSettings.engineContextSize, 12288);
    expect(storage.backendSettings.promptContext(32768), 12288);
  });
}
