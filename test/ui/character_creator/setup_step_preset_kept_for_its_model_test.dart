// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Choosing a preset in the character creator's Backend & Model Setup step
// (from the list, with Browse, or clearing it) is kept the way Settings, the
// Model Settings dialog and the phone keep it: a preset that names its own
// model makes that model the model in use, and the preset is kept for the
// model a launch will load, not for whichever model the step happened to
// show. The step used to set only the active preset, so the model in use and
// the link between a model and its preset stayed as they were.
//
// The real step, mounted with the Settings harness's doubles (see
// settings_page_harness.dart); the OS file dialog answers with a real file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/settings_page_harness.dart';

/// A preset file that names [model].
String presetNaming(String dir, String name, String model) {
  final file = File(p.join(dir, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({'model_param': model, 'contextsize': 8192}),
    );
  return file.path;
}

void main() {
  Finder presetDropdown() => find.descendant(
    of: find.byType(KcppsSelector),
    matching: find.byType(DropdownButton<String>),
  );

  /// The creator's setup step, on the local backend with Extra Settings open,
  /// over the harness's two models and the presets [before] writes.
  Future<({SettingsPageRig rig, CreatorState creator})> mountStep(
    WidgetTester tester, {
    required bool lastUsedIsB,
    Future<void> Function(SettingsPageRig rig)? before,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = await buildRig(
      tester,
      lastUsedIsB: lastUsedIsB,
      before: before,
    );
    final creator = CreatorState();
    addTearDown(creator.dispose);
    creator.localPresets = kcppsPresetFiles(rig.store.binDir.path);
    creator.extraSettingsExpanded = true;
    // Each place that shows the step rebuilds it when the creator state
    // changes, which is what the step relies on to show a new choice.
    await tester.pumpWidget(
      withRigProviders(
        rig,
        child: MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: creator,
              builder: (_, _) => SetupStep(state: creator),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return (rig: rig, creator: creator);
  }

  testWidgets('a preset from the list that names model B, with model A in '
      'use: B is the model in use and the preset is kept for B', (
    tester,
  ) async {
    late String preset;
    final m = await mountStep(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        preset = presetNaming(rig.store.binDir.path, 'b-own.kcpps', rig.b);
      },
    );
    final rig = m.rig;
    expect(rig.store.backendSettings.lastUsedModelPath, rig.a);
    m.creator.selectedLocalModelPath = rig.a;

    await pickFromDropdown(tester, presetDropdown(), 'b-own.kcpps');

    expect(rig.store.backendSettings.activeKcppsPath, preset);
    expect(
      m.creator.selectedLocalModelPath,
      isEmpty,
      reason: 'a preset that names a model gives the choice of model to it',
    );
    expect(
      rig.store.backendSettings.lastUsedModelPath,
      rig.b,
      reason: 'the model the preset loads is the model in use',
    );
    final links = Map.of(rig.store.presetSettings.modelPresetMap);
    expect(links[rig.b], preset, reason: 'kept for B; saved links: $links');
    expect(links[rig.a], isNull, reason: 'not for the model that was in use');
  });

  testWidgets('clearing it clears it for the model it was kept for', (
    tester,
  ) async {
    final m = await mountStep(
      tester,
      lastUsedIsB: true,
      before: (rig) async {
        final preset = presetNaming(
          rig.store.binDir.path,
          'b-own.kcpps',
          rig.b,
        );
        await rig.store.backendSettings.setActiveKcppsPath(preset);
        await rig.store.presetSettings.setModelPreset(rig.b, preset);
      },
    );
    final rig = m.rig;
    expect(rig.store.backendSettings.activeKcppsPath, isNotNull);

    await pickFromDropdown(tester, presetDropdown(), 'None (Use App Settings)');

    expect(rig.store.backendSettings.activeKcppsPath, isNull);
    expect(
      rig.store.presetSettings.modelPresetMap[rig.b] ?? '',
      isEmpty,
      reason: 'cleared for the model it was kept for',
    );
  });

  testWidgets('browsed to is kept for the model it names, and clearing its '
      'chip clears it for that model', (tester) async {
    late String browsed;
    final m = await mountStep(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        browsed = presetNaming(
          p.join(rig.dir.path, 'downloads'),
          'b-browsed.kcpps',
          rig.b,
        );
      },
    );
    final rig = m.rig;
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async =>
            FilePickerResult([PickedFile(browsed)]);
    addTearDown(() => PickerPrefs.testPickFilesOverride = null);

    await tapVisible(tester, find.byTooltip('Browse'));
    await settle(tester);

    expect(rig.store.backendSettings.activeKcppsPath, browsed);
    expect(
      rig.store.backendSettings.lastUsedModelPath,
      rig.b,
      reason: 'the model the preset loads is the model in use',
    );
    expect(rig.store.presetSettings.modelPresetMap[rig.b], browsed);
    expect(rig.store.presetSettings.modelPresetMap[rig.a], isNull);

    // A preset outside the engine folder shows as a chip with an X.
    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(KcppsSelector),
        matching: find.byIcon(Icons.close),
      ),
    );
    await settle(tester);

    expect(rig.store.backendSettings.activeKcppsPath, isNull);
    expect(
      rig.store.presetSettings.modelPresetMap[rig.b] ?? '',
      isEmpty,
      reason: 'cleared for the model the preset loaded',
    );
  });
}
