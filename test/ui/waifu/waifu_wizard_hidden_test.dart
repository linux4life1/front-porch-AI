// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_page.dart';

void main() {
  testWidgets('folder picker hides dot dirs until Show hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuWizardPage(
          characters: [CharacterCard(name: 'Mira')],
          onSatDown: (_) {},
          initialFolder: '/tmp/home',
          listDirectory: (path) async => WaifuFolderListing(
            path: path,
            parentPath: null,
            directories: const [
              WaifuDirEntry(name: '.cache', path: '/tmp/home/.cache'),
              WaifuDirEntry(name: 'Documents', path: '/tmp/home/Documents'),
            ],
            projectHints: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('.cache'), findsNothing);
    expect(find.byKey(const Key('waifu-show-hidden')), findsOneWidget);
    await tester.tap(find.byKey(const Key('waifu-show-hidden')));
    await tester.pump();
    expect(find.text('.cache'), findsOneWidget);
  });
}
