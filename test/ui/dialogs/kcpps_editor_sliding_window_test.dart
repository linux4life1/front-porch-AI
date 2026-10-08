// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Sliding window is written only for a model that has one, as the app's own
// settings do. Changing the model of an automatic preset to one without it
// used to keep a hidden sliding-window choice: the checkbox was gone and the
// panel said "fast forward stays on", but the file written had fast forward
// off. Nor is anything written while the model's file is still being read:
// its header, which says whether it has one, is not there yet. Real model
// headers: Gemma 3 has a sliding window, Llama 3.2 has not.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const headers = 'test/fixtures/gguf_headers';
  late Directory bin;
  late _Storage storage;
  late String gemma;
  late String llama;
  late KcppsEditorController c;

  /// While set, a model file being read waits for it.
  Completer<void>? hold;

  setUp(() async {
    hold = null;
    bin = await Directory.systemTemp.createTemp('fpai editor swa');
    storage = _Storage(bin);
    gemma = p.join(bin.path, 'gemma-3-12b-it-Q4_K_M.gguf');
    llama = p.join(bin.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    final infos = {
      gemma: await GGUFParser.getModelArchitectureInfo(
        '$headers/gemma-3-12b-it.gguf',
      ),
      llama: await GGUFParser.getModelArchitectureInfo(
        '$headers/Llama-3.2-3B.gguf',
      ),
    };
    expect(infos[gemma]!.hasSlidingWindow, isTrue);
    expect(infos[llama]!.hasSlidingWindow, isFalse);
    c = KcppsEditorController(
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
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (path) async {
        await hold?.future;
        return (info: infos[path], bytes: 0);
      },
      unified: false,
      threads: () async => 8,
    );
  });

  tearDown(() async {
    c.dispose();
    await bin.delete(recursive: true);
  });

  Future<File> open(Map<String, dynamic> map) async {
    final file = File(p.join(bin.path, 'Swa.kcpps'));
    await file.writeAsString(jsonEncode(map));
    await c.select(file.path);
    return file;
  }

  Map<String, dynamic> slidingWindowPreset(String model) => {
    'model_param': model,
    'contextsize': 16384,
    'gpulayers': -1,
    'autofit': true,
    'noswa': false,
    'nofastforward': true,
    'noshift': true,
    'swapadding': 0,
  };

  test('another model without a sliding window: fast forward is written, '
      'not a choice the form cannot show', () async {
    final file = await open(slidingWindowPreset(gemma));
    expect(c.slidingWindowOn, isTrue);
    expect(c.config.contextMode, ContextManagementMode.slidingWindowAttention);

    await c.setModel(llama);
    expect(c.slidingWindowOn, isFalse);
    expect(c.config.contextMode, ContextManagementMode.fastForwardSmartCache);
    expect(await c.save(), KcppsSaveResult.saved);
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect(saved['noswa'], isTrue);
    expect(saved['nofastforward'], isFalse);
    expect(saved['model_param'], llama);
  });

  test(
    'back to a model that has one, the choice is still the user\'s',
    () async {
      await open(slidingWindowPreset(gemma));
      await c.setModel(llama);
      await c.setModel(gemma);
      expect(c.slidingWindowOn, isTrue);
      expect(
        c.config.contextMode,
        ContextManagementMode.slidingWindowAttention,
      );
    },
  );

  test('a save while the model file is still read writes nothing; once it '
      'is read, the file keeps the sliding window', () async {
    final file = await open(slidingWindowPreset(gemma));
    final before = await file.readAsString();

    final reading = hold = Completer<void>();
    final picking = c.setModel(gemma);
    expect(c.canWrite, isFalse);
    expect(await c.save(), isNot(KcppsSaveResult.saved));
    expect(await file.readAsString(), before);

    reading.complete();
    await picking;
    expect(c.canWrite, isTrue);
    expect(await c.save(), KcppsSaveResult.saved);
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect(saved['noswa'], isFalse);
    expect(saved['nofastforward'], isTrue);
  });

  testWidgets('Save, Save and use now and the MMQ timing wait for the model '
      'file', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await open({
        ...slidingWindowPreset(gemma),
        'usecuda': ['normal', '0'],
      });
      await c.init();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: c)),
        ),
      ),
    );
    await tester.pump();
    final buttons = [
      'Save',
      'Save and use now',
      'Time both on this card',
    ].map((label) => find.widgetWithText(KeButton, label));
    bool enabled(Finder button) =>
        tester.widget<KeButton>(button).onPressed != null;
    expect(buttons.map(enabled), everyElement(isTrue));

    final reading = hold = Completer<void>();
    unawaited(c.setModel(gemma));
    await tester.pump();
    expect(buttons.map(enabled), everyElement(isFalse));

    reading.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(buttons.map(enabled), everyElement(isTrue));
  });

  testWidgets('the smart cache section does not blame a sliding window the '
      'model has not', (tester) async {
    await tester.runAsync(() => open(slidingWindowPreset(gemma)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => KcppsSmartCacheSection(c: c),
            ),
          ),
        ),
      ),
    );
    final blame = find.textContaining('Smart cache needs fast forward');
    expect(blame, findsOneWidget, reason: 'Gemma has a sliding window');

    await tester.runAsync(() => c.setModel(llama));
    await tester.pump();
    expect(blame, findsNothing);
    expect(find.byKey(const ValueKey('kcpps-slots')), findsOneWidget);
  });
}
