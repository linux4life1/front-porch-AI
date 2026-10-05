// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The editor's number boxes (layers, experts, batch, slots, tokens guessed):
// one box that shows the form's number, takes what is typed when it will do,
// and keeps a wrong entry on screen with its reason until the form's number
// moves by other means. On the original author's machine (a 6 GB GTX 1060
// with 5.1 GB free) with the Qwen3.6 35B MoE model's real header.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_controller.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

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

  late Directory bin;
  late KcppsEditorController c;

  Finder box(String key) => find.byKey(ValueKey(key));
  String text(WidgetTester tester, String key) =>
      tester.widget<TextField>(box(key)).controller!.text;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor boxes');
    const fx = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-Q4_K_XL';
    final side = jsonDecode(await File('$fx.json').readAsString()) as Map;
    final model = p.join(bin.path, 'Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf');
    final raf = await File(model).open(mode: FileMode.write);
    await raf.writeFrom(await File('$fx.gguf').readAsBytes());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    final info = await GGUFParser.getModelArchitectureInfo(model);
    final bytes = await File(model).length();
    // Placed by hand, too much for the card, with a draft model.
    await File(p.join(bin.path, 'Long chats.kcpps')).writeAsString(
      jsonEncode({
        'model_param': model,
        'draftmodel': p.join(bin.path, 'small.gguf'),
        'contextsize': 16384,
        'batchsize': 1024,
        'gpulayers': 41,
        'moecpu': 34,
        'autofit': false,
        'noswa': true,
        'nofastforward': false,
        'noshift': true,
        'usecuda': ['normal', '0'],
      }),
    );
    c = KcppsEditorController(
      storage: _Storage(bin),
      hardware: FakeHardwareService(
        hardwareInfo: HardwareInfo(
          gpuName: 'NVIDIA GeForce GTX 1060 6GB',
          vramMb: 6144,
          ramMb: 16384,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
      ),
      kobold: FakeKoboldService(),
      models: [model],
      readFree: () async => (graphics: 5222, system: 11063),
      // The draft model is a file this test does not have a header for.
      readModel: (path) async => path.endsWith('small.gguf')
          ? (info: null, bytes: 0)
          : (info: info, bytes: bytes),
      unified: false,
      threads: () async => 4,
    );
  });

  tearDown(() async {
    c.dispose();
    await bin.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(c.init);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: _Storage(bin),
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: c)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a wrong entry gives way when the form moves the number: '
      'one tap takes the largest placement that fits', (tester) async {
    await open(tester);
    expect(text(tester, 'kcpps-moecpu'), '34');

    await tester.enterText(box('kcpps-moecpu'), '55');
    await tester.pump();
    expect(find.text('This model has 40 layers.'), findsOneWidget);
    expect(c.draft.moeCpuLayers, 34, reason: 'not taken');

    await tester.tap(find.text('Use the largest that fits'));
    await tester.pump();
    expect(c.draft.moeCpuLayers, 38);
    expect(text(tester, 'kcpps-moecpu'), '38');
    expect(find.text('This model has 40 layers.'), findsNothing);
  });

  testWidgets('a number that will do is taken as typed', (tester) async {
    await open(tester);
    await tester.enterText(box('kcpps-moecpu'), '30');
    await tester.pump();
    expect(c.draft.moeCpuLayers, 30);
    expect(text(tester, 'kcpps-moecpu'), '30');
    await tester.enterText(box('kcpps-layers'), '999');
    await tester.pump();
    expect(find.textContaining('This model has 41 layers.'), findsOneWidget);
    expect(c.draft.gpuLayers, 41, reason: 'not taken');
  });

  testWidgets('the slots and the tokens guessed say what is allowed', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(box('kcpps-slots'), '25');
    await tester.pump();
    expect(find.text('From 0 to 20 slots.'), findsOneWidget);
    await tester.enterText(box('kcpps-slots'), '4');
    await tester.pump();
    expect(find.text('From 0 to 20 slots.'), findsNothing);
    expect(c.draft.slots, 4);

    await tester.enterText(box('kcpps-draft-amount'), '20');
    await tester.pump();
    expect(find.text('A whole number from 1 to 16.'), findsOneWidget);
    expect(c.draft.draftAmount, isNull);
    await tester.enterText(box('kcpps-draft-amount'), '6');
    await tester.pump();
    expect(c.draft.draftAmount, 6);
    await tester.enterText(box('kcpps-draft-amount'), '');
    await tester.pump();
    expect(c.draft.draftAmount, isNull);
    expect(find.text('Empty: KoboldCpp guesses 4.'), findsOneWidget);
  });
}
