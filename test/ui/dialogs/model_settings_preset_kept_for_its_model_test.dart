// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Choosing a preset in the chat's Model Settings dialog, from the list or with
// Browse: a preset that names its own model is kept for that model, not for
// the model the dialog happened to show. Kept for the model on show, picking
// that model later turns the preset on and loads the other model instead.
// Clearing a preset (the list's "None" or the X on its chip) clears it for the
// model it loaded.
//
// The real dialog and the real launch; only the engine start is recorded, and
// the OS file dialog answers with a real file (see
// model_settings_dialog_harness.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/model_settings_dialog_harness.dart';
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

  void browsesTo(String path) {
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async =>
            FilePickerResult([PickedFile(path)]);
    addTearDown(() => PickerPrefs.testPickFilesOverride = null);
  }

  group('a preset that names model B, with model A on show', () {
    testWidgets('picked from the list is kept for B, and picking A later '
        'loads A', (tester) async {
      late String preset;
      final rig = await openModelSettings(
        tester,
        lastUsedIsB: false,
        before: (rig) async {
          preset = presetNaming(rig.store.binDir.path, 'b-own.kcpps', rig.b);
        },
      );
      expect(
        tester.widget<DropdownButton<String>>(modelDropdown()).value,
        rig.a,
        reason: 'the dialog opens on model A',
      );

      await pickFromDropdown(tester, presetDropdown(), 'b-own.kcpps');

      final links = Map.of(rig.store.presetSettings.modelPresetMap);
      expect(
        links[rig.b],
        preset,
        reason: 'kept for the model it names; saved links: $links',
      );
      expect(links[rig.a], isNull, reason: 'not for the model on show');

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
      await pressDialogStart(tester, 'Start Backend');

      final start = rig.kobold.starts.single;
      expect(start.model, rig.a, reason: 'picking A loads A');
      expect(start.kcpps, isNull);
    });

    testWidgets('browsed to is kept for B, and picking A later loads A', (
      tester,
    ) async {
      late String browsed;
      final rig = await openModelSettings(
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
      browsesTo(browsed);

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
      await pressDialogStart(tester, 'Start Backend');

      final start = rig.kobold.starts.single;
      expect(start.model, rig.a, reason: 'picking A loads A');
      expect(start.kcpps, isNull);
    });
  });

  testWidgets('a preset cleared with the X on its chip stays cleared for the '
      'model it loaded', (tester) async {
    late String browsed;
    final rig = await openModelSettings(
      tester,
      lastUsedIsB: true,
      before: (rig) async {
        // Model B running on a preset that is kept for it, from elsewhere.
        browsed = presetNaming(
          p.join(rig.dir.path, 'downloads'),
          'b-browsed.kcpps',
          rig.b,
        );
        await rig.store.presetSettings.setModelPreset(rig.b, browsed);
        await rig.store.backendSettings.setActiveKcppsPath(browsed);
      },
    );
    // The model list says "managed by the preset", so it names no model.
    await pickFromDropdown(tester, modelDropdown(), 'None (Managed by kcpps)');

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

    await pickFromDropdown(tester, modelDropdown(), p.basename(rig.b));
    await pressDialogStart(tester, 'Start Backend');

    final start = rig.kobold.starts.single;
    expect(start.model, rig.b);
    expect(
      start.kcpps,
      isNull,
      reason: 'picking B turned the cleared preset back on',
    );
  });
}
