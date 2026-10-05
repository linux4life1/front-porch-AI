// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The character creator's Context Size box shows the context that is saved.
// It was filled once, when the creator opened, so choosing a preset there
// (which sets the preset's context) left the box, locked under the preset,
// showing the number from before; and clearing the preset, which puts the
// user's own back, did not show that either.
//
// The real setup step over the Settings page harness's models and engine
// folder (settings_page_harness.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  testWidgets('choosing a preset shows its context in the box, and clearing '
      'it shows the user\'s own again', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rig = await buildRig(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        File(
          p.join(rig.store.binDir.path, 'long.kcpps'),
        ).writeAsStringSync(jsonEncode({'contextsize': 32768}));
      },
    );
    final own = rig.store.backendSettings.contextSize;
    final creator = CreatorState()
      ..localPresets = kcppsPresetFiles(rig.store.binDir.path)
      ..extraSettingsExpanded = true
      ..initLocalSettingsControllers(rig.store);
    addTearDown(creator.dispose);
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
    final presets = find.descendant(
      of: find.byType(KcppsSelector),
      matching: find.byType(DropdownButton<String>),
    );
    String box() => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Context Size'))
        .controller!
        .text;
    expect(box(), '$own');

    await pickFromDropdown(tester, presets, 'long.kcpps');

    expect(rig.store.backendSettings.contextSize, 32768);
    expect(box(), '32768', reason: 'the box showed the number from before');

    await pickFromDropdown(tester, presets, 'None (Use App Settings)');

    expect(rig.store.backendSettings.contextSize, own);
    expect(box(), '$own');
  });
}
