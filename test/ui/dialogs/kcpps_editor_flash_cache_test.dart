// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor follows auto mode's rule for flash attention and a
// compressed chat memory (maintainer, 2026-10-05): a compressed cache turns
// flash attention on wherever it can run. The editor used to do the
// opposite: "New from my settings" with flash attention off started with
// the compressed sizes greyed out and saved a full-size cache, so the preset
// used more memory than the automatic launch it copied, with no reason
// given.
//
// Used as a person would: the whole dialog, taps, Save, and the file read
// back. Real model headers: Llama 3.2 (no special case) and Gemma 4, which
// runs without flash attention on Vulkan.

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

final _nvidia = HardwareInfo(
  gpuName: 'NVIDIA GeForce RTX 4090',
  vramMb: 24564,
  ramMb: 65536,
  vendor: 'Nvidia',
  hasCuda: true,
);

final _amd = HardwareInfo(
  gpuName: 'AMD Radeon RX 6900 XT',
  vramMb: 16368,
  ramMb: 65536,
  vendor: 'AMD',
  hasCuda: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const headers = 'test/fixtures/gguf_headers';
  late Directory bin;
  late _Storage storage;
  late String llama;
  late String gemma4;
  late Map<String, GGUFModelInfo?> infos;
  KcppsEditorController? c;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor flash cache');
    storage = _Storage(bin);
    llama = p.join(bin.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    gemma4 = p.join(bin.path, 'gemma-4-12b-it-Q4_K_M.gguf');
    infos = {
      llama: await GGUFParser.getModelArchitectureInfo(
        '$headers/Llama-3.2-3B.gguf',
      ),
      gemma4: await GGUFParser.getModelArchitectureInfo(
        '$headers/gemma-4-12b-it.gguf',
      ),
    };
  });

  tearDown(() async {
    c?.dispose();
    c = null;
    await bin.delete(recursive: true);
  });

  /// The editor on [model] with the app's own settings at [flash] and
  /// [cache], opened on [preset] when given, else on a new preset made from
  /// those settings (no preset exists yet).
  Future<KcppsEditorController> open(
    WidgetTester tester, {
    required String model,
    required bool flash,
    required KvQuant cache,
    HardwareInfo? hardware,
    Map<String, dynamic>? preset,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = KcppsEditorController(
      storage: storage,
      hardware: FakeHardwareService(hardwareInfo: hardware ?? _nvidia),
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 15000, system: 60000),
      readModel: (path) async => (info: infos[path], bytes: 0),
      unified: false,
      threads: () async => 8,
    );
    c = editor;
    await tester.runAsync(() async {
      final b = storage.backendSettings;
      await b.setLastUsedModelPath(model);
      await b.setFlashAttentionEnabled(flash);
      await b.setKvQuant(cache);
      if (preset != null) {
        await File(p.join(bin.path, 'Mine.kcpps')).writeAsString(
          jsonEncode({'model_param': model, 'contextsize': 16384, ...preset}),
        );
      }
      await editor.init();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: editor)),
        ),
      ),
    );
    await tester.pump();
    return editor;
  }

  /// Taps Save, waits for the file, and reads it back.
  Future<Map<String, dynamic>> save(
    WidgetTester tester,
    KcppsEditorController editor,
  ) async {
    await tester.tap(find.widgetWithText(KeButton, 'Save'));
    for (var i = 0; i < 100 && (editor.dirty || editor.path == null); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
    final file = File(editor.path!);
    return (jsonDecode(await tester.runAsync(file.readAsString) as String)
            as Map)
        .cast<String, dynamic>();
  }

  KeCheck flashBox(WidgetTester tester) => tester.widget<KeCheck>(
    find.byKey(const ValueKey('kcpps-flash-attention')),
  );

  Finder size(String label) => find.descendant(
    of: find.byKey(const ValueKey('kcpps-cache')),
    matching: find.text(label),
  );

  Finder note() => find.text(kKoboldCompressedTurnsFlashOn);

  testWidgets('"New from my settings" with flash attention off and an 8-bit '
      'cache starts as auto mode runs it, and saves it so', (tester) async {
    final editor = await open(
      tester,
      model: llama,
      flash: false,
      cache: KvQuant.q8_0,
    );

    expect(editor.draft.kvQuant, KvQuant.q8_0);
    expect(flashBox(tester).value, isTrue);
    expect(flashBox(tester).onChanged, isNull, reason: 'the cache needs it');
    expect(note(), findsOneWidget);

    final saved = await save(tester, editor);
    expect(saved['quantkv'], 'q8_0');
    expect(saved['noflashattention'], isFalse);

    // It started from what auto mode runs, flash attention on, so a
    // full-size cache keeps it.
    await tester.tap(size('Full'));
    await tester.pump();
    expect(flashBox(tester).value, isTrue);
    expect(flashBox(tester).onChanged, isNotNull);
  });

  testWidgets('with flash attention off, a compressed size can still be '
      'picked, turns it on, and Full gives the switch back', (tester) async {
    final editor = await open(
      tester,
      model: llama,
      flash: false,
      cache: KvQuant.f16,
    );
    expect(flashBox(tester).value, isFalse);
    expect(flashBox(tester).onChanged, isNotNull);
    expect(note(), findsNothing);

    await tester.tap(size('4-bit'));
    await tester.pump();
    expect(editor.draft.kvQuant, KvQuant.q4_0);
    expect(flashBox(tester).value, isTrue);
    expect(flashBox(tester).onChanged, isNull);
    expect(note(), findsOneWidget);

    await tester.tap(size('Full'));
    await tester.pump();
    expect(flashBox(tester).value, isFalse, reason: 'the switch as it was');
    expect(flashBox(tester).onChanged, isNotNull);
    expect(note(), findsNothing);
  });

  testWidgets('Gemma 4 on Vulkan still runs without flash attention, with a '
      'full-size cache', (tester) async {
    final editor = await open(
      tester,
      model: gemma4,
      flash: true,
      cache: KvQuant.q8_0,
      hardware: _amd,
    );

    expect(editor.draft.backend, KoboldGpuBackend.vulkan);
    expect(editor.draft.kvQuant, KvQuant.f16, reason: 'it starts at Full');
    expect(flashBox(tester).value, isFalse);
    expect(note(), findsNothing);
    expect(find.textContaining('Gemma 4 on Vulkan'), findsOneWidget);

    final saved = await save(tester, editor);
    expect(saved['quantkv'], 'f16');
    expect(saved['noflashattention'], isTrue);
  });

  testWidgets('a preset that pairs an 8-bit cache with flash attention off '
      'is shown by the rule, and the next save writes it', (tester) async {
    final editor = await open(
      tester,
      model: llama,
      flash: true,
      cache: KvQuant.f16,
      preset: {'quantkv': 'q8_0', 'noflashattention': true},
    );
    expect(editor.path, isNotNull, reason: 'the file was opened');
    expect(flashBox(tester).value, isTrue);
    expect(note(), findsOneWidget);

    editor.edit((d) => d.copyWith(contextSize: 32768));
    await tester.pump();
    final saved = await save(tester, editor);

    expect(saved['contextsize'], 32768);
    expect(saved['quantkv'], 'q8_0');
    expect(saved['noflashattention'], isFalse);
  });
}
