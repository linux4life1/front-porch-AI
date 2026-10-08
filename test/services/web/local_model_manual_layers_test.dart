// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the phone's "Local model" card is sent with "Set layers myself" on:
// the desktop card's own facts (KoboldStatusFacts), so it says "Set up by
// hand in Advanced settings." with the speed and the context verdicts of
// the layer count set, not of KoboldCpp's fit. A real Llama 3.1 8B file on
// an RTX 4090's figures, 10 layers on the card.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Models extends FakeModelManager {
  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

class _Hardware extends FakeHardwareService {
  _Hardware()
    : super(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4090',
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  @override
  FreeMemoryMb? get freeBeforeEngine => (graphics: 23000, system: 60000);

  @override
  set freeBeforeEngine(FreeMemoryMb? value) {}
}

class _Kobold extends FakeKoboldService {
  @override
  bool get isProcessRunning => false;
}

class _Llm extends FakeLLMProvider {
  final kobold = _Kobold();

  @override
  KoboldService get koboldService => kobold;
}

void main() {
  late Directory dir;
  late FakeStorageService storage;
  late BackendFacade facade;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai web manual layers');
    storage = FakeStorageService();
    facade = BackendFacade(_Llm(), storage, _Models(), _Hardware());
    const fx = 'test/fixtures/gguf_headers/Llama-3.1-8B';
    final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
    final model = p.join(dir.path, 'Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    final b = storage.backendSettings;
    await b.setLastUsedModelPath(model);
    await b.setContextSize(16384);
    await b.setGpuLayers(10);
    await b.setGpuLayersManual(true);
  });

  tearDown(() => dir.delete(recursive: true));

  test('the phone is told the layers were set by hand, and their '
      'verdicts', () async {
    final sent =
        jsonDecode(jsonEncode(await facade.localModel()))
            as Map<String, dynamic>;
    final auto = sent['auto'] as Map<String, dynamic>;

    expect(
      (auto['lines'] as List).first,
      'Set up by hand in Advanced settings. Much of the model runs from '
      'system memory, so replies come slowly.',
    );
    expect((auto['verdicts'] as Map)['131072']['outcome'], 'tooBig');
    expect(auto['largestGood'], 65536);
  });
}
