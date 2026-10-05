// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A first launch can start before the graphics card has been detected. It
// waits for the detection (that is how it learns which backend to use), and
// what it learned must reach everything that is worked out from the machine:
// the batch, the smart cache slots and MMQ. They were once worked out from
// the hardware the caller had at the start, which was none, so that launch
// ran untuned.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// A real model header grown to its real size (a sparse file).
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

final _nvidia = HardwareInfo(
  gpuName: 'NVIDIA GeForce RTX 4080',
  vramMb: 16384,
  ramMb: 32768,
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
    dir = Directory.systemTemp.createTempSync('fpai awaited hardware');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, dynamic>> launch(
    String model, {
    HardwareInfo? hardware,
    Future<HardwareInfo?> Function()? awaitHardware,
  }) async {
    final args = await buildKoboldLaunchArgs(
      storage: storage,
      executablePath: p.join(dir.path, 'koboldcpp'),
      modelPath: model,
      kcppsPath: null,
      mmprojPath: null,
      port: 5001,
      gpuLayers: 0,
      contextSize: 16384,
      useVulkan: false,
      useCublas: false,
      useMetal: false,
      useRocm: false,
      hardware: hardware,
      awaitHardware: awaitHardware,
      free: (graphics: 16000, system: 28000),
    );
    return (jsonDecode(
              File(args[args.indexOf('--config') + 1]).readAsStringSync(),
            )
            as Map)
        .cast<String, dynamic>();
  }

  test('a launch that waited for the card is tuned for it, as one that '
      'knew it at once', () async {
    final model = await _model(dir, 'Qwen3-14B');
    final known = await launch(model, hardware: _nvidia);
    // The tuning is real here: a model that fits with room gets the
    // largest batch, three slots, and MMQ timed first.
    expect(known['batchsize'], 2048);
    expect(known['smartcache'], 3);
    expect(known['nommq'], isFalse);

    final waited = await launch(model, awaitHardware: () async => _nvidia);
    expect(waited, known);
  });

  test('a launch that finds no card is not tuned, and still starts', () async {
    final model = await _model(dir, 'Qwen3-14B');
    final config = await launch(model, awaitHardware: () async => null);
    expect(config['batchsize'], 512);
    expect(config.containsKey('smartcache'), isFalse);
    expect(config.containsKey('nommq'), isFalse);
  });
}
