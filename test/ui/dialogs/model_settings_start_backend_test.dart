// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Starting the engine from the Model Settings dialog. The dialog has no
// graphics-backend control, so it must not record a graphics choice: one
// never made means "pick from the hardware" at every launch, and recording
// four offs here used to turn that into a deliberate CPU-only.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Hardware extends FakeHardwareService {
  @override
  bool get cpuOnlyLowPerf => false;
}

class _Models extends FakeModelManager {
  _Models(this._models);
  final List<FileSystemEntity> _models;

  @override
  List<FileSystemEntity> get models => _models;
}

class _Engine extends ChangeNotifier implements BackendManager {
  @override
  String? get backendPath => '/engine/koboldcpp';

  @override
  bool get isDownloading => false;

  @override
  bool get isIntelMac => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records how the dialog asked for the engine to be started.
class _Kobold extends FakeKoboldService {
  final List<Map<String, Object?>> starts = [];

  @override
  Future<void> startKobold(
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
    starts.add({
      'model': modelPath,
      'cuda': useCublas,
      'vulkan': useVulkan,
      'metal': useMetal,
      'rocm': useRocm,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Opens the dialog on the local backend with one real model file picked.
  /// [presetText], when given, is written to a preset that is made active.
  Future<({FakeStorageService storage, _Kobold kobold, File model})> open(
    WidgetTester tester, {
    String? presetText,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A real file with the GGUF magic: the dialog checks it before starting.
    late Directory temp;
    late File model;
    File? preset;
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('fpai dialog start');
      model = File(p.join(temp.path, 'tiny.gguf'));
      await model.writeAsBytes('GGUF'.codeUnits + List.filled(64, 0));
      if (presetText != null) {
        preset = File(p.join(temp.path, 'mine.kcpps'));
        await preset!.writeAsString(presetText);
      }
    });
    addTearDown(() => temp.deleteSync(recursive: true));

    final storage = FakeStorageService();
    storage.backendSettings.setBackendType('local');
    if (preset != null) {
      storage.backendSettings.setActiveKcppsPath(preset!.path);
    }
    final llm = FakeLLMProvider(activeBackend: BackendType.kobold);
    final models = _Models([model]);
    final hardware = _Hardware();
    final kobold = _Kobold();
    final engine = _Engine();
    addTearDown(() {
      for (final n in [storage, llm, models, hardware, kobold, engine]) {
        n.dispose();
      }
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<BackendManager>.value(value: engine),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const ModelSettingsDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    return (storage: storage, kobold: kobold, model: model);
  }

  /// Presses the start button. The model check reads the real file and the
  /// dialog then waits a second for the port, so the tap runs in real time.
  Future<void> pressStart(WidgetTester tester, String label) async {
    final start = find.text(label);
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(start);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
    });
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Start Backend starts the picked model and leaves a graphics '
      'choice that was never made unrecorded', (tester) async {
    final it = await open(tester);
    final b = it.storage.backendSettings;
    bool automatic() => GpuBackendResolver.isAutomatic(
      userCublas: b.useCublas,
      userVulkan: b.useVulkan,
      userRocm: b.useRocm,
      userMetal: b.useMetal,
    );
    expect(automatic(), isTrue, reason: 'nothing chosen yet');

    await pressStart(tester, 'Start Backend');

    expect(it.kobold.starts, hasLength(1));
    expect(it.kobold.starts.single['model'], it.model.path);
    expect(
      automatic(),
      isTrue,
      reason: 'the dialog must not turn "never chosen" into CPU-only',
    );
  });

  testWidgets('a preset that cannot be read: the dialog says so in plain '
      'words and starts nothing', (tester) async {
    final it = await open(tester, presetText: '{this is not a config');

    await pressStart(tester, 'Start with Preset');

    expect(it.kobold.starts, isEmpty);
    expect(find.textContaining('mine.kcpps'), findsWidgets);
    expect(find.textContaining('can\'t be read'), findsOneWidget);
  });
}
