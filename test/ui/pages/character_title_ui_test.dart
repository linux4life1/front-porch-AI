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

// The desktop half of a character's Title: the editor's Title field (library
// cards only; a group member's copy has nowhere to keep one), the line under
// the name on a library tile, and the library search. The web twins are
// pinned in web_ui (CharacterEditPage.title.test.tsx, LibraryCards.title.test.tsx).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page/group_member_mode.dart';
import 'package:front_porch_ai/ui/pages/home/cards/character_grid_card_face.dart';
import 'package:front_porch_ai/ui/widgets/library_view.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import '../../helpers/double_tap.dart';

/// The Details tab asks for the cover; the shared fake throws on unknowns.
class _RepoWithCover extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the editor Title field', () {
    Future<List<CharacterCard>> pumpEditor(
      WidgetTester tester,
      CharacterCard card, {
      GroupMemberMode? member,
    }) async {
      final writes = <CharacterCard>[];
      await tester.binding.setSurfaceSize(const Size(1280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = _RepoWithCover();
      final chat = FakeChatService();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      addTearDown(repo.dispose);
      addTearDown(chat.dispose);
      addTearDown(storage.dispose);
      addTearDown(worlds.dispose);
      // No AppDatabase: the editor treats it as optional, and a Drift call
      // inside testWidgets' fake-async zone never completes.
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
              character: card,
              member: member,
              onSaveOverride: (c) async => writes.add(c),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return writes;
    }

    Finder titleField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == kCardTitleHint,
    );

    testWidgets('sits under Name, shows the card\'s title, and Save writes '
        'the typed title once', (tester) async {
      final card = CharacterCard(name: 'Misty', title: 'Weather Girl');
      final writes = await pumpEditor(tester, card);

      expect(find.text('Title'), findsOneWidget);
      expect(find.text(kCardTitleHelp), findsOneWidget);
      expect(titleField(), findsOneWidget);
      expect(
        tester.getTopLeft(titleField()).dy,
        greaterThan(tester.getTopLeft(find.text('Name')).dy),
      );
      expect(find.text('Weather Girl'), findsOneWidget);

      await tester.enterText(
        titleField(),
        '  Misty Meadows, Misguided Meteorologist ',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save'));
      await doubleTapNoFrame(tester, find.text('Save'));
      await tester.pumpAndSettle();

      expect(writes, hasLength(1));
      expect(writes.single.name, 'Misty');
      expect(writes.single.title, 'Misty Meadows, Misguided Meteorologist');
    });

    testWidgets('is not offered on a group member\'s copy', (tester) async {
      await pumpEditor(
        tester,
        CharacterCard(name: 'Mara'),
        member: GroupMemberMode(
          groupName: 'Pair',
          memberId: 'mem-mara',
          others: const [],
          scene: const GroupSceneTime(),
          values: const GroupMemberValues(),
          saveValues: (_) async {},
        ),
      );
      expect(find.text('Name'), findsOneWidget);
      expect(titleField(), findsNothing);
      expect(find.text(kCardTitleHelp), findsNothing);
    });
  });

  group('a library tile', () {
    Widget tile(CharacterCard card) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          height: 343,
          child: CharacterGridCardFullBody(
            character: card,
            onResolveCharImage: (_) => File('missing.png'),
            imageCacheEpoch: 0,
            msgCount: 0,
            isCompact: false,
          ),
        ),
      ),
    );

    testWidgets('shows the title under the name in place of the tags', (
      tester,
    ) async {
      await tester.pumpWidget(
        tile(
          CharacterCard(
            name: 'Misty',
            title: 'Misty Meadows, Misguided Meteorologist',
            tags: ['weather'],
          ),
        ),
      );
      expect(find.text('Misty'), findsOneWidget);
      expect(
        find.text('Misty Meadows, Misguided Meteorologist'),
        findsOneWidget,
      );
      expect(find.text('weather'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('without a title keeps the tags', (tester) async {
      await tester.pumpWidget(
        tile(CharacterCard(name: 'Misty', tags: ['weather'])),
      );
      expect(find.text('weather'), findsOneWidget);
    });
  });

  test('the library search finds a card by its title', () async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);
    final folders = FolderService(db);
    addTearDown(folders.dispose);
    final cards = [
      CharacterCard(
        name: 'Misty',
        title: 'Misguided Meteorologist',
        imagePath: '/library/Misty.png',
      ),
      CharacterCard(name: 'Rowan', imagePath: '/library/Rowan.png'),
    ];
    for (final c in cards) {
      await db.insertCharacterReturningId(
        CharactersCompanion(name: Value(c.name), imagePath: Value(c.imagePath)),
      );
    }
    await folders.reload();

    final view = libraryViewOf(
      characters: cards,
      groups: const [],
      folders: folders,
      activeFolderId: null,
      query: 'meteor',
      scope: SearchScope.allCharacters,
      sortMode: 'name',
    );
    expect([for (final c in view.characters) c.name], ['Misty']);
  });
}
