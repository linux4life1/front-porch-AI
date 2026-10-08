// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The chat's Model Settings dialog starts its model list on the model in use
// when nothing is chosen: after a preset that names its own model is cleared
// the list shows that model, as Settings does, not the first file in the
// folder. It used to show the first file, so Start Backend loaded another
// model and the model that was running was forgotten.
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
  testWidgets('after a preset that names model B is cleared, the model list '
      'shows B and Start loads it', (tester) async {
    final rig = await openModelSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        File(p.join(rig.store.binDir.path, 'b-own.kcpps')).writeAsStringSync(
          jsonEncode({'model_param': rig.b, 'contextsize': 8192}),
        );
      },
    );
    final presets = find.descendant(
      of: find.byType(KcppsSelector),
      matching: find.byType(DropdownButton<String>),
    );
    final models = find.descendant(
      of: find.byType(ModelSelector),
      matching: find.byType(DropdownButton<String>),
    );

    await pickFromDropdown(tester, presets, 'b-own.kcpps');
    await pickFromDropdown(tester, presets, 'None (Use App Settings)');

    expect(
      tester.widget<DropdownButton<String>>(models).value,
      rig.b,
      reason: 'B is the model in use, but the list went back to the first file',
    );

    await pressDialogStart(tester, 'Start Backend');

    expect(rig.kobold.starts.single.model, rig.b);
    expect(rig.store.backendSettings.lastUsedModelPath, rig.b);
  });
}
