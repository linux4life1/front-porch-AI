// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Create World → From character copies only the ticked entries into the
// place draft. The header glow ticker is repeating, so pumps stay bounded.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/pick_character_lore_entries_dialog.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';

import '../../golden/support/fakes.dart';

CharacterCard _keeper() {
  return CharacterCard(
    name: 'Pier Keeper',
    lorebook: Lorebook(
      entries: [
        LorebookEntry(
          name: 'Harbor bell',
          keys: const ['harbor'],
          content: 'Rings at dusk.',
          stickyDepth: 4,
        ),
        LorebookEntry(
          name: 'Market day',
          keys: const ['market'],
          content: 'Stalls at dawn.',
          stickyDepth: 2,
        ),
      ],
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scroll the Create World body until [finder] is on screen. Never
/// pumpAndSettle: the page header ticker repeats forever.
Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12; i++) {
    if (finder.evaluate().isNotEmpty) {
      final rect = tester.getRect(finder.first);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      if (rect.top >= 0 && rect.bottom <= size.height) return;
    }
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -280),
    );
    await _pump(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the picker returns only the ticked entries', (tester) async {
    CharacterLoreSelection? pick;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                pick = await showPickCharacterLoreEntriesDialog(
                  context: context,
                  characters: [
                    _keeper(),
                    CharacterCard(name: 'Quiet Extra'),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await _pump(tester);

    expect(find.text('Quiet Extra'), findsNothing);
    expect(find.text('Pier Keeper'), findsOneWidget);
    expect(find.text('P'), findsOneWidget);
    await tester.tap(find.text('Pier Keeper'));
    await _pump(tester);

    expect(find.text('Harbor bell'), findsOneWidget);
    expect(find.text('Market day'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add selected'), findsOneWidget);

    await tester.tap(find.text('Harbor bell'));
    await _pump(tester);
    await tester.tap(find.text('Add 1 entry'));
    await _pump(tester);

    expect(pick, isNotNull);
    expect(pick!.characterName, 'Pier Keeper');
    expect(pick!.entries.map((e) => e.name), ['Harbor bell']);
    expect(pick!.entries.single.stickyDepth, 4);
    expect(pick!.entries.single.content, 'Rings at dusk.');
  });

  testWidgets('a character row shows that card\'s portrait', (tester) async {
    final portrait = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}fp_lore_pick_avatar.png',
    );
    // 1×1 PNG. The row paints this file beside the name.
    portrait.writeAsBytesSync(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x78,
      0x9C,
      0x63,
      0x00,
      0x01,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x0A,
      0x2D,
      0xB4,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    addTearDown(() async {
      if (portrait.existsSync()) await portrait.delete();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showPickCharacterLoreEntriesDialog(
                  context: context,
                  characters: [
                    CharacterCard(
                      name: 'Pier Keeper',
                      imagePath: portrait.path,
                      lorebook: Lorebook(
                        entries: [
                          LorebookEntry(name: 'Harbor bell', content: 'Rings.'),
                        ],
                      ),
                    ),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await _pump(tester);

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage;
    expect(image, isA<FileImage>());
    expect((image! as FileImage).file.path, portrait.path);
    expect(find.text('P'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Create World keeps only the entries that were ticked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final worlds = FakeWorldRepository();
    final characters = FakeCharacterRepository([
      _keeper(),
      CharacterCard(name: 'Quiet Extra'),
    ]);
    addTearDown(worlds.dispose);
    addTearDown(characters.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ChangeNotifierProvider<CharacterRepository>.value(value: characters),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
          home: const WorldManagementPage(),
        ),
      ),
    );
    await _pump(tester);

    await tester.tap(find.widgetWithText(ElevatedButton, 'New World'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await _bringIntoView(tester, find.text('From character'));
    await tester.tap(find.text('From character'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Quiet Extra'), findsNothing);
    await tester.tap(find.text('Pier Keeper'));
    await _pump(tester);
    await tester.tap(find.text('Harbor bell'));
    await _pump(tester);
    await tester.tap(find.text('Add 1 entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Lorebook Entries (1)'), findsOneWidget);
    expect(find.text('Harbor bell'), findsOneWidget);
    expect(find.text('Market day'), findsNothing);
    expect(find.text('Depth 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
