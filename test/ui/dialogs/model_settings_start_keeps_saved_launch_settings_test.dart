// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Start Backend in the chat's Model Settings dialog launches from what is
// saved. It used to write the context and the GPU layer count its two boxes
// held into storage first, and those boxes are older than storage whenever
// something else changed it while the dialog was open:
//  - choosing a preset sets the context to the preset's, so "Start with
//    Preset" put the older context back and the chat went on using it;
//  - the phone or the Local model card changing the context was undone the
//    same way;
//  - a layer count box left empty was saved as 0, "keep the model off the
//    card".
// What the user types in the two boxes is kept: it is saved as it is typed.
//
// The real dialog and the real launch; only the engine start is recorded (see
// model_settings_dialog_harness.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../helpers/model_settings_dialog_harness.dart';
import '../../helpers/settings_page_harness.dart';

void main() {
  Finder presetDropdown() => find.descendant(
    of: find.byType(KcppsSelector),
    matching: find.byType(DropdownButton<String>),
  );
  Finder contextBox() => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Context Size',
  );

  /// A preset that sets its own context and names no model.
  Future<void> longChatsPreset(SettingsPageRig rig) async {
    File(
      p.join(rig.store.binDir.path, 'long.kcpps'),
    ).writeAsStringSync(jsonEncode({'contextsize': 32768}));
  }

  testWidgets('the context a preset sets survives Start with Preset', (
    tester,
  ) async {
    final rig = await openModelSettings(
      tester,
      lastUsedIsB: false,
      before: longChatsPreset,
    );
    await pickFromDropdown(tester, presetDropdown(), 'long.kcpps');
    expect(rig.store.backendSettings.contextSize, 32768);

    await pressDialogStart(tester, 'Start with Preset');

    expect(
      rig.store.backendSettings.contextSize,
      32768,
      reason: 'Start put back the context the dialog opened with',
    );
    expect(rig.kobold.starts.single.context, 32768);
  });

  testWidgets('a context set elsewhere while the dialog is open survives '
      'Start', (tester) async {
    final rig = await openModelSettings(tester, lastUsedIsB: false);
    // The phone, or the Local model card.
    await rig.store.backendSettings.setContextSize(32768);

    await pressDialogStart(tester, 'Start Backend');

    expect(
      rig.store.backendSettings.contextSize,
      32768,
      reason: 'Start wrote the context the dialog opened with over it',
    );
    expect(rig.kobold.starts.single.context, 32768);
  });

  /// Types a context and, with the layer count set by hand, a layer count.
  Future<void> typeLaunchValues(WidgetTester tester) async {
    await tester.ensureVisible(contextBox());
    await tester.enterText(contextBox(), '12288');
    await tapVisible(
      tester,
      find.byKey(const ValueKey('gpu-layers-manual-switch')),
    );
    await settle(tester);
    final layers = find.byKey(const ValueKey('gpu-layers-number'));
    await tester.ensureVisible(layers);
    await tester.enterText(layers, '20');
    await settle(tester);
  }

  testWidgets('a context and a layer count typed here are what Start '
      'launches', (tester) async {
    final rig = await openModelSettings(tester, lastUsedIsB: false);
    await typeLaunchValues(tester);

    await pressDialogStart(tester, 'Start Backend');

    final start = rig.kobold.starts.single;
    expect([start.context, start.layers], [12288, 20]);
  });

  testWidgets('a context and a layer count are saved as they are typed', (
    tester,
  ) async {
    final rig = await openModelSettings(tester, lastUsedIsB: false);
    await typeLaunchValues(tester);

    final b = rig.store.backendSettings;
    expect([b.contextSize, b.gpuLayers], [12288, 20]);
  });

  testWidgets('an emptied layer count box does not become 0 at Start', (
    tester,
  ) async {
    final rig = await openModelSettings(tester, lastUsedIsB: false);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('gpu-layers-manual-switch')),
    );
    await settle(tester);
    final layers = find.byKey(const ValueKey('gpu-layers-number'));
    await tester.ensureVisible(layers);
    await tester.enterText(layers, '20');
    await tester.enterText(layers, '');
    await settle(tester);

    await pressDialogStart(tester, 'Start Backend');

    expect(
      rig.kobold.starts.single.layers,
      20,
      reason: 'an empty box saved 0, which keeps the model off the card',
    );
  });

  testWidgets('the context box shows the context a chosen preset set, and '
      'the user\'s own again after the preset is cleared', (tester) async {
    final rig = await openModelSettings(
      tester,
      lastUsedIsB: false,
      before: longChatsPreset,
    );
    final own = rig.store.backendSettings.contextSize;
    String box() => tester.widget<TextField>(contextBox()).controller!.text;
    await pickFromDropdown(tester, presetDropdown(), 'long.kcpps');

    expect(rig.store.backendSettings.contextSize, 32768);
    expect(
      box(),
      '32768',
      reason: 'the box still shows the context the dialog opened with',
    );

    await pickFromDropdown(tester, presetDropdown(), 'None (Use App Settings)');

    // The user's own context comes back with the preset cleared.
    expect(rig.store.backendSettings.contextSize, own);
    expect(box(), '$own');
  });
}
