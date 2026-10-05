// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset that never mentions sliding window, on a model that has it, is
// left to KoboldCpp's own default, which switches sliding window on together
// with fast forward: a pairing that degrades output. The editor used to show
// that preset's switch as "off" and say nothing, so it looked the same as a
// preset that had switched sliding window off. Now the switch has a third
// state, "left to KoboldCpp", with the app's sentence beside it, and the file
// keeps saying nothing until the user answers the switch.
//
// Used as a person would: the whole dialog, a tap, Save, and the file read
// back. Real model headers: Gemma 3 has a sliding window, Llama 3.2 has not.

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
  const leftLabel = 'Sliding window: left to KoboldCpp';
  const offLabel =
      'Sliding window: less chat memory, but every reply reads the whole '
      'chat again';
  late Directory bin;
  late _Storage storage;
  late String gemma;
  late String llama;
  late KcppsEditorController c;
  late File file;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor swa left');
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
      readModel: (path) async => (info: infos[path], bytes: 0),
      unified: false,
      threads: () async => 8,
    );
    file = File(p.join(bin.path, 'Silent.kcpps'));
  });

  tearDown(() async {
    c.dispose();
    await bin.delete(recursive: true);
  });

  /// The preset [written] on [model], opened in the whole dialog.
  Future<void> mount(
    WidgetTester tester,
    String model,
    Map<String, dynamic> written,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await file.writeAsString(
        jsonEncode({
          'model_param': model,
          'contextsize': 16384,
          'gpulayers': -1,
          'autofit': true,
          ...written,
        }),
      );
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
  }

  /// Taps Save, waits for the file to be written, and reads it back.
  Future<Map<String, dynamic>> save(WidgetTester tester) async {
    expect(c.dirty, isTrue, reason: 'something was edited');
    await tester.tap(find.widgetWithText(KeButton, 'Save'));
    for (var i = 0; i < 100 && c.dirty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
    expect(c.dirty, isFalse, reason: 'it was saved');
    return (jsonDecode(await tester.runAsync(file.readAsString) as String)
            as Map)
        .cast<String, dynamic>();
  }

  Finder sentence() => find.text(kSwaLeftToKoboldNote);

  testWidgets('a preset that says nothing about sliding window shows the '
      'third state and the sentence, not "off"', (tester) async {
    await mount(tester, gemma, {});

    expect(find.text(leftLabel), findsOneWidget);
    expect(sentence(), findsOneWidget);
    expect(find.text(offLabel), findsNothing);
  });

  testWidgets('saving other edits leaves the file saying nothing about it', (
    tester,
  ) async {
    await mount(tester, gemma, {});
    c.edit((d) => d.copyWith(contextSize: 32768));
    await tester.pump();

    final saved = await save(tester);

    expect(saved['contextsize'], 32768);
    expect(saved.containsKey('noswa'), isFalse);
    expect(saved.containsKey('useswa'), isFalse);
    expect(find.text(leftLabel), findsOneWidget, reason: 'still left to it');
  });

  // The smart cache is saved together with sliding window and fast forward:
  // a change to it rewrites that whole group of settings from the form.
  testWidgets('a smart cache change keeps the file\'s own word on sliding '
      'window, fast forward and the padding', (tester) async {
    await mount(tester, gemma, {'nofastforward': true, 'swapadding': 512});
    expect(find.text(leftLabel), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('kcpps-slots')), '4');
    await tester.pump();
    final saved = await save(tester);

    expect(saved['smartcache'], isNotNull, reason: 'the slots were saved');
    expect(saved.containsKey('noswa'), isFalse);
    expect(saved.containsKey('useswa'), isFalse);
    expect(
      saved['nofastforward'],
      isTrue,
      reason:
          'fast forward on beside the default sliding window is the '
          'pairing that degrades output',
    );
    expect(saved['swapadding'], 512);
    expect(find.text(leftLabel), findsOneWidget, reason: 'still left to it');
    expect(sentence(), findsNothing);
  });

  testWidgets('a smart cache change on a file that says nothing about either '
      'still says nothing, and the sentence stays', (tester) async {
    await mount(tester, gemma, {});

    await tester.enterText(find.byKey(const ValueKey('kcpps-slots')), '4');
    await tester.pump();
    final saved = await save(tester);

    expect(saved['smartcache'], isNotNull, reason: 'the slots were saved');
    for (final key in ['noswa', 'useswa', 'nofastforward', 'swapadding']) {
      expect(saved.containsKey(key), isFalse, reason: key);
    }
    expect(find.text(leftLabel), findsOneWidget);
    expect(sentence(), findsOneWidget);
  });

  testWidgets('tapping the switch answers it: off is written, and the third '
      'state and the sentence go', (tester) async {
    await mount(tester, gemma, {});

    await tester.tap(find.text(leftLabel));
    await tester.pump();

    expect(find.text(offLabel), findsOneWidget);
    expect(find.text(leftLabel), findsNothing);
    expect(sentence(), findsNothing);
    final saved = await save(tester);
    expect(saved['noswa'], isTrue);
    expect(saved['nofastforward'], isFalse);
  });

  testWidgets('a second tap turns sliding window on, with fast forward off', (
    tester,
  ) async {
    await mount(tester, gemma, {});

    await tester.tap(find.text(leftLabel));
    await tester.pump();
    await tester.tap(find.text(offLabel));
    await tester.pump();

    final saved = await save(tester);
    expect(saved['noswa'], isFalse);
    expect(saved['nofastforward'], isTrue);
  });

  testWidgets('a preset that answers it never shows the third state', (
    tester,
  ) async {
    for (final answered in <Map<String, dynamic>>[
      {'noswa': true},
      {'noswa': false, 'nofastforward': true},
      {'useswa': true, 'nofastforward': true},
    ]) {
      await mount(tester, gemma, answered);

      expect(find.text(leftLabel), findsNothing, reason: '$answered');
      expect(sentence(), findsNothing, reason: '$answered');
      expect(
        find.textContaining('Sliding window: less chat memory'),
        findsOneWidget,
        reason: '$answered',
      );
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a model without a sliding window has nothing to leave to '
      'KoboldCpp', (tester) async {
    await mount(tester, llama, {});

    expect(find.text(leftLabel), findsNothing);
    expect(sentence(), findsNothing);
    expect(find.textContaining('has no sliding window'), findsOneWidget);
  });

  testWidgets('with fast forward off already, the switch says it is left but '
      'the pairing warning is not made', (tester) async {
    await mount(tester, gemma, {'nofastforward': true});

    expect(find.text(leftLabel), findsOneWidget);
    expect(sentence(), findsNothing);
  });
}
