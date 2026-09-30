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

// Export on the character editor's Lorebook tab writes a SillyTavern
// world-info file that the same tab's Import file can read back.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RepoWithCover extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpEditor(
    WidgetTester tester, {
    required CharacterCard card,
    required Size surface,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _RepoWithCover();
    final chat = FakeChatService();
    final storage = FakeStorageService();
    final worlds = FakeWorldRepository();
    addTearDown(repo.dispose);
    addTearDown(chat.dispose);
    addTearDown(storage.dispose);
    addTearDown(worlds.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CharacterRepository>.value(value: repo),
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<WorldRepository>.value(value: worlds),
        ],
        child: MaterialApp(home: EditCharacterPage(character: card)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lorebook'));
    await tester.pumpAndSettle();
  }

  testWidgets('Export file writes world-info JSON the importer can read', (
    tester,
  ) async {
    Uint8List? savedBytes;
    String? savedName;
    String? savedTitle;
    String? savedCategory;
    List<String>? savedExtensions;
    PickerPrefs.testSaveFileOverride =
        ({
          required String category,
          required Uint8List bytes,
          String? dialogTitle,
          String? fileName,
          FileType? type,
          List<String>? allowedExtensions,
        }) async {
          savedCategory = category;
          savedBytes = bytes;
          savedName = fileName;
          savedTitle = dialogTitle;
          savedExtensions = allowedExtensions;
          return '/tmp/pier_lorebook.json';
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);

    await pumpEditor(
      tester,
      surface: const Size(780, 900),
      card: CharacterCard(
        name: 'Pier & Lantern',
        lorebook: Lorebook(
          entries: [
            LorebookEntry(
              name: 'Harbor bell',
              keys: const ['harbor', 'bell'],
              content: 'The bell rings at dusk.',
              stickyDepth: 3,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Export file'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Dialog width is 780. The four labels have to share that line.
    final actionTops = [
      tester.getRect(find.text('Import file')).top,
      tester.getRect(find.text('Export file')).top,
      tester.getRect(find.text('From character')).top,
      tester.getRect(find.text('Add Entry')).top,
    ];
    expect(actionTops.toSet(), hasLength(1));

    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();
    // Entries start ticked. Confirm the picker before the save dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(savedCategory, PickerPrefs.catExport);
    expect(savedTitle, 'Export lorebook');
    expect(savedName, 'Pier_Lantern_lorebook.json');
    expect(savedExtensions, ['json']);
    expect(savedBytes, isNotNull);

    final decoded =
        jsonDecode(utf8.decode(savedBytes!)) as Map<String, dynamic>;
    expect(decoded['entries'], isA<Map>());
    expect(decoded['name'], 'Pier & Lantern');
    final restored = Lorebook.fromJson(decoded);
    expect(restored.entries, hasLength(1));
    expect(restored.entries.single.name, 'Harbor bell');
    expect(restored.entries.single.keys, ['harbor', 'bell']);
    expect(restored.entries.single.content, 'The bell rings at dusk.');
    expect(restored.entries.single.stickyDepth, 3);
    expect(find.text('Exported 1 entry.'), findsOneWidget);
  });

  testWidgets('an empty lorebook does not open the save dialog', (
    tester,
  ) async {
    var saved = false;
    PickerPrefs.testSaveFileOverride =
        ({
          required String category,
          required Uint8List bytes,
          String? dialogTitle,
          String? fileName,
          FileType? type,
          List<String>? allowedExtensions,
        }) async {
          saved = true;
          return '/tmp/should-not-write.json';
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);

    await pumpEditor(
      tester,
      surface: const Size(640, 800),
      card: CharacterCard(name: 'Pier & Lantern'),
    );

    expect(find.text('Export file'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(find.text('No lorebook entries to export.'), findsOneWidget);
  });
}
