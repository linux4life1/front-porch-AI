// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the phone's "Local model" card is sent about how much context to
// offer: up to the length the model was made for (the desktop card's own
// facts, KoboldStatusFacts), with the size in use, and for a model made for
// less than 16,384 tokens a plain warning. Real model files: an 8k model
// (Llama 3.2's header saying 8,192) and Qwen3.6 35B, made for 262,144.

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
import '../../helpers/short_model_file.dart';

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
  late _Storage storage;
  late BackendFacade facade;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai web short model');
    storage = _Storage(dir);
    facade = BackendFacade(_Llm(), storage, _Models(), _Hardware());
    await storage.backendSettings.setContextSize(16384);
  });

  tearDown(() => dir.delete(recursive: true));

  /// The card's auto section as the phone is sent it, for [model].
  Future<Map<String, dynamic>> autoFor(String model) async {
    await storage.backendSettings.setLastUsedModelPath(model);
    final sent =
        jsonDecode(jsonEncode(await facade.localModel()))
            as Map<String, dynamic>;
    return sent['auto'] as Map<String, dynamic>;
  }

  test('an 8k model: the choices stop at 8,192 beside the size in use, and '
      'the card is told why', () async {
    final auto = await autoFor(await writeShortModel(dir, contextLength: 8192));

    expect(auto['choices'], [8192, 16384]);
    expect(
      auto['warning'],
      'This model was made for 8,192 tokens of chat. Front Porch needs at '
      'least 16,384, so it may not work well here. A model made for longer '
      'chats is recommended.',
    );
  });

  test('a model made for 262,144 tokens is offered all of it, with no '
      'warning', () async {
    const fx = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-Q4_K_XL';
    final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
    final model = p.join(dir.path, 'Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();

    final auto = await autoFor(model);

    expect((auto['choices'] as List).last, 262144);
    expect(auto['verdicts'], contains('262144'));
    expect(auto['warning'], isNull);
  });
}
