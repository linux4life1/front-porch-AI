// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the phone's "Local model" card and preset card are told about a
// preset that never mentions sliding window, on a model that has it.
// KoboldCpp's own default switches sliding window on together with fast
// forward then, a pairing that degrades output; the phone, like the desktop,
// described such a preset as one that "starts replies fast on long chats"
// and nothing else. The sentence goes in the preset's plain words, which both
// phone cards print as they are.
//
// The model is a real header (Gemma 3 has a sliding window, Llama 3.2 has
// not) grown to its real size; the presets are real files in the engine
// folder; the JSON is what the phone would be sent.

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

  @override
  Future<KoboldLaunchResult?> reloadChatKobold() async => null;
}

void main() {
  late Directory dir;
  late _Storage storage;
  late BackendFacade facade;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai web card swa');
    storage = _Storage(dir);
    facade = BackendFacade(_Llm(), storage, _Models(), _Hardware());
  });

  tearDown(() => dir.delete(recursive: true));

  /// What the phone is sent for [preset] in use on the model whose header is
  /// [fixture]: the plain words of the preset, from the JSON as it travels.
  Future<String> wordsFor(String fixture, Map<String, dynamic> preset) async {
    const headers = 'test/fixtures/gguf_headers';
    final side =
        jsonDecode(File('$headers/$fixture.json').readAsStringSync()) as Map;
    final model = p.join(dir.path, '$fixture-Q4_K_M.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(File('$headers/$fixture.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    await storage.backendSettings.setLastUsedModelPath(model);
    final file = p.join(dir.path, 'Mine.kcpps');
    File(file).writeAsStringSync(
      jsonEncode({
        'model_param': model,
        'contextsize': 16384,
        'gpulayers': -1,
        'autofit': true,
        ...preset,
      }),
    );
    expect(await facade.setChatPreset(file), isTrue);

    final sent =
        jsonDecode(jsonEncode(await facade.localModel()))
            as Map<String, dynamic>;
    return (sent['preset'] as Map)['words'] as String;
  }

  test('a preset that says nothing about sliding window, on a model that has '
      'it, is described with the sentence', () async {
    final words = await wordsFor('gemma-3-12b-it', {});

    expect(words, contains(kSwaLeftToKoboldNote));
  });

  test('a preset that answers it says nothing more', () async {
    for (final answered in <Map<String, dynamic>>[
      {'noswa': true},
      {'noswa': false, 'nofastforward': true},
      {'useswa': true, 'nofastforward': true},
    ]) {
      expect(
        await wordsFor('gemma-3-12b-it', answered),
        isNot(contains('sliding window')),
        reason: '$answered',
      );
    }
  });

  test('a model without a sliding window has nothing to warn about', () async {
    expect(
      await wordsFor('Llama-3.2-3B', {}),
      isNot(contains('sliding window')),
    );
  });

  test('with fast forward off already, there is no pairing to warn '
      'about', () async {
    expect(
      await wordsFor('gemma-3-12b-it', {'nofastforward': true}),
      isNot(contains('sliding window')),
    );
  });
}
