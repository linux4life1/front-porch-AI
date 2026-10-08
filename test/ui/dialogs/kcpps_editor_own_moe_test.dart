// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Two settings a preset can carry that the editor's form does not hold
// (maintainer, 2026-10-05):
//
// A MoE setting of its own (`moecpu`, experts kept in system memory) beside
// automatic layers. The form writes placement as one group and its
// automatic placement never writes `moecpu`, so editing the placement
// (greedy, automatic or by hand, the layers) dropped the user's own tuning
// without a word. Now the editor says so once, before that save, and Cancel
// keeps the file as it was.
//
// A split over several cards (`tensor_split`). Switching a CUDA preset from
// every card to one kept the split, and KoboldCpp pins the named card only
// when there is no split, so the preset still ran over all of them. Now the
// split goes with the switch, and stays while the preset uses every card.
//
// Used as a person would: the whole dialog, taps, Save, and the file read
// back. Real model headers: Qwen3 30B A3B (a MoE model), Llama 3.2.

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
  const ask = "Replace this preset's MoE setting?";
  const greedy = 'Greedy: keep 32 MB spare instead of 1 GB';
  const mmq = 'MMQ (NVIDIA): faster on some cards, slower on others';
  const cuda = {
    'usecuda': ['normal', '0'],
  };
  late Directory bin;
  late _Storage storage;
  late String moe;
  late String llama;
  late Map<String, ({GGUFModelInfo? info, int bytes})> models;
  late File file;
  KcppsEditorController? c;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor own moe');
    storage = _Storage(bin);
    moe = p.join(bin.path, 'Qwen3-30B-A3B-Q4_K_M.gguf');
    llama = p.join(bin.path, 'Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    models = {
      moe: (
        info: await GGUFParser.getModelArchitectureInfo(
          '$headers/Qwen3-30B-A3B.gguf',
        ),
        bytes: 18556686912,
      ),
      llama: (
        info: await GGUFParser.getModelArchitectureInfo(
          '$headers/Llama-3.2-3B.gguf',
        ),
        bytes: 2019373184,
      ),
    };
    file = File(p.join(bin.path, 'Mine.kcpps'));
  });

  tearDown(() async {
    c?.dispose();
    c = null;
    await bin.delete(recursive: true);
  });

  /// The preset [written] on [model], opened in the whole dialog, on a
  /// computer with [cards] NVIDIA cards.
  Future<KcppsEditorController> open(
    WidgetTester tester,
    String model,
    Map<String, dynamic> written, {
    int cards = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = KcppsEditorController(
      storage: storage,
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4090',
          vramMb: 24564,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
          cardCount: cards,
        ),
      ),
      kobold: FakeKoboldService(),
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (path) async => models[path]!,
      unified: false,
      threads: () async => 8,
    );
    c = editor;
    await tester.runAsync(() async {
      await file.writeAsString(
        jsonEncode({'model_param': model, 'contextsize': 16384, ...written}),
      );
      await editor.init();
    });
    expect(editor.path, file.path, reason: 'the preset was opened');
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

  /// The preset file (or [other]) as it is on disk now.
  Future<Map<String, dynamic>> onDisk(
    WidgetTester tester, [
    File? other,
  ]) async =>
      (jsonDecode(await tester.runAsync((other ?? file).readAsString) as String)
              as Map)
          .cast<String, dynamic>();

  /// Taps Save and lets a question, if one comes, appear.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(KeButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Waits for the save to be written, then reads the file (or [other])
  /// back.
  Future<Map<String, dynamic>> saved(
    WidgetTester tester,
    KcppsEditorController editor, [
    File? other,
  ]) async {
    for (var i = 0; i < 500 && editor.dirty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
    expect(editor.dirty, isFalse, reason: 'it was saved');
    return onDisk(tester, other);
  }

  testWidgets('a placement edit beside the preset\'s own MoE setting asks '
      'once: Cancel keeps the file, the answer saves', (tester) async {
    final editor = await open(tester, moe, {
      'gpulayers': -1,
      'moecpu': 20,
      ...cuda,
    });
    final before = await onDisk(tester);

    await tester.tap(find.text(greedy));
    await tester.pump();
    await tapSave(tester);
    expect(find.text(ask), findsOneWidget);
    expect(find.textContaining('MoE (experts on CPU)'), findsOneWidget);

    // The question's own Cancel, over the editor's.
    await tester.tap(find.widgetWithText(KeButton, 'Cancel').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ask), findsNothing);
    expect(editor.dirty, isTrue, reason: 'the edit is still in the form');
    expect(await onDisk(tester), before, reason: 'nothing was written');

    await tapSave(tester);
    expect(find.text(ask), findsOneWidget, reason: 'not agreed yet');
    await tester.tap(find.widgetWithText(KeButton, 'Replace and save'));
    await tester.pump();
    final file = await saved(tester, editor);
    expect(file.containsKey('moecpu'), isFalse);
    expect(file['autofitpadding'], 32);

    // Placement changed again: the file has no setting of its own left.
    await tester.tap(find.text(greedy));
    await tester.pump();
    await tapSave(tester);
    expect(find.text(ask), findsNothing);
    expect((await saved(tester, editor))['autofitpadding'], 1024);
  });

  testWidgets('agreed once, a save that stops at the name does not ask about '
      'the MoE setting again', (tester) async {
    await tester.runAsync(
      () => File(p.join(bin.path, 'Other.kcpps')).writeAsString('{}'),
    );
    final editor = await open(tester, moe, {
      'gpulayers': -1,
      'moecpu': 20,
      ...cuda,
    });
    await tester.tap(find.text(greedy));
    await tester.enterText(find.byKey(const ValueKey('kcpps-name')), 'Other');
    await tester.pump();

    await tapSave(tester);
    expect(find.text(ask), findsOneWidget);
    await tester.tap(find.widgetWithText(KeButton, 'Replace and save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Replace "Other"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(KeButton, 'Cancel').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tapSave(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(ask), findsNothing, reason: 'agreed already');
    expect(find.text('Replace "Other"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(KeButton, 'Replace'));
    await tester.pump();
    final other = File(p.join(bin.path, 'Other.kcpps'));
    final written = await saved(tester, editor, other);
    expect(written.containsKey('moecpu'), isFalse);
    expect(written['autofitpadding'], 32);
  });

  testWidgets('an edit that leaves placement alone does not ask, and keeps '
      'the preset\'s own MoE setting', (tester) async {
    final editor = await open(tester, moe, {
      'gpulayers': -1,
      'moecpu': 20,
      ...cuda,
    });

    editor.edit((d) => d.copyWith(contextSize: 32768));
    await tester.pump();
    await tapSave(tester);

    expect(find.text(ask), findsNothing);
    final file = await saved(tester, editor);
    expect(file['contextsize'], 32768);
    expect(file['moecpu'], 20);
    expect(file['gpulayers'], -1);
  });

  testWidgets('a preset without a MoE setting of its own never asks', (
    tester,
  ) async {
    final editor = await open(tester, moe, {'gpulayers': -1, ...cuda});

    await tester.tap(find.text(greedy));
    await tester.pump();
    await tapSave(tester);

    expect(find.text(ask), findsNothing);
    expect((await saved(tester, editor))['autofitpadding'], 32);
  });

  testWidgets('placed by hand, the form shows the MoE setting: editing the '
      'layers and the experts there does not ask', (tester) async {
    final editor = await open(tester, moe, {
      'gpulayers': 49,
      'moecpu': 20,
      'autofit': false,
      ...cuda,
    });
    expect(editor.draft.manual, isTrue);
    expect(editor.draft.moeCpuLayers, 20);

    await tester.enterText(find.byKey(const ValueKey('kcpps-layers')), '30');
    await tester.enterText(find.byKey(const ValueKey('kcpps-moecpu')), '24');
    await tester.pump();
    await tapSave(tester);

    expect(find.text(ask), findsNothing);
    final file = await saved(tester, editor);
    expect(file['gpulayers'], 30);
    expect(file['moecpu'], 24);
  });

  testWidgets('a CUDA preset switched from every card to one loses its '
      'split', (tester) async {
    final editor = await open(tester, llama, {
      'usecuda': ['normal'],
      'tensor_split': [3, 1],
    }, cards: 2);
    expect(editor.cards, 2);

    editor.edit((d) => d.copyWith(gpuId: 0));
    await tester.pump();
    await tapSave(tester);
    final file = await saved(tester, editor);

    expect(file['usecuda'], ['normal', '0']);
    expect(file.containsKey('tensor_split'), isFalse);
  });

  testWidgets('still on every card, the split stays when the cards are '
      'saved', (tester) async {
    final editor = await open(tester, llama, {
      'usecuda': ['normal'],
      'tensor_split': [3, 1],
    }, cards: 2);

    await tester.tap(find.text(mmq));
    await tester.pump();
    await tapSave(tester);
    final file = await saved(tester, editor);

    expect(file['nommq'], isTrue, reason: 'the card setting was saved');
    expect(file['tensor_split'], [3, 1]);
  });

  testWidgets('a preset that already names one card keeps what it wrote '
      'when the cards are saved', (tester) async {
    final editor = await open(tester, llama, {
      'usecuda': ['normal', '0'],
      'tensor_split': [3, 1],
    }, cards: 2);

    await tester.tap(find.text(mmq));
    await tester.pump();
    await tapSave(tester);
    final file = await saved(tester, editor);

    expect(file['nommq'], isTrue);
    expect(file['tensor_split'], [3, 1]);
  });
}
