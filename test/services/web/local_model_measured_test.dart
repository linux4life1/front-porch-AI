// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's Local model card judges each context size with what the speed
// test measured for the model, as the desktop's card and the launch do: on a
// 16 GB NVIDIA card, Llama 3.1 8B with flash attention off (measured faster
// there) is too big at 65,536 tokens, where auto mode's own settings make it
// only a little slower. The model is a real header grown to its real size;
// the preset is written by the app's own writer, as the speed test saves it.

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

const _card = 'NVIDIA GeForce RTX 4080';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Models extends FakeModelManager {
  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

class _Hardware extends FakeHardwareService {
  _Hardware()
    : super(
        hardwareInfo: HardwareInfo(
          gpuName: _card,
          vramMb: 16376,
          ramMb: 32768,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  @override
  FreeMemoryMb? get freeBeforeEngine => (graphics: 16000, system: 28000);

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
  late _Storage storage;
  late BackendFacade facade;
  late String model;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai web card measured');
    storage = _Storage(dir);
    facade = BackendFacade(_Llm(), storage, _Models(), _Hardware());
    const fx = 'test/fixtures/gguf_headers/Llama-3.1-8B';
    final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
    model = p.join(dir.path, 'Llama-3.1-8B-Instruct-Q4_K_M.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    await storage.backendSettings.setBackendType('kobold');
    await storage.backendSettings.setLastUsedModelPath(model);
    await storage.backendSettings.setContextSize(32768);
  });

  tearDown(() => dir.delete(recursive: true));

  Future<String?> outcomeAt64k() async {
    final card = await facade.localModel();
    final verdicts = (card['auto'] as Map)['verdicts'] as Map;
    return (verdicts['65536'] as Map?)?['outcome'] as String?;
  }

  test("auto mode's own settings: a little slower at 65,536", () async {
    expect(await outcomeAt64k(), KoboldContextOutcome.littleSlower.name);
  });

  test('measured with flash attention off here: too big at 65,536', () async {
    final path = await KcppsLibrary(dir.path).write(
      koboldMeasuredPresetName(model, _card),
      kcppsMap(
        KoboldLaunchConfig(
          modelPath: model,
          contextSize: 32768,
          flashAttention: false,
          backend: KoboldGpuBackend.cuda,
          gpuId: 0,
          measured: const KoboldMeasured(
            card: _card,
            backend: 'cuda',
            auto: true,
          ),
        ),
      ),
    );
    await storage.presetSettings.setModelPreset(model, path);
    expect(await outcomeAt64k(), KoboldContextOutcome.tooBig.name);
  });
}
