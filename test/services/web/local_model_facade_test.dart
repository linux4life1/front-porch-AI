// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What the phone's "Local model" card and chat-preset picker get from the
// server, and what they may set. The model is a real header grown to its
// real size (a sparse file); the presets are real files in the engine
// folder.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

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
  late String preset;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai web card');
    const fx = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-Q4_K_XL';
    final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
    final model = p.join(dir.path, 'Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    preset = p.join(dir.path, 'Long chats.kcpps');
    File(preset).writeAsStringSync(
      jsonEncode({
        'model_param': model,
        'contextsize': 32768,
        'gpulayers': -1,
        'autofit': true,
        'noswa': true,
      }),
    );
    storage = _Storage(dir);
    await storage.backendSettings.setLastUsedModelPath(model);
    await storage.backendSettings.setContextSize(16384);
    facade = BackendFacade(_Llm(), storage, _Models(), _Hardware());
  });

  tearDown(() => dir.delete(recursive: true));

  test(
    'auto mode: the plain lines and a verdict for every context size',
    () async {
      final card = await facade.localModel();
      expect(card['modelName'], 'Qwen3.6 35B A3B');
      expect(card['preset'], isNull);
      final auto = card['auto'] as Map;
      expect(
        auto['lines'],
        contains(
          'Set up for this computer automatically. The model is bigger than '
          'your graphics card, so replies come at about reading pace.',
        ),
      );
      expect(auto['context'], 16384);
      expect(auto['largestGood'], 65536);
      final verdicts = auto['verdicts'] as Map;
      expect(verdicts['8192']['title'], 'Not recommended or supported.');
      expect(verdicts['16384']['title'], 'Works like now.');
      expect(verdicts['131072']['outcome'], 'tooBig');
      expect(
        verdicts['131072']['text'],
        contains('The most that works well here is 65,536.'),
      );
      expect((card['presets'] as List).single, {
        'path': preset,
        'name': 'Long chats',
        'line': '32k chat · fitted to the card · smart cache off',
      });
    },
  );

  test('a preset in the engine folder can be chosen, and cleared', () async {
    expect(await facade.setChatPreset(preset), isTrue);
    expect(storage.backendSettings.activeKcppsPath, preset);
    final card = await facade.localModel();
    expect(card['auto'], isNull);
    expect((card['preset'] as Map)['name'], 'Long chats');
    expect(
      (card['preset'] as Map)['words'],
      contains('lets KoboldCpp fit it to your card'),
    );

    expect(await facade.setChatPreset(null), isTrue);
    expect(storage.backendSettings.activeKcppsPath, isNull);
  });

  test('no other path is taken: the server may be reachable from the '
      'internet', () async {
    final outside = File(p.join(Directory.systemTemp.path, 'x.kcpps'))
      ..writeAsStringSync('{}');
    addTearDown(outside.deleteSync);
    expect(await facade.setChatPreset(outside.path), isFalse);
    expect(await facade.setChatPreset('/etc/passwd'), isFalse);
    expect(storage.backendSettings.activeKcppsPath, isNull);
  });

  test('the context is set within its range only', () async {
    expect(await facade.setLocalContext(32768), isTrue);
    expect(storage.backendSettings.contextSize, 32768);
    expect(await facade.setLocalContext(100), isFalse);
    expect(await facade.setLocalContext(5000000), isFalse);
    expect(storage.backendSettings.contextSize, 32768);
  });
}
