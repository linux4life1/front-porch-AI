// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Time batch sizes" in the preset editor (the maintainer's ruling,
// 2026-10-06): the batch sizes that fit are each loaded as a trial and timed
// once with the speed test's own loop, the fastest goes into the preset being
// edited with a stamp that it was measured on this card, and chat's model is
// put back. On KoboldCpp 1.122 each trial is the physical batch beside a
// logical 2,048, as auto mode runs it. The editor is the real dialog on a
// real model header; the engine's timings come from the trial it was given.

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

/// The running engine: a timing's speeds follow the trial it last loaded.
class _Kobold extends FakeKoboldService {
  Map<String, dynamic> loaded = {};

  @override
  bool get isRunning => true;

  @override
  Future<KoboldSpeed?> timeTurn(int round) async {
    final read = switch (kcppsBatchOf(loaded).physical) {
      512 => 900.0,
      1024 => 1000.0,
      _ => 1300.0,
    };
    return (
      read: 2000,
      readSeconds: 2000 / read,
      written: 200,
      writeSeconds: 1.0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late _Storage storage;
  late _Kobold kobold;
  late List<Map<String, dynamic>> trials;
  late int putBack;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor batch timing');
    storage = _Storage(bin);
    kobold = _Kobold();
    trials = [];
    putBack = 0;
  });

  tearDown(() => bin.delete(recursive: true));

  /// The editor on "Mine", a preset for Qwen3 14B with a batch of 1,024;
  /// [stamp] is the `measured` it was saved with, if any.
  Future<KcppsEditorController> open(
    WidgetTester tester, {
    Map<String, dynamic>? stamp,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const header = 'test/fixtures/gguf_headers/Qwen3-14B';
    final model = p.join(bin.path, 'Qwen3-14B-Q4_K_M.gguf');
    final exe = p.join(bin.path, 'koboldcpp');
    late final GGUFModelInfo? info;
    late final int bytes;
    await tester.runAsync(() async {
      info = await GGUFParser.getModelArchitectureInfo('$header.gguf');
      bytes =
          (jsonDecode(await File('$header.json').readAsString())
                  as Map)['fixture_file_bytes']
              as int;
      await File(exe).writeAsBytes(List.filled(64, 1));
      await KoboldBinaryVersion.write(bin.path, version: '1.122.1', size: 64);
      await File(p.join(bin.path, 'Mine.kcpps')).writeAsString(
        jsonEncode({
          'model_param': model,
          'contextsize': 16384,
          'batchsize': 1024,
          'usecuda': ['normal', '0'],
          'measured': ?stamp,
        }),
      );
    });
    final editor = KcppsEditorController(
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
      kobold: kobold,
      enginePath: exe,
      loadTrial: (name, config) async {
        trials.add(config);
        kobold.loaded = config;
        return true;
      },
      holdForSpeedTest: () async => () {},
      reloadChat: () async {
        putBack++;
        return null;
      },
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (_) async => (info: info, bytes: bytes),
      unified: false,
      threads: () async => 8,
    );
    addTearDown(editor.dispose);
    await tester.runAsync(editor.init);
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

  Finder measured() => find.byKey(const ValueKey('kcpps-batch-measured'));

  String text(WidgetTester tester, Finder f) => tester.widget<Text>(f).data!;

  Future<Map> save(WidgetTester tester, KcppsEditorController editor) async {
    await tester.tap(find.widgetWithText(KeButton, 'Save'));
    for (var i = 0; i < 100 && editor.dirty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    return jsonDecode(
          await tester.runAsync(File(editor.path!).readAsString) as String,
        )
        as Map;
  }

  testWidgets('a measured setting changed by hand is not measured any more: '
      'the line says so, and Save drops the stamp', (tester) async {
    final editor = await open(
      tester,
      stamp: {
        'card': 'NVIDIA GeForce RTX 4090',
        'backend': 'cuda',
        'engine': '1.122.1',
        'on': '2026-10-06',
      },
    );
    expect(text(tester, measured()), 'Batch 1,024, measured on this card.');

    // A setting the test did not measure keeps the stamp.
    await tester.enterText(find.byKey(const ValueKey('kcpps-slots')), '4');
    await tester.pump();
    expect(text(tester, measured()), 'Batch 1,024, measured on this card.');

    // The batch, typed by hand, is not what was measured.
    await tester.enterText(find.byKey(const ValueKey('kcpps-batch')), '2000');
    await tester.pump();
    expect(text(tester, measured()), 'Not measured on this card yet.');

    final saved = await save(tester, editor);
    expect(saved['batchsize'], 2000);
    expect(saved.containsKey('measured'), isFalse);
  });

  testWidgets('MMQ or flash attention changed by hand is not measured any '
      'more either', (tester) async {
    final editor = await open(
      tester,
      stamp: {'card': 'NVIDIA GeForce RTX 4090', 'backend': 'cuda'},
    );
    expect(text(tester, measured()), 'Batch 1,024, measured on this card.');
    editor.edit((d) => d.copyWith(mmq: !(d.mmq ?? true)));
    await tester.pump();
    expect(text(tester, measured()), 'Not measured on this card yet.');

    final again = await open(
      tester,
      stamp: {'card': 'NVIDIA GeForce RTX 4090', 'backend': 'cuda'},
    );
    again.edit((d) => d.copyWith(flashAttention: !d.flashAttention));
    await tester.pump();
    expect(text(tester, measured()), 'Not measured on this card yet.');
  });

  testWidgets('each size that fits is timed once, the fastest is set and '
      'stamped as measured here, and the file saves it', (tester) async {
    final editor = await open(tester);
    expect(text(tester, measured()), 'Not measured on this card yet.');

    final button = find.byKey(const ValueKey('kcpps-time-batch'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    for (var i = 0; i < 50 && editor.batchTiming; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    // What the preset runs first, then the other sizes that fit, each as
    // the physical batch beside a logical 2,048 (KoboldCpp 1.122).
    expect(
      [for (final t in trials) kcppsBatchOf(t).physical],
      [1024, 512, 2048],
    );
    expect({for (final t in trials) t['batchsize']}, {kKoboldLogicalBatch});
    expect(putBack, 1, reason: "chat's model is put back after");
    expect(editor.batchStatus, contains('2,048 is fastest here'));
    expect(text(tester, measured()), 'Batch 2,048, measured on this card.');

    await tester.tap(find.widgetWithText(KeButton, 'Save'));
    for (var i = 0; i < 100 && editor.dirty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final saved =
        jsonDecode(
              await tester.runAsync(File(editor.path!).readAsString) as String,
            )
            as Map;
    expect(saved['batchsize'], kKoboldLogicalBatch);
    expect(saved['ubatchsize'], 2048);
    expect(saved['measured']['card'], 'NVIDIA GeForce RTX 4090');
    expect(
      saved['measured']['auto'],
      isNull,
      reason: "it is the user's preset",
    );
  });
}
