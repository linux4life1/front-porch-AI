// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A model picked on Settings -> Backend while KoboldCpp runs goes into the
// running engine at once. When KoboldCpp could not load it and the old model
// is kept running, the stored choice goes back to the model that runs (see
// kobold_reload_puts_choice_back_test), and the model dropdown, which holds
// the pick on the page, names it again: it used to go on naming the model
// that was not loaded.
//
// The real Settings page; the engine is marked running and the live reload
// answers as the test says, after doing to the stored choice what the real
// one does when it keeps the old model (see settings_page_harness.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  Finder modelDropdown() => find.descendant(
    of: find.byType(ModelSelector),
    matching: find.byType(DropdownButton<String>),
  );

  String? shown(WidgetTester tester) =>
      tester.widget<DropdownButton<String>>(modelDropdown()).value;

  testWidgets('a model that was not loaded is not the one the dropdown '
      'names', (tester) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        rig.kobold.debugMarkProcessRunning();
        rig.llm.answer = () async {
          await rig.store.backendSettings.setLastUsedModelPath(rig.a);
          return const KoboldLaunchResult.refused(
            'The new model was not loaded. The previous one is still '
            'running. Not a valid GGUF model file.',
          );
        };
      },
    );
    await openTab(tester, 'Backend');
    expect(shown(tester), rig.a);

    await pickFromDropdown(tester, modelDropdown(), p.basename(rig.b));
    await settle(tester, () => rig.llm.reloads > 0);
    await settle(tester);

    expect(rig.llm.reloads, 1);
    expect(rig.store.backendSettings.lastUsedModelPath, rig.a);
    expect(
      shown(tester),
      rig.a,
      reason: 'the dropdown names ${p.basename(shown(tester) ?? 'nothing')}',
    );
  });

  testWidgets('a model that was loaded stays on show', (tester) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async => rig.kobold.debugMarkProcessRunning(),
    );
    await openTab(tester, 'Backend');

    await pickFromDropdown(tester, modelDropdown(), p.basename(rig.b));
    await settle(tester, () => rig.llm.reloads > 0);
    await settle(tester);

    expect(rig.store.backendSettings.lastUsedModelPath, rig.b);
    expect(shown(tester), rig.b);
  });
}
