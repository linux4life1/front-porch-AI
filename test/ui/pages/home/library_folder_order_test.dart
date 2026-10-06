// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #345: the folder tiles at the top of the home grid kept the order the
// folders were made in, whatever the sort said. They (and the group chats)
// now follow the sort. Drives the real CharacterCardGrid over a real
// FolderService on an in-memory database.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/cards/folder_grid_card.dart';
import 'package:front_porch_ai/ui/pages/home/cards/group_grid_card.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show CharacterCardGrid, FolderDialogAction, SearchScope;

import '../../../golden/support/fakes.dart';

class _Groups extends FakeGroupChatRepository {
  _Groups(this._groups);
  final List<GroupChat> _groups;
  @override
  List<GroupChat> get groups => _groups;
  @override
  Future<List<File>> getMemberAvatarFiles(String groupId) async => const [];
}

void main() {
  late AppDatabase db;
  late FolderService folders;
  late CharacterCard newest;
  late CharacterCard older;

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    folders = FolderService(db);
    // Made in the order Cedar, Birch, Aspen — the issue's C, B, A.
    final cedar = await folders.createFolder('Cedar');
    final birch = await folders.createFolder('Birch');
    final aspen = await folders.createFolder('Aspen');
    expect(cedar.id, isNotEmpty);

    newest = CharacterCard(name: 'Newest', imagePath: '/library/Newest.png')
      ..createdAt = DateTime(2026, 10, 1);
    older = CharacterCard(name: 'Older', imagePath: '/library/Older.png')
      ..createdAt = DateTime(2026, 1, 1);
    for (final c in [newest, older]) {
      await db.insertCharacterReturningId(
        CharactersCompanion(name: Value(c.name), imagePath: Value(c.imagePath)),
      );
    }
    await folders.addToFolder(birch.id, newest.imagePath!);
    await folders.addToFolder(aspen.id, older.imagePath!);
    await folders.reload();
  });

  tearDown(() async {
    folders.dispose();
    await db.close();
  });

  Future<void> pumpGrid(WidgetTester tester, {required String sortMode}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeCharacterRepository([newest, older]);
    addTearDown(repo.dispose);
    final groups = _Groups([
      GroupChat(id: 'group_z', name: 'Zeta Crew'),
      GroupChat(id: 'group_a', name: 'Alpha Crew'),
    ]);
    addTearDown(groups.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<CharacterRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: CharacterCardGrid(
              searchQuery: '',
              searchScope: SearchScope.allCharacters,
              activeFolderId: null,
              sortMode: sortMode,
              lastActivityCache: const {},
              messageCountCache: const {},
              gridScale: 200,
              isSelecting: false,
              isOrganizing: false,
              selectedCharacterIds: const {},
              selectedGroupIds: const {},
              searchController: TextEditingController(),
              gridScrollController: ScrollController(),
              repo: repo,
              folderService: folders,
              groupRepo: groups,
              modeToggle: const SizedBox.shrink(),
              onTapCharacter: (_) async {},
              onTapGroup: (_) async {},
              onToggleSelect: (_) {},
              onToggleSelectGroup: (_) {},
              onContextMenuAction: (_, _) {},
              onImport: (_) {},
              onAcceptFolderDrop: (_, _) {},
              onFolderDialogAction:
                  (FolderDialogAction _, {folder, parentId}) {},
              onFolderTap: (_) {},
              onFolderNavigateBack: () {},
              onFolderJump: (_) {},
              onCancelSelection: () {},
              onDeleteSelected: (_) {},
              onMoveToFolder: (_) {},
              onSortChanged: (_) {},
              onGridScaleChanged: (_) {},
              onSearchScopeChanged: (_) {},
              onSearchQueryChanged: (_) {},
              onResolveCharImage: (c) => File(c.imagePath ?? ''),
              onDeleteGroup: (_) {},
              onAfterNavigateBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> folderTiles(WidgetTester tester) => tester
      .widgetList<FolderGridCard>(find.byType(FolderGridCard))
      .map((w) => w.folder.name)
      .toList();

  List<String> groupTiles(WidgetTester tester) => tester
      .widgetList<GroupGridCard>(find.byType(GroupGridCard))
      .map((w) => w.group.name)
      .toList();

  testWidgets('Name (A→Z) puts folders and group chats in name order', (
    tester,
  ) async {
    await pumpGrid(tester, sortMode: 'name');
    expect(folderTiles(tester), ['Aspen', 'Birch', 'Cedar']);
    expect(groupTiles(tester), ['Alpha Crew', 'Zeta Crew']);
    // On screen, too: the first tile is the one furthest left.
    expect(
      tester.getTopLeft(find.text('Aspen')).dx,
      lessThan(tester.getTopLeft(find.text('Cedar')).dx),
    );
  });

  testWidgets('Import Date puts the folder with the newest card first and '
      'the empty one last', (tester) async {
    await pumpGrid(tester, sortMode: 'importDate');
    expect(folderTiles(tester), ['Birch', 'Aspen', 'Cedar']);
  });
}
