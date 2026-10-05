// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Choosing a preset on Settings -> Backend, from the list or with Browse: a
// preset that names its own model is kept for that model, not for the model
// the dropdown happened to show. Kept for the model on show, picking that
// model later turns the preset on and loads the other model instead.
//
// The real Settings page and the real launch; only the engine start is
// recorded, and the OS file dialog answers with a real file (see
// settings_page_harness.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
  Finder modelDropdown() => find.descendant(
    of: find.byType(ModelSelector),
    matching: find.byType(DropdownButton<String>),
  );

  /// The dropdown shows model A and the user picks a preset that names B;
  /// then clears it and picks A. What is saved, and what Start loads.
  group('a preset that names model B, with model A on show', () {
    testWidgets('picked from the list is kept for B, and picking A later '
        'loads A', (tester) async {
      late String preset;
      final rig = await mountSettings(
        tester,
        lastUsedIsB: false,
        before: (rig) async {
          preset = presetNaming(rig.store.binDir.path, 'b-own.kcpps', rig.b);
        },
      );
      await openTab(tester, 'Backend');
      expect(
        tester.widget<DropdownButton<String>>(modelDropdown()).value,
        rig.a,
        reason: 'the page opens on model A',
      );

      // The hardware-detected snackbar from opening the page goes first.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pump();
      await pickFromDropdown(tester, presetDropdown(), 'b-own.kcpps');

      final links = Map.of(rig.store.presetSettings.modelPresetMap);
      expect(
        links[rig.b],
        preset,
        reason: 'kept for the model it names; saved links: $links',
      );
      expect(links[rig.a], isNull, reason: 'not for the model on show');
      expect(
        find.text('Preset saved for model: ${p.basename(rig.b)}'),
        findsOneWidget,
        reason: 'the message names the model the preset was saved for',
      );

      await pickFromDropdown(
        tester,
        presetDropdown(),
        'None (Use App Settings)',
      );
      expect(
        rig.store.presetSettings.modelPresetMap[rig.b] ?? '',
        isEmpty,
        reason: 'clearing the preset clears it for the model it was kept for',
      );
      await pickFromDropdown(tester, modelDropdown(), p.basename(rig.a));
      await tapVisible(tester, find.text('Start Backend'));
      await settle(tester, () => rig.kobold.starts.isNotEmpty);

      final start = rig.kobold.starts.single;
      expect(start.model, rig.a, reason: 'picking A loads A');
      expect(start.kcpps, isNull);
    });

    testWidgets('browsed to is kept for B, and picking A later loads A', (
      tester,
    ) async {
      late String browsed;
      final rig = await mountSettings(
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
      PickerPrefs.testPickFilesOverride =
          ({required String category, List<String>? allowedExtensions}) async =>
              FilePickerResult([PickedFile(browsed)]);
      addTearDown(() => PickerPrefs.testPickFilesOverride = null);
      await openTab(tester, 'Backend');

      await tapVisible(tester, find.byTooltip('Browse'));
      await settle(tester);

      final links = Map.of(rig.store.presetSettings.modelPresetMap);
      expect(
        links[rig.b],
        browsed,
        reason: 'kept for the model it names; saved links: $links',
      );
      expect(links[rig.a], isNull, reason: 'not for the model on show');
      expect(
        rig.store.backendSettings.lastUsedModelPath,
        rig.b,
        reason: 'the model the preset loads is the model in use',
      );

      await pickFromDropdown(tester, modelDropdown(), p.basename(rig.a));
      await tapVisible(tester, find.text('Start Backend'));
      await settle(tester, () => rig.kobold.starts.isNotEmpty);

      final start = rig.kobold.starts.single;
      expect(start.model, rig.a, reason: 'picking A loads A');
      expect(start.kcpps, isNull);
    });
  });
}
