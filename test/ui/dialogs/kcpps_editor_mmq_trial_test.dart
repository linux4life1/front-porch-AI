// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Timing MMQ in the preset editor loads the preset into the running
// KoboldCpp twice, with MMQ on and off. What it loads must be what the
// preset would run on this machine: on a ROCm build that already died with
// flash attention on, that is flash attention off, not the setting that
// killed it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Running extends FakeKoboldService {
  @override
  bool get isRunning => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late FakeStorageService storage;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor mmq trial');
    storage = _Storage(bin);
  });

  tearDown(() => bin.delete(recursive: true));

  /// The config the editor loads for the first trial (MMQ on) of a CUDA
  /// preset with a compressed cache and flash attention on.
  Future<Map<String, dynamic>> firstTrial() async {
    final file = File(p.join(bin.path, 'Mine.kcpps'));
    await file.writeAsString(
      jsonEncode({
        'contextsize': 16384,
        'usecuda': ['normal', '0'],
        'quantkv': 'q8_0',
        'noflashattention': false,
      }),
    );
    final loaded = <String, dynamic>{};
    final c = KcppsEditorController(
      storage: storage,
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'AMD Radeon RX 6900 XT',
          vramMb: 16384,
          ramMb: 32768,
          vendor: 'AMD',
          hasRocm: true,
        ),
      ),
      kobold: _Running(),
      // The trial is taken as not loaded, which ends the timing there: the
      // config it was given is what is looked at.
      loadTrial: (name, config) async {
        if (loaded.isEmpty) loaded.addAll(config);
        return false;
      },
      readFree: () async => (graphics: 15000, system: 20000),
      readModel: (_) async => (info: null, bytes: 0),
      unified: false,
      threads: () async => 4,
    );
    addTearDown(c.dispose);
    await c.select(file.path);
    await c.timeMmq();
    return loaded;
  }

  test('on a ROCm build that died with flash attention on, the trial runs '
      'without it, and with the cache at full size', () async {
    await storage.backendSettings.setUseRocm(true);
    await storage.backendSettings.setRocmFlashAttentionFailed(true);
    final trial = await firstTrial();
    expect(trial['noflashattention'], isTrue);
    expect(trial['quantkv'], 'f16');
    expect(trial['nommq'], isFalse, reason: 'the first trial is MMQ on');
  });

  test('where flash attention has not failed, the trial keeps it', () async {
    await storage.backendSettings.setUseRocm(true);
    final trial = await firstTrial();
    expect(trial['noflashattention'], isFalse);
    expect(trial['quantkv'], 'q8_0');
  });

  test('a timing asked for while the model file is still read loads '
      'nothing: the trial is built from its header', () async {
    final file = File(p.join(bin.path, 'Mine.kcpps'));
    await file.writeAsString(
      jsonEncode({
        'contextsize': 16384,
        'usecuda': ['normal', '0'],
      }),
    );
    final slow = p.join(bin.path, 'slow.gguf');
    final reading = Completer<void>();
    var trials = 0;
    final c = KcppsEditorController(
      storage: storage,
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4090',
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      ),
      kobold: _Running(),
      loadTrial: (name, config) async {
        trials++;
        return false;
      },
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (path) async {
        if (path == slow) await reading.future;
        return (info: null, bytes: 0);
      },
      unified: false,
      threads: () async => 4,
    );
    addTearDown(c.dispose);
    await c.select(file.path);

    final picking = c.setModel(slow);
    await c.timeMmq();
    expect(trials, 0);

    reading.complete();
    await picking;
    await c.timeMmq();
    expect(trials, 1, reason: 'once the file is read, the timing runs');
  });
}
