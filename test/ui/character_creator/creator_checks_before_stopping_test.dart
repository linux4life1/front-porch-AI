// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The character creator's model change asks whether the start can go ahead
// BEFORE it stops the running KoboldCpp, as the desktop's Start and Restart
// buttons do. It used to stop the working engine first and then have the
// start refused, leaving chat with no engine. Now a model or preset that
// cannot be used leaves the engine running, and the creator says why where it
// says how a start went.
//
// The launch is the real one (the real rule for which model loads, the real
// checks); only the spawn of the engine process and the stop are counted.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:path/path.dart' as p;

import '../../golden/support/fakes.dart';
import '../../services/kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// A KoboldCpp that is running, whose stops and spawns are counted.
class _Running extends KoboldService {
  _Running(super.storage);
  bool running = true;
  int stops = 0;
  final List<String> startedModels = [];

  @override
  bool get isRunning => running;

  @override
  bool get modelReady => startedModels.isNotEmpty;

  @override
  Future<void> stopKobold() async {
    stops++;
    running = false;
  }

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
    startedModels.add(modelPath);
    running = true;
    return const KoboldLaunchResult.started();
  }
}

class _Llm extends FakeLLMProvider {
  _Llm(this._kobold);
  final KoboldService _kobold;

  @override
  KoboldService get koboldService => _kobold;
}

class _Engine extends ChangeNotifier implements BackendManager {
  _Engine(this.backendPath);

  @override
  final String? backendPath;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late Directory dir;
  late StorageService storage;
  late _Running kobold;
  late CreatorState state;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('fpai creator checks first');
    storage = await createStorageService();
    kobold = _Running(storage);
    state = CreatorState();
  });

  tearDown(() {
    state.dispose();
    kobold.dispose();
    dir.deleteSync(recursive: true);
  });

  String file(String name, List<int> bytes) =>
      (File(p.join(dir.path, name))..writeAsBytesSync(bytes)).path;

  Future<void> reload(String picked, {String? engine}) =>
      state.reloadKoboldWithModel(
        picked,
        _Llm(kobold),
        storage,
        _Engine(engine ?? p.join(dir.path, 'koboldcpp')),
      );

  test('a model that is not one: the running engine is not stopped, and the '
      'creator says why', () async {
    final picked = file('notes.gguf', 'XXXX'.codeUnits + List.filled(32, 0));

    await reload(picked);

    expect(kobold.stops, 0, reason: 'the working engine was left alone');
    expect(kobold.isRunning, isTrue);
    expect(kobold.startedModels, isEmpty);
    expect(state.koboldStatus, contains('Not a valid GGUF'));
    expect(state.isReloadingKobold, isFalse);
  });

  test('a preset the app will not start from: the running engine is not '
      'stopped, and the creator says why', () async {
    final picked = file('picked.gguf', 'GGUF'.codeUnits + List.filled(32, 0));
    final preset = File(p.join(dir.path, 'Theirs.kcpps'))
      ..writeAsStringSync(
        jsonEncode({'mcpfile': 'https://example.com/servers.json'}),
      );
    await storage.backendSettings.setActiveKcppsPath(preset.path);

    await reload(picked);

    expect(kobold.stops, 0);
    expect(kobold.startedModels, isEmpty);
    expect(state.koboldStatus, contains('mcpfile'));
  });

  test('with nothing in the way, the engine is stopped and the picked model '
      'started, as before', () async {
    final picked = file('picked.gguf', 'GGUF'.codeUnits + List.filled(32, 0));

    await reload(picked);

    expect(kobold.stops, 1);
    expect(kobold.startedModels, [picked]);
    expect(state.koboldStatus, 'Model loaded successfully!');
  });
}
