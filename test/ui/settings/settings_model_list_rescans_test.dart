// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings -> Backend -> Model Selection lists the app's local models. The
// list was scanned at startup, after an in-app download and by Manage Models
// only, so a GGUF copied into the models folder while the app ran was missing
// ("No models found.") until the user visited Manage Models. Opening the tab
// scans the folder again, and so does Rescan.
//
// With no model chosen yet, the list says "Choose a model". It used to show
// the first file as if it were picked while the Local model card under it said
// "No model chosen", and Start would have loaded that file.
//
// The real Settings page, and for the folder tests the real ModelManager over
// a real models folder; only the engine start is recorded (see
// settings_page_harness.dart).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/settings_page_harness.dart';

Finder _modelDropdown() => find.descendant(
  of: find.byType(ModelSelector),
  matching: find.byType(DropdownButton<String>),
);

DropdownButton<String> _dropdown(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(_modelDropdown());

List<String> _listed(WidgetTester tester) => [
  if (_modelDropdown().evaluate().isNotEmpty)
    for (final item in _dropdown(tester).items ?? <DropdownMenuItem<String>>[])
      if (item.value != null && item.value!.isNotEmpty) p.basename(item.value!),
];

ElevatedButton _startButton(WidgetTester tester) => tester.widget(
  find.ancestor(
    of: find.text('Start Backend'),
    matching: find.byType(ElevatedButton),
  ),
);

/// Lets real file and isolate work finish; true once [done] holds.
Future<bool> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200; i++) {
    if (done()) return true;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  return done();
}

/// The real Settings page over the real ModelManager, whose models folder
/// starts empty. No model was ever used.
Future<({ModelManager models, Directory folder})> _mountOverRealFolder(
  WidgetTester tester,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final rig = await buildRig(
    tester,
    lastUsedIsB: false,
    before: (rig) => rig.store.backendSettings.setLastUsedModelPath(null),
  );
  late ModelManager models;
  late Directory folder;
  await tester.runAsync(() async {
    final library = StorageService.sandbox(p.join(rig.dir.path, 'library'));
    final downloads = DownloadManager(targetDir: library.modelsDir.path);
    models = ModelManager(library, downloads);
    await models.refreshModels();
    folder = library.modelsDir;
    addTearDown(() {
      models.dispose();
      downloads.dispose();
      library.dispose();
    });
  });
  await tester.pumpWidget(
    withRigProviders(
      rig,
      child: ChangeNotifierProvider<ModelManager>.value(
        value: models,
        child: const MaterialApp(home: SettingsPage()),
      ),
    ),
  );
  await settle(tester);
  expect(models.models, isEmpty, reason: 'the folder starts empty');
  return (models: models, folder: folder);
}

void main() {
  testWidgets('a model copied into the folder while the app runs is listed '
      'when the Backend tab opens, with nothing chosen', (tester) async {
    final real = await _mountOverRealFolder(tester);

    // Copied in by hand after startup: no download, no Manage Models visit.
    await tester.runAsync(
      () => writeGgufModel(real.folder, 'Llama-3.1-8B', 'copied-in.gguf'),
    );

    await openTab(tester, 'Backend');
    final listed = await _waitFor(
      tester,
      () => _listed(tester).contains('copied-in.gguf'),
    );

    expect(
      listed,
      isTrue,
      reason:
          'Model Selection still says "No models found." for a file in the '
          'models folder: opening the tab did not scan it again',
    );
    expect(find.text('No models found.'), findsNothing);
    expect(
      _dropdown(tester).value,
      isNull,
      reason: 'no model was chosen, so none may show as picked',
    );
    expect(find.text('Choose a model'), findsOneWidget);
    expect(find.textContaining('No model chosen'), findsOneWidget);
  });

  testWidgets('Rescan lists a model copied in while the tab is open', (
    tester,
  ) async {
    final real = await _mountOverRealFolder(tester);
    await openTab(tester, 'Backend');
    expect(find.text('No models found.'), findsOneWidget);

    await tester.runAsync(
      () => writeGgufModel(real.folder, 'Llama-3.1-8B', 'late.gguf'),
    );
    await tapVisible(tester, find.byKey(const ValueKey('model-rescan')));
    final listed = await _waitFor(
      tester,
      () => _listed(tester).contains('late.gguf'),
    );

    expect(listed, isTrue, reason: 'Rescan did not pick up the new file');
    expect(_dropdown(tester).value, isNull);
  });

  testWidgets('with no last-used model the list shows no pick and Start '
      'waits; picking one starts that one', (tester) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) => rig.store.backendSettings.setLastUsedModelPath(null),
    );
    await openTab(tester, 'Backend');
    await settle(tester);

    final shown = _dropdown(tester).value;
    expect(
      shown,
      isNull,
      reason:
          'the list shows ${p.basename(shown ?? '')} as picked while the '
          'card under it says "No model chosen"',
    );
    expect(find.text('Choose a model'), findsOneWidget);
    expect(find.textContaining('No model chosen'), findsOneWidget);
    expect(
      _startButton(tester).onPressed,
      isNull,
      reason: 'Start must not load a model nobody chose',
    );

    await pickFromDropdown(tester, _modelDropdown(), p.basename(rig.b));
    expect(_dropdown(tester).value, rig.b);
    await tapVisible(tester, find.text('Start Backend'));
    await settle(tester, () => rig.kobold.starts.isNotEmpty);
    expect(rig.kobold.starts.single.model, rig.b);
  });
}
