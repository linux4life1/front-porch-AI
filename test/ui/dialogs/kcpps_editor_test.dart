// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor, used the way a person uses it: on the original
// author's machine (a 6 GB GTX 1060, 5.1 GB free) with the Qwen3.6 35B MoE
// model (its real header, grown to its real size as a sparse file).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_controller.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

final _gtx1060 = HardwareInfo(
  gpuName: 'NVIDIA GeForce GTX 1060 6GB',
  vramMb: 6144,
  ramMb: 16384,
  vendor: 'Nvidia',
  hasCuda: true,
);

void main() {
  late Directory bin;
  late String model;
  late String inUse;
  late _Storage storage;

  /// Real time for file work, a frame at a time, until [done] (or a few
  /// frames when there is nothing to wait for).
  Future<void> settle(WidgetTester tester, [bool Function()? done]) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
      if (done == null ? i >= 8 : done()) return;
    }
    fail('still not done after 4 seconds');
  }

  KcppsEditorController controller() => KcppsEditorController(
    storage: storage,
    hardware: FakeHardwareService(hardwareInfo: _gtx1060),
    kobold: FakeKoboldService(),
    models: [model],
    readFree: () async => (graphics: 5222, system: 11063),
    unified: false,
    threads: () async => 4,
  );

  Future<KcppsEditorController> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      bin = await Directory.systemTemp.createTemp('fpai editor');
      const fx = 'test/fixtures/gguf_headers/Qwen3.6-35B-A3B-Q4_K_XL';
      final side = jsonDecode(File('$fx.json').readAsStringSync()) as Map;
      model = p.join(bin.path, 'Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf');
      final raf = await File(model).open(mode: FileMode.write);
      await raf.writeFrom(File('$fx.gguf').readAsBytesSync());
      await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
      await raf.writeByte(0);
      await raf.close();
      inUse = p.join(bin.path, 'Qwen3.6 35B — long chats.kcpps');
      File(inUse).writeAsStringSync(
        jsonEncode({
          'model_param': model,
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
      File(p.join(bin.path, 'Another.kcpps')).writeAsStringSync(
        jsonEncode({'model_param': model, 'contextsize': 32768}),
      );
      storage = _Storage(bin);
      await storage.backendSettings.setActiveKcppsPath(inUse);
    });
    addTearDown(() => bin.deleteSync(recursive: true));
    final c = controller();
    await tester.runAsync(c.init);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(body: KcppsEditorDialog(controller: c)),
        ),
      ),
    );
    await tester.pump();
    return c;
  }

  testWidgets('the preset chat uses comes first, marked, and is opened', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('IN USE'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Qwen3.6 35B — long chats').first).dy,
      lessThan(tester.getTopLeft(find.text('Another')).dy),
    );
    final name = tester.widget<TextField>(
      find.byKey(const ValueKey('kcpps-name')),
    );
    expect(name.controller!.text, 'Qwen3.6 35B — long chats');
  });

  testWidgets('placed by hand and too much: it says by how much, and one tap '
      'takes the largest that fits', (tester) async {
    final c = await open(tester);
    expect(find.textContaining("This won't fit: 1.6 GB over."), findsOneWidget);
    expect(
      find.textContaining('keep the first 38 in system memory'),
      findsOneWidget,
    );

    await tester.tap(find.text('Use the largest that fits'));
    await tester.pump();
    expect(c.draft.moeCpuLayers, 38);
    expect(find.textContaining("This won't fit"), findsNothing);
    expect(find.textContaining('It fits, at reduced speed.'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester, () => !c.dirty);
    final saved = jsonDecode(File(inUse).readAsStringSync()) as Map;
    expect(saved['gpulayers'], 41);
    expect(saved['moecpu'], 38);
  });

  testWidgets('a number past the model is refused with the reason', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.enterText(find.byKey(const ValueKey('kcpps-moecpu')), '55');
    await tester.pump();
    expect(find.text('This model has 40 layers.'), findsOneWidget);
    expect(c.draft.moeCpuLayers, 34, reason: 'not taken');
  });

  testWidgets('renaming on save moves the file and chat goes with it', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.enterText(find.byKey(const ValueKey('kcpps-name')), 'Long');
    await tester.tap(find.text('Save'));
    await settle(tester, () => !c.dirty);

    final renamed = p.join(bin.path, 'Long.kcpps');
    expect(File(renamed).existsSync(), isTrue);
    expect(File(inUse).existsSync(), isFalse);
    expect(storage.backendSettings.activeKcppsPath, renamed);

    // Opened again, it reads back as saved.
    final again = controller();
    addTearDown(again.dispose);
    await tester.runAsync(again.init);
    expect(again.draft.name, 'Long');
    expect(again.draft.gpuLayers, 41);
    expect(again.draft.moeCpuLayers, 34);
    expect(again.draft.batchSize, 1024);
  });

  testWidgets('a name another preset has asks before replacing it', (
    tester,
  ) async {
    final c = await open(tester);
    await tester.enterText(find.byKey(const ValueKey('kcpps-name')), 'Another');
    await tester.tap(find.text('Save'));
    await settle(
      tester,
      () => find.text('Replace "Another"?').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Replace'));
    await settle(tester, () => !c.dirty);
    final replaced =
        jsonDecode(File(p.join(bin.path, 'Another.kcpps')).readAsStringSync())
            as Map;
    expect(replaced['moecpu'], 34, reason: 'the edited preset, saved over it');
  });

  testWidgets('the pop-up keeps it automatic unless the user opens presets, '
      'and can be told not to ask again', (tester) async {
    final storage = FakeStorageService();
    bool? answer;
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await showDialog<bool>(
                context: context,
                builder: (_) => const KcppsExpertGate(),
              ),
              child: const Text('presets'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it automatic'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);

    await tester.tap(find.text('presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I know KoboldCpp: don't ask again"));
    await tester.pump();
    await tester.tap(find.text('Open presets'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
    expect(storage.backendSettings.presetGateSkipped, isTrue);
  });

  test('closing the editor while it is still reading is harmless', () async {
    final dir = await Directory.systemTemp.createTemp('fpai editor close');
    addTearDown(() => dir.delete(recursive: true));
    final c = KcppsEditorController(
      storage: _Storage(dir),
      hardware: FakeHardwareService(hardwareInfo: _gtx1060),
      kobold: FakeKoboldService(),
      readFree: () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return (graphics: 5222, system: 11063);
      },
      unified: false,
      threads: () async => 4,
    );
    final reading = c.init();
    c.dispose();
    await expectLater(reading, completes);
  });
}
