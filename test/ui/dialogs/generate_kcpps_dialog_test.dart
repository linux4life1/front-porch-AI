// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The "Generate preset" dialog and the preset it writes.
//
// The dialog does not decide how a model is loaded. KoboldCpp fits it. The
// dialog's "VRAM Usage Estimate" is a GUESS at how that fit will come out
// (for a MoE model: the active weights on the card, the experts in system
// memory), there so the user can pick a context size, batch size and cache
// type that fit in what is left and the model runs at full speed.
//
// The guess counts on a figure the preset also has to carry: how much
// graphics memory the fit leaves spare, 1024 MB, or 32 MB with "Greedy
// memory allocation". KoboldCpp keeps a preset's padding only when the fit
// is forced; switching the fit on by itself, it puts the padding back to
// its default. A preset that stopped forcing the fit left the dialog
// counting on 32 MB that KoboldCpp never used.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/generate_kcpps_dialog.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_services.dart';
import '../../golden/support/fakes_storage.dart';

class _Storage extends FakeStorageService {
  _Storage(this._bin);
  final Directory _bin;

  @override
  Directory get binDir => _bin;
}

class _Models extends FakeModelManager {
  _Models(this._models);
  final List<FileSystemEntity> _models;

  @override
  List<FileSystemEntity> get models => _models;

  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) async =>
      null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late File model;

  /// One step of real time (for a process or a file write) and of the
  /// test's clock (for the timers and animations waiting on them).
  Future<void> step(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }

  /// Lets real work (counting cores, writing the preset) run until [done]
  /// says it has finished.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await step(tester);
    }
    expect(done(), isTrue, reason: 'still not done after 10 seconds');
  }

  bool shown(Finder f) => f.evaluate().isNotEmpty;

  /// Puts the dialog behind an "open" button, with two model files to
  /// choose from.
  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('fpai generate preset');
      await File(
        p.join(temp.path, 'other.gguf'),
      ).writeAsBytes('GGUF'.codeUnits);
      model = File(p.join(temp.path, 'picked.gguf'));
      await model.writeAsBytes('GGUF'.codeUnits + List.filled(64, 0));
    });
    addTearDown(() => temp.deleteSync(recursive: true));

    final storage = _Storage(temp);
    final models = _Models([File(p.join(temp.path, 'other.gguf')), model]);
    final hardware = FakeHardwareService();
    addTearDown(() {
      for (final n in <ChangeNotifier>[storage, models, hardware]) {
        n.dispose();
      }
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const GenerateKcppsDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the dialog, waits for it to count the processor's cores (real
  /// work), and picks a model.
  Future<void> open(WidgetTester tester) async {
    await mount(tester);
    await tester.tap(find.text('open'));
    await settle(tester, () => shown(find.text('other.gguf')));
    final threads = await tester.runAsync(suggestKoboldThreads);
    await settle(
      tester,
      () => shown(find.widgetWithText(TextField, '$threads')),
    );

    await tester.tap(find.text('other.gguf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('picked.gguf').last);
    await tester.pumpAndSettle();
  }

  /// Presses "Generate & Apply" and returns the preset it wrote. The dialog
  /// closes once the file is written and chosen.
  Future<Map<String, dynamic>> generate(WidgetTester tester) async {
    final button = find.text('Generate & Apply');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await settle(tester, () => !shown(find.byType(GenerateKcppsDialog)));
    final written = File(p.join(temp.path, 'picked.kcpps'));
    return (jsonDecode(written.readAsStringSync()) as Map).cast();
  }

  testWidgets('the preset leaves the loading to KoboldCpp, and tells it to '
      'keep the spare memory the estimate counted on', (tester) async {
    await open(tester);
    expect(find.textContaining('Autofit padding: 1024 MB'), findsOneWidget);

    final preset = await generate(tester);

    expect(preset['model_param'], model.path);
    // KoboldCpp fits the model: no layer count, no MoE setting.
    expect(preset['gpulayers'], -1);
    expect(preset.containsKey('moecpu'), isFalse);
    // Forced, or KoboldCpp does not keep the padding that follows.
    expect(preset['autofit'], isTrue);
    expect(preset['autofitpadding'], 1024);
    expect(preset['usemlock'], isFalse);
  });

  testWidgets('"Greedy memory allocation" changes the estimate and the '
      'preset together', (tester) async {
    await open(tester);

    final greedy = find.byType(Switch);
    await tester.ensureVisible(greedy);
    await tester.pump();
    await tester.tap(greedy);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Autofit padding: 32 MB (greedy)'),
      findsOneWidget,
    );

    final preset = await generate(tester);

    expect(preset['autofitpadding'], 32);
    expect(
      preset['autofit'],
      isTrue,
      reason: 'without it KoboldCpp puts the padding back to 1024 MB',
    );
  });

  testWidgets('closing the dialog before it has counted the cores is '
      'harmless', (tester) async {
    await mount(tester);
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(GenerateKcppsDialog), findsNothing);

    // The count finishes after the dialog has gone.
    for (var i = 0; i < 40; i++) {
      await step(tester);
    }
    expect(tester.takeException(), isNull);
  });
}
