// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk_wizard_page.dart';

void main() {
  testWidgets('folder picker hides dot dirs until Show hidden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeskWizardPage(
          characters: [CharacterCard(name: 'Mira')],
          onSatDown: (_) {},
          initialFolder: '/tmp/home',
          listDirectory: (path) async => DeskFolderListing(
            path: path,
            parentPath: null,
            directories: const [
              DeskDirEntry(name: '.cache', path: '/tmp/home/.cache'),
              DeskDirEntry(name: 'Documents', path: '/tmp/home/Documents'),
            ],
            projectHints: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('.cache'), findsNothing);
    expect(find.byKey(const Key('desk-show-hidden')), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-show-hidden')));
    await tester.pump();
    expect(find.text('.cache'), findsOneWidget);
  });
}
