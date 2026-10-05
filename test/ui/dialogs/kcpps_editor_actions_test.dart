// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Duplicate and Delete in the preset editor. Duplicate copies the file on
// disk, so the form's unsaved edits are not in the copy and are lost when the
// copy opens: it asks first, as switching presets does, and tells Settings
// the list changed. A copy or a delete the disk refuses says so in plain
// words instead of failing unseen. The failures here are real ones: the file
// is gone from under the editor.

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late _Storage storage;
  late String alpha;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor actions');
    storage = _Storage(bin);
    alpha = p.join(bin.path, 'Alpha.kcpps');
    await File(alpha).writeAsString(
      jsonEncode({
        'model_param': p.join(bin.path, 'm.gguf'),
        'contextsize': 16384,
      }),
    );
    await File(p.join(bin.path, 'Beta.kcpps')).writeAsString(
      jsonEncode({
        'model_param': p.join(bin.path, 'm.gguf'),
        'contextsize': 8192,
      }),
    );
  });

  tearDown(() => bin.delete(recursive: true));

  KcppsEditorController controller() => KcppsEditorController(
    storage: storage,
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
    readFree: () async => (graphics: 5222, system: 11063),
    readModel: (_) async => (info: null, bytes: 0),
    unified: false,
    threads: () async => 4,
  );

  group('the controller', () {
    test('a copy the disk refuses says so, and nothing throws', () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.init();
      expect(c.path, alpha);
      File(alpha).deleteSync();

      expect(await c.duplicate(), isFalse);
      expect(c.problem, startsWith('The preset could not be copied'));
      expect(c.path, alpha, reason: 'the form is as it was');
    });

    test('a delete the disk refuses says so, and nothing throws', () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.init();
      File(alpha).deleteSync();

      expect(await c.delete(), isFalse);
      expect(c.problem, startsWith('The preset could not be deleted'));
      expect(c.path, alpha);
    });

    test(
      'a copy is opened in place of the preset; a delete opens the next',
      () async {
        final c = controller();
        addTearDown(c.dispose);
        await c.init();

        expect(await c.duplicate(), isTrue);
        expect(p.basename(c.path!), 'Alpha (copy).kcpps');
        expect(c.presets.map((e) => e.name), contains('Alpha (copy)'));
        expect(c.problem, isNull);

        expect(await c.delete(), isTrue);
        expect(
          File(p.join(bin.path, 'Alpha (copy).kcpps')).existsSync(),
          isFalse,
        );
        expect(c.path, alpha);
      },
    );
  });

  group('the dialog', () {
    Future<List<bool?>> open(
      WidgetTester tester,
      KcppsEditorController c,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final result = <bool?>[];
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result.add(
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => KcppsEditorDialog(controller: c),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    Future<void> until(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done(), isTrue);
    }

    testWidgets('Duplicate asks before it drops edits, and tells Settings the '
        'list changed', (tester) async {
      final c = controller();
      addTearDown(c.dispose);
      await tester.runAsync(c.init);
      final result = await open(tester, c);

      c.edit((d) => d.copyWith(contextSize: 32768));
      await tester.pump();
      expect(c.dirty, isTrue);

      // Keep editing: nothing is copied and the edits are still there.
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        File(p.join(bin.path, 'Alpha (copy).kcpps')).existsSync(),
        isFalse,
      );
      expect(c.path, alpha);
      expect(c.draft.contextSize, 32768);

      // Discard: the copy of the saved preset opens.
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await until(tester, () => c.path != alpha);
      expect(p.basename(c.path!), 'Alpha (copy).kcpps');
      expect(c.draft.contextSize, 16384, reason: 'the edits are not in it');

      // Closing says a preset was added, so Settings looks again.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(result, [true]);
    });

    testWidgets(
      'a copy the disk refuses shows its message beside the buttons',
      (tester) async {
        final c = controller();
        addTearDown(c.dispose);
        await tester.runAsync(c.init);
        await open(tester, c);
        File(alpha).deleteSync();

        await tester.tap(find.text('Duplicate'));
        await until(tester, () => c.problem != null);
        final message = find.byKey(const ValueKey('kcpps-problem'));
        expect(message, findsOneWidget);
        expect(
          tester.widget<Text>(message).data,
          startsWith('The preset could not be copied'),
        );
        expect(
          tester.getTopLeft(message).dy,
          greaterThan(tester.getTopLeft(find.text('Save')).dy - 40),
          reason: 'in the footer with Save, not at the bottom of the form',
        );
      },
    );
  });
}
