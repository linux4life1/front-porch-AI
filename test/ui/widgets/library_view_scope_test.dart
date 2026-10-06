// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #346: the search scope works at every level of the home library.
//   - Everywhere ignores folders.
//   - Folder & subfolders looks inside the open folder and everything below
//     it (at the top level that is the whole library, so it matches
//     Everywhere).
//   - This folder only looks at the open folder's own cards; at the top
//     level that means "Top level only": cards in no folder.
// Group chats follow the same rule as characters. Browsing (no search) is
// unchanged. The matrix runs on libraryViewOf, the one helper the grid
// draws from, over a real FolderService.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/ui/widgets/library_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FolderService folders;
  late String outerId;
  late String innerId;
  final cards = [
    for (final name in ['Porch Top', 'Porch Outer', 'Porch Inner', 'Quiet'])
      CharacterCard(
        name: name,
        imagePath: '/library/${name.replaceAll(' ', '_')}.png',
      ),
  ];
  final groups = [
    GroupChat(id: 'group_top', name: 'Porch Crew Top'),
    GroupChat(id: 'group_outer', name: 'Porch Crew Outer'),
    GroupChat(id: 'group_inner', name: 'Porch Crew Inner'),
  ];

  setUp(() async {
    db = AppDatabase.forTesting();
    for (final c in cards) {
      await db.insertCharacterReturningId(
        CharactersCompanion(name: Value(c.name), imagePath: Value(c.imagePath)),
      );
    }
    for (final g in groups) {
      await db.insertGroup(GroupsCompanion.insert(id: g.id, name: g.name));
    }
    folders = FolderService(db);
    final outer = await folders.createFolder('Outer');
    final inner = await folders.createFolder('Inner', parentId: outer.id);
    outerId = outer.id;
    innerId = inner.id;
    await folders.addToFolder(outerId, '/library/Porch_Outer.png');
    await folders.addToFolder(innerId, '/library/Porch_Inner.png');
    await folders.addGroupToFolder(outerId, 'group_outer');
    await folders.addGroupToFolder(innerId, 'group_inner');
    await folders.reload();
  });

  tearDown(() async {
    folders.dispose();
    await db.close();
  });

  LibraryView view({
    String? folder,
    String query = 'porch',
    required SearchScope scope,
  }) => libraryViewOf(
    characters: cards,
    groups: groups,
    folders: folders,
    activeFolderId: folder,
    query: query,
    scope: scope,
    sortMode: 'name',
  );

  Set<String> chars(LibraryView v) => {for (final c in v.characters) c.name};
  Set<String> casts(LibraryView v) => {for (final g in v.groups) g.name};

  group('top level', () {
    test('Everywhere finds cards and groups in every folder', () {
      final v = view(scope: SearchScope.allCharacters);
      expect(chars(v), {'Porch Top', 'Porch Outer', 'Porch Inner'});
      expect(casts(v), {
        'Porch Crew Top',
        'Porch Crew Outer',
        'Porch Crew Inner',
      });
    });

    test('folder & subfolders at the top level matches Everywhere', () {
      final v = view(scope: SearchScope.folderRecursive);
      expect(chars(v), {'Porch Top', 'Porch Outer', 'Porch Inner'});
      expect(casts(v), {
        'Porch Crew Top',
        'Porch Crew Outer',
        'Porch Crew Inner',
      });
    });

    test('Top level only finds just what is in no folder', () {
      final v = view(scope: SearchScope.currentFolder);
      expect(chars(v), {'Porch Top'});
      expect(casts(v), {'Porch Crew Top'});
    });

    test('browsing shows the folder tile and only unfoldered cards', () {
      final v = view(query: '', scope: SearchScope.currentFolder);
      expect(chars(v), {'Porch Top', 'Quiet'});
      expect(casts(v), {'Porch Crew Top'});
      expect(v.folders.map((f) => f.name), ['Outer']);
    });
  });

  group('inside a folder', () {
    test('This folder only does not look in its subfolders', () {
      final v = view(folder: outerId, scope: SearchScope.currentFolder);
      expect(chars(v), {'Porch Outer'});
      expect(casts(v), {'Porch Crew Outer'});
    });

    test('Folder & subfolders looks one level down and further', () {
      final v = view(folder: outerId, scope: SearchScope.folderRecursive);
      expect(chars(v), {'Porch Outer', 'Porch Inner'});
      expect(casts(v), {'Porch Crew Outer', 'Porch Crew Inner'});
    });

    test('Everywhere leaves the folder behind', () {
      final v = view(folder: innerId, scope: SearchScope.allCharacters);
      expect(chars(v), {'Porch Top', 'Porch Outer', 'Porch Inner'});
    });

    test('searching hides folder tiles; browsing shows direct members', () {
      expect(
        view(folder: outerId, scope: SearchScope.folderRecursive).folders,
        isEmpty,
      );
      final browse = view(
        folder: outerId,
        query: '',
        scope: SearchScope.allCharacters,
      );
      expect(chars(browse), {'Porch Outer'});
      expect(casts(browse), {'Porch Crew Outer'});
      expect(browse.folders.map((f) => f.name), ['Inner']);
    });
  });
}
