// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset chosen with Browse on Settings -> Backend goes into a running
// KoboldCpp, as one chosen from the list does. It used to be chosen and
// shown, and KoboldCpp kept running the old model and settings until the next
// restart.
//
// The real Settings page; the engine is marked running and the live reload is
// counted, and the OS file dialog answers with a real file (see
// settings_page_harness.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  testWidgets('a preset chosen with Browse goes into the running KoboldCpp, '
      'like one chosen from the list', (tester) async {
    late String browsed;
    final rig = await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) async {
        File(
          p.join(rig.store.binDir.path, 'list.kcpps'),
        ).writeAsStringSync(jsonEncode({'contextsize': 8192}));
        browsed = p.join(rig.dir.path, 'downloads', 'browsed.kcpps');
        File(browsed)
          ..createSync(recursive: true)
          ..writeAsStringSync(jsonEncode({'contextsize': 12288}));
        rig.kobold.debugMarkProcessRunning();
      },
    );
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async =>
            FilePickerResult([PickedFile(browsed)]);
    addTearDown(() => PickerPrefs.testPickFilesOverride = null);
    await openTab(tester, 'Backend');

    await pickFromDropdown(
      tester,
      find.descendant(
        of: find.byType(KcppsSelector),
        matching: find.byType(DropdownButton<String>),
      ),
      'list.kcpps',
    );
    final fromList = rig.llm.reloads;
    expect(fromList, 1, reason: 'a preset from the list reloads the engine');

    await tapVisible(tester, find.byTooltip('Browse'));
    await settle(tester);

    expect(rig.store.backendSettings.activeKcppsPath, browsed);
    expect(
      rig.llm.reloads - fromList,
      1,
      reason: 'the browsed preset is chosen but the engine was not told',
    );
  });
}
