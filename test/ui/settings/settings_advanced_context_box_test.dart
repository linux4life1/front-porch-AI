// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Advanced tab's Context Window box shows the context that is saved. A
// preset sets its own context, and the Local model card and the phone set it
// too, and the box heard about none of it: it kept the number it had when the
// page opened, and the memory gauge above it used that number. Start already
// launches from what is saved, so this is only what the box says.
//
// The real Settings page (see settings_page_harness.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  Finder contextBox() => find.descendant(
    of: find
        .ancestor(of: find.text('Context Window'), matching: find.byType(Row))
        .first,
    matching: find.byType(TextField),
  );
  String boxText(WidgetTester tester) =>
      tester.widget<TextField>(contextBox()).controller!.text;

  testWidgets('a preset chosen and cleared on the Backend tab leaves the box '
      'on the context the preset set', (tester) async {
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        File(
          p.join(rig.store.binDir.path, 'long.kcpps'),
        ).writeAsStringSync(jsonEncode({'contextsize': 32768}));
      },
    );
    await openTab(tester, 'Backend');
    final presets = find.descendant(
      of: find.byType(KcppsSelector),
      matching: find.byType(DropdownButton<String>),
    );
    await pickFromDropdown(tester, presets, 'long.kcpps');
    await pickFromDropdown(tester, presets, 'None (Use App Settings)');
    expect(rig.store.backendSettings.contextSize, 32768);

    await openTab(tester, 'Advanced');

    expect(
      boxText(tester),
      '32768',
      reason: 'the box shows the context the page opened with',
    );
  });

  testWidgets('a context chosen on the Local model card shows in the box', (
    tester,
  ) async {
    final rig = await mountSettings(tester, lastUsedIsB: false);
    await openTab(tester, 'Backend');
    final chip = find.descendant(
      of: find.byKey(const ValueKey('local-model-context')),
      matching: find.text('32,768'),
    );
    await settle(tester, () => chip.evaluate().isNotEmpty);
    await tapVisible(tester, chip);
    await settle(tester);
    expect(rig.store.backendSettings.contextSize, 32768);

    await openTab(tester, 'Advanced');

    expect(boxText(tester), '32768');
  });

  testWidgets('what is typed in the box is left alone while the page '
      'rebuilds', (tester) async {
    final rig = await mountSettings(tester, lastUsedIsB: false);
    final b = rig.store.backendSettings;
    await openTab(tester, 'Advanced');

    // Emptied to type a new number: nothing is saved, and nothing is put back.
    await tester.ensureVisible(contextBox());
    await tester.enterText(contextBox(), '');
    await b.setMlockEnabled(true);
    await settle(tester);
    expect(boxText(tester), '');

    await tester.enterText(contextBox(), '012288');
    await b.setMlockEnabled(false);
    await settle(tester);
    expect(b.contextSize, 12288);
    expect(boxText(tester), '012288', reason: 'the typed text stays as typed');
  });
}
