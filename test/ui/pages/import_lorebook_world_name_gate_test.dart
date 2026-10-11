// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Import Lorebook's last step reads the World name to decide whether Import
// may run. The button is only rebuilt when something rebuilds the page, so
// without a listener on the name field, clearing it left Import enabled and
// created a World named "". Driven through the real wizard over the real
// library; only the OS file dialog is replaced (PickerPrefs'
// testPickFilesOverride, as the lorebook_import E2E does).
// Proven red by dropping the World-name listener in ImportLorebookPage.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/import_lorebook_page.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'home/home_page_harness.dart';

const _book = {
  'name': 'Hollow Creek',
  'entries': {
    '0': {
      'uid': 0,
      'key': ['mill'],
      'content': 'The mill wheel has not turned since the flood.',
    },
    '1': {
      'uid': 1,
      'key': ['ferryman'],
      'content': 'He only crosses at dusk, and never for coin.',
    },
  },
};

void main() {
  testWidgets('clearing the World name disables Import; a name re-enables it', (
    tester,
  ) async {
    final rig = await HomeRig.build(tester);
    PickerPrefs.testPickFilesOverride =
        ({required String category, List<String>? allowedExtensions}) async =>
            FilePickerResult([
              MemoryPlatformFile(
                name: 'hollow_creek.json',
                bytes: utf8.encode(jsonEncode(_book)),
              ),
            ]);
    addTearDown(() => PickerPrefs.testPickFilesOverride = null);

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: rig.chat),
          ChangeNotifierProvider<CharacterRepository>.value(
            value: rig.characters,
          ),
        ],
        child: const MaterialApp(home: ImportLorebookPage()),
      ),
    );

    await tester.tap(find.text('Choose a lorebook file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
    await tester.pumpAndSettle();
    expect(find.text('Where should this lorebook live?'), findsOneWidget);

    final import = find.widgetWithText(ElevatedButton, 'Import 2 entries');
    bool importEnabled() => tester.widget<ElevatedButton>(import).enabled;
    final name = find.widgetWithText(TextField, 'World name');

    expect(
      tester.widget<TextField>(name).controller!.text,
      'Hollow Creek',
      reason: 'the World name starts from the book',
    );
    expect(importEnabled(), isTrue);

    await tester.enterText(name, '   ');
    await tester.pump();
    expect(
      importEnabled(),
      isFalse,
      reason: 'a blank World name must disable Import as it is cleared',
    );

    await tester.enterText(name, 'Mill Town');
    await tester.pump();
    expect(importEnabled(), isTrue, reason: 'typing a name re-enables Import');
  });
}
