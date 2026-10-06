// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared by the library gesture tests (phases 2–3): the real
// CharacterCardGrid over a real FolderService on an in-memory database,
// wired to a LibrarySelection exactly the way HomePage wires it, plus a
// FolderService that records every moveMany it is asked for.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show CharacterCardGrid, FolderDialogAction, SearchScope;

import '../../../golden/support/fakes.dart';

/// One moveMany request, as FolderService received it.
typedef MoveCall = ({String? folderId, Set<String> files, Set<String> groups});

class SpyFolderService extends FolderService {
  SpyFolderService(super.db);

  final moves = <MoveCall>[];

  @override
  Future<int> moveMany({
    required String? folderId,
    Iterable<String> characterPaths = const [],
    Iterable<String> groupIds = const [],
  }) {
    moves.add((
      folderId: folderId,
      files: {for (final p in characterPaths) p.split('/').last},
      groups: groupIds.toSet(),
    ));
    return super.moveMany(
      folderId: folderId,
      characterPaths: characterPaths,
      groupIds: groupIds,
    );
  }
}

class GestureGroups extends FakeGroupChatRepository {
  GestureGroups(this._groups);
  final List<GroupChat> _groups;
  @override
  List<GroupChat> get groups => _groups;
  @override
  Future<List<File>> getMemberAvatarFiles(String groupId) async => const [];
}

/// A library with characters [names] (image `/library/<name>.png`) and the
/// group chats [groups], all in the database.
class GestureLibrary {
  GestureLibrary._(this.db, this.folders, this.cards, this.groups);

  final AppDatabase db;
  final SpyFolderService folders;
  final List<CharacterCard> cards;
  final List<GroupChat> groups;
  final selection = LibrarySelection();
  final opened = <String>[];

  /// What each drop returned: how many moved, or null for "nothing dropped".
  final drops = <int?>[];

  static Future<GestureLibrary> create(
    List<String> names, {
    List<GroupChat> groups = const [],
  }) async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    final cards = [
      for (final n in names)
        CharacterCard(name: n, imagePath: '/library/$n.png'),
    ];
    for (final c in cards) {
      await db.insertCharacterReturningId(
        CharactersCompanion(name: Value(c.name), imagePath: Value(c.imagePath)),
      );
    }
    for (final g in groups) {
      await db.insertGroup(GroupsCompanion.insert(id: g.id, name: g.name));
    }
    final folders = SpyFolderService(db);
    await folders.reload();
    return GestureLibrary._(db, folders, cards, groups);
  }

  Future<void> dispose() async {
    selection.dispose();
    folders.dispose();
    await db.close();
  }

  CharacterCard card(String name) => cards.firstWhere((c) => c.name == name);

  Future<void> pump(
    WidgetTester tester, {
    String? folderId,
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeCharacterRepository(cards);
    addTearDown(repo.dispose);
    final groupRepo = GestureGroups(groups);
    addTearDown(groupRepo.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final sel = selection;
    Future<void> drop(Object item, String? id) async =>
        drops.add(await sel.drop(item, id, folders: folders, library: cards));
    await tester.pumpWidget(
      ChangeNotifierProvider<CharacterRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: Listenable.merge([sel, folders]),
              builder: (context, _) => CharacterCardGrid(
                searchQuery: '',
                searchScope: SearchScope.allCharacters,
                activeFolderId: folderId,
                sortMode: 'name',
                lastActivityCache: const {},
                messageCountCache: const {},
                gridScale: 200,
                isSelecting: sel.isSelecting,
                isOrganizing: sel.isOrganizing,
                selectedCharacterIds: sel.characterIds,
                selectedGroupIds: sel.groupIds,
                searchController: TextEditingController(),
                gridScrollController: scroll,
                repo: repo,
                folderService: folders,
                groupRepo: groupRepo,
                modeToggle: const SizedBox.shrink(),
                onTapCharacter: (c) async => opened.add(c.name),
                onTapGroup: (g) async => opened.add(g.name),
                onToggleSelect: (c) =>
                    sel.toggle(c.stableGroupId, group: false),
                onToggleSelectGroup: (g) => sel.toggle(g.id, group: true),
                onToggleSelectMode: sel.toggleSelectMode,
                onToggleOrganizeMode: sel.toggleOrganizeMode,
                onContextMenuAction: (_, _) {},
                onImport: (_) {},
                onAcceptFolderDrop: (item, f) => drop(item, f.id),
                onFolderDialogAction:
                    (FolderDialogAction _, {folder, parentId}) {},
                onFolderTap: (_) {},
                onFolderNavigateBack: () {},
                onFolderJump: (_) {},
                onCancelSelection: sel.cancel,
                onDeleteSelected: (_) {},
                onMoveToFolder: (_) {},
                onSortChanged: (_) {},
                onGridScaleChanged: (_) {},
                onSearchScopeChanged: (_) {},
                onSearchQueryChanged: (_) {},
                onResolveCharImage: (c) => File(c.imagePath ?? ''),
                onDeleteGroup: (_) {},
                onAfterNavigateBack: () {},
                onSelectAll: sel.selectAll,
                onSelectNone: sel.selectNone,
                selection: sel,
                onDropOnLevel: drop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }
}

/// The centre of the grid card showing [name].
Offset centerOf(WidgetTester tester, String name) =>
    tester.getCenter(find.text(name).first);
