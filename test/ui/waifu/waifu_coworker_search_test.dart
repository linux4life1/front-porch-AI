// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_page.dart';

void main() {
  testWidgets('coworker search filters the grid by name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuWizardPage(
          skipProject: true,
          initialFolder: '/tmp/folder3',
          characters: [
            CharacterCard(name: 'Mira'),
            CharacterCard(name: 'Iris'),
            CharacterCard(name: 'Nina', tags: const ['tsundere']),
          ],
          onSatDown: (_) {},
          listDirectory: (path) async => WaifuFolderListing(
            path: path,
            parentPath: null,
            directories: const [],
            projectHints: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waifu-coworker-search')), findsOneWidget);
    expect(find.text('Mira'), findsOneWidget);
    expect(find.text('Iris'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('waifu-coworker-search')),
      'iri',
    );
    await tester.pump();
    expect(find.text('Iris'), findsOneWidget);
    expect(find.text('Mira'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('waifu-coworker-search')),
      'tsundere',
    );
    await tester.pump();
    expect(find.text('Nina'), findsOneWidget);
    expect(find.text('Iris'), findsNothing);
  });
}
