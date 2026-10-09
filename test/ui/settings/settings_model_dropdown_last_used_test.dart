// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Settings -> Backend opens its model dropdown on the model the Local model
// card names: the last-used one. It used to open on the first file in the
// folder, so Start Backend loaded a model the card above it did not mention
// and made it the last-used one, and the model the user had been running was
// forgotten.
//
// The real Settings page and the real launch; only the engine start is
// recorded (see settings_page_harness.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  Finder modelDropdown() => find.descendant(
    of: find.byType(ModelSelector),
    matching: find.byType(DropdownButton<String>),
  );

  testWidgets('the dropdown opens on the last-used model, and Start loads '
      'that one', (tester) async {
    final rig = await mountSettings(tester, lastUsedIsB: true);
    await openTab(tester, 'Backend');
    await settle(tester);

    final shown = tester.widget<DropdownButton<String>>(modelDropdown()).value;
    final card = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('local-model-card')),
            matching: find.textContaining('not running'),
          ),
        )
        .data;
    expect(
      shown,
      rig.b,
      reason:
          'the dropdown shows ${p.basename(shown ?? 'nothing')} while the '
          'card above the Start button says "$card"',
    );

    await tapVisible(tester, find.text('Start Backend'));
    await settle(tester, () => rig.kobold.starts.isNotEmpty);

    final started = rig.kobold.starts.single.model;
    expect(
      started,
      rig.b,
      reason: 'Start loaded ${p.basename(started)}, not what the dropdown said',
    );
    expect(
      rig.store.backendSettings.lastUsedModelPath,
      rig.b,
      reason: 'the model in use must stay the one the user was running',
    );
  });

  testWidgets('a last-used model that is not in the folder leaves the '
      'dropdown on no model, and Start works once one is picked', (
    tester,
  ) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) => rig.store.backendSettings.setLastUsedModelPath(
        p.join(rig.dir.path, 'moved-away.gguf'),
      ),
    );
    await openTab(tester, 'Backend');
    await settle(tester);

    expect(
      tester.widget<DropdownButton<String>>(modelDropdown()).value,
      isNull,
      reason: 'the first file was never chosen, so it must not show as picked',
    );
    expect(find.text('Choose a model'), findsOneWidget);

    await pickFromDropdown(tester, modelDropdown(), p.basename(rig.a));
    final start = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Start Backend'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(start.onPressed, isNotNull, reason: 'Start must not be disabled');

    await tapVisible(tester, find.text('Start Backend'));
    await settle(tester, () => rig.kobold.starts.isNotEmpty);
    expect(rig.kobold.starts.single.model, rig.a);
  });
}
