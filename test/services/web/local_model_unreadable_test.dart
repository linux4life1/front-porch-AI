// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The phone's "Local model" card for a model whose file cannot be read: it
// says so (the card used to say "Reading the model file…" for ever), and
// reads again once the file is back. A real header grown to its real size
// as a sparse file stands for the model.

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
          gpuName: 'NVIDIA GeForce GTX 1060 6GB',
          vramMb: 6144,
          ramMb: 16384,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      );

  FreeMemoryMb? _free = (graphics: 5222, system: 11063);

  @override
  FreeMemoryMb? get freeBeforeEngine => _free;

  @override
  set freeBeforeEngine(FreeMemoryMb? value) => _free = value;
}

class _Llm extends FakeLLMProvider {
  @override
  KoboldService get koboldService => FakeKoboldService();
}

void main() {
  late Directory dir;
  late _Storage storage;
  late BackendFacade facade;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai web card unreadable');
    storage = _Storage(dir);
    facade = BackendFacade(_Llm(), storage, _Models(), _Hardware());
  });

  tearDown(() => dir.delete(recursive: true));

  Future<void> putModel(String path) async {
    const fx = 'test/fixtures/gguf_headers/Llama-3.2-3B';
    final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
    final raf = await File(path).open(mode: FileMode.write);
    await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
  }

  test('a model file that is gone says so, and is read again when it is '
      'back', () async {
    final model = p.join(dir.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    await storage.backendSettings.setLastUsedModelPath(model);
    await storage.backendSettings.setContextSize(16384);

    final gone = await facade.localModel();
    expect(gone['model'], model);
    expect(gone['auto'], isNull);
    expect(gone['modelUnreadable'], isTrue);

    await putModel(model);
    final back = await facade.localModel();
    expect(back['modelUnreadable'], isFalse);
    expect((back['auto'] as Map)['context'], 16384);
  });

  test('no model chosen is not an unreadable one', () async {
    final card = await facade.localModel();
    expect(card['auto'], isNull);
    expect(card['modelUnreadable'], isFalse);
  });
}
