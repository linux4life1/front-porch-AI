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

  /// Opens the dialog with two model files to choose from and picks one.
  Future<void> open(WidgetTester tester) async {
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
    // Opening counts the processor's cores, which is real work.
    await tester.runAsync(() async {
      await tester.tap(find.text('open'));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('other.gguf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('picked.gguf').last);
    await tester.pumpAndSettle();
  }

  /// Presses "Generate & Apply" and returns the preset it wrote.
  Future<Map<String, dynamic>> generate(WidgetTester tester) async {
    final button = find.text('Generate & Apply');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(button);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump(const Duration(milliseconds: 300));
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
}
