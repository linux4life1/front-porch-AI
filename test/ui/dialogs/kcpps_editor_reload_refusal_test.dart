// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Save and use now" puts the saved preset into the running KoboldCpp. When
// the engine could not take it (it went back to the model it had, and a fresh
// start would be refused), the preset is still saved and chat's, but the
// editor says so where it shows problems, and the dialog stays open for it to
// be read. The same goes for the reload that puts chat back after an MMQ
// timing.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Running extends FakeKoboldService {
  @override
  bool get isRunning => true;
}

const _refusal =
    'The new model was not loaded. The previous one is still running. '
    'Not a valid GGUF model file.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory bin;
  late FakeStorageService storage;

  setUp(() async {
    bin = await Directory.systemTemp.createTemp('fpai editor reload refusal');
    File(p.join(bin.path, 'Mine.kcpps')).writeAsStringSync(
      jsonEncode({
        'contextsize': 16384,
        'usecuda': ['normal', '0'],
      }),
    );
    storage = _Storage(bin);
  });

  tearDown(() => bin.delete(recursive: true));

  /// The editor with a running KoboldCpp whose reload says [answer], and the
  /// number of reloads it was asked for.
  Future<(KcppsEditorController, List<int>)> editor(
    KoboldLaunchResult? answer,
  ) async {
    final asked = <int>[];
    Future<KoboldLaunchResult?> reload() async {
      asked.add(1);
      return answer;
    }

    final c = KcppsEditorController(
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
      kobold: _Running(),
      reloadChat: reload,
      loadTrial: (name, config) async => false,
      readFree: () async => (graphics: 23000, system: 60000),
      readModel: (_) async => (info: null, bytes: 0),
      unified: false,
      threads: () async => 4,
    );
    addTearDown(c.dispose);
    await c.init();
    return (c, asked);
  }

  test('a reload KoboldCpp refused: the preset is saved and chat\'s, the '
      'reason is shown, and the result says it was not loaded', () async {
    final (c, asked) = await editor(const KoboldLaunchResult.refused(_refusal));

    final result = await c.saveAndUse();

    expect(result.name, 'notLoaded');
    expect(c.problem, _refusal);
    expect(asked, [1]);
    expect(storage.backendSettings.activeKcppsPath, c.path);
  });

  test('a reload that loads has nothing to say', () async {
    final (c, asked) = await editor(null);

    final result = await c.saveAndUse();

    expect(result, KcppsSaveResult.saved);
    expect(c.problem, isNull);
    expect(asked, [1]);
  });

  test('a restart that started has nothing to say either, whatever note '
      'came with it', () async {
    final (c, _) = await editor(
      const KoboldLaunchResult.started('The preset was loaded.'),
    );

    expect(await c.saveAndUse(), KcppsSaveResult.saved);
    expect(c.problem, isNull);
  });

  test('putting chat back after the MMQ timing says so too when it is '
      'refused', () async {
    final (c, asked) = await editor(const KoboldLaunchResult.refused(_refusal));

    await c.timeMmq();

    expect(asked, [1], reason: 'chat is put back after the timing');
    expect(c.problem, _refusal);
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

    testWidgets('Save and use now, refused: the dialog stays open with the '
        'reason beside the buttons, and closing still says a preset was '
        'saved', (tester) async {
      final (c, _) = await tester
          .runAsync(() => editor(const KoboldLaunchResult.refused(_refusal)))
          .then((r) => r!);
      final result = await open(tester, c);

      await tester.tap(find.text('Save and use now'));
      await until(tester, () => c.problem != null);
      await tester.pumpAndSettle();

      expect(find.text('KoboldCpp presets'), findsOneWidget);
      final message = find.byKey(const ValueKey('kcpps-problem'));
      expect(tester.widget<Text>(message).data, _refusal);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(result, [true]);
    });

    testWidgets('Save and use now, loaded: the dialog closes', (tester) async {
      final (c, _) = await tester.runAsync(() => editor(null)).then((r) => r!);
      final result = await open(tester, c);

      await tester.tap(find.text('Save and use now'));
      await until(tester, () => result.isNotEmpty);
      await tester.pumpAndSettle();

      expect(find.text('KoboldCpp presets'), findsNothing);
      expect(result, [true]);
    });
  });
}
