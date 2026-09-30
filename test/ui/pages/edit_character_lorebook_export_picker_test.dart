// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Export file asks which lore entries to write. All start ticked.
// Cancel and an empty selection write nothing.

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

  Future<void> pumpEditor(WidgetTester tester, {required Size surface}) async {
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
        child: MaterialApp(
          home: EditCharacterPage(
            character: CharacterCard(
              name: 'Pier & Lantern',
              lorebook: Lorebook(
                entries: [
                  LorebookEntry(
                    name: 'Harbor bell',
                    keys: const ['harbor', 'bell'],
                    content: 'The bell rings at dusk.',
                  ),
                  LorebookEntry(
                    name: 'Salt lamp',
                    keys: const ['salt', 'lamp'],
                    content: 'A lamp of salt.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lorebook'));
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.text('Export file'));
    await tester.pumpAndSettle();
  }

  testWidgets('default export writes every entry', (tester) async {
    Uint8List? savedBytes;
    String? savedName;
    PickerPrefs.testSaveFileOverride =
        ({
          required String category,
          required Uint8List bytes,
          String? dialogTitle,
          String? fileName,
          FileType? type,
          List<String>? allowedExtensions,
        }) async {
          savedBytes = bytes;
          savedName = fileName;
          return '/tmp/pier_lorebook.json';
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);

    await pumpEditor(tester, surface: const Size(800, 900));
    await openPicker(tester);

    expect(find.text('Harbor bell'), findsWidgets);
    expect(find.text('harbor, bell'), findsOneWidget);
    expect(find.text('Salt lamp'), findsWidgets);
    expect(find.text('salt, lamp'), findsOneWidget);
    expect(find.text('Select none'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    expect(savedName, 'Pier_Lantern_lorebook.json');
    final restored = Lorebook.fromJson(
      jsonDecode(utf8.decode(savedBytes!)) as Map<String, dynamic>,
    );
    expect(restored.entries.map((e) => e.name), ['Harbor bell', 'Salt lamp']);
    expect(find.text('Exported 2 entries.'), findsOneWidget);
  });

  testWidgets('unticking an entry leaves it out of the file', (tester) async {
    Uint8List? savedBytes;
    PickerPrefs.testSaveFileOverride =
        ({
          required String category,
          required Uint8List bytes,
          String? dialogTitle,
          String? fileName,
          FileType? type,
          List<String>? allowedExtensions,
        }) async {
          savedBytes = bytes;
          return '/tmp/pier_lorebook.json';
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);

    await pumpEditor(tester, surface: const Size(800, 900));
    await openPicker(tester);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Salt lamp'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await tester.pumpAndSettle();

    final restored = Lorebook.fromJson(
      jsonDecode(utf8.decode(savedBytes!)) as Map<String, dynamic>,
    );
    expect(restored.entries.map((e) => e.name), ['Harbor bell']);
    expect(find.text('Exported 1 entry.'), findsOneWidget);
  });

  testWidgets('Select none disables Export', (tester) async {
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
          return '/tmp/pier_lorebook.json';
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);

    await pumpEditor(tester, surface: const Size(390, 844));
    await openPicker(tester);

    await tester.tap(find.text('Select none'));
    await tester.pumpAndSettle();

    final export = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export'),
    );
    expect(export.onPressed, isNull);
    expect(find.text('Select all'), findsOneWidget);
    expect(saved, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel writes nothing', (tester) async {
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
          return '/tmp/pier_lorebook.json';
        };
    addTearDown(() => PickerPrefs.testSaveFileOverride = null);

    await pumpEditor(tester, surface: const Size(800, 900));
    await openPicker(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(find.textContaining('Exported'), findsNothing);
  });
}
