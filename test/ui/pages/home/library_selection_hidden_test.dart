// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #347: picks stay selected when a later search or folder change hides
// them, so the counts say how many are out of sight: "2 selected
// (1 hidden)" in the header and in the bottom bar. Before, the bar said
// "2 selected" while only one card on screen was ticked.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_toolbar.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show CharacterCardGrid, FolderDialogAction, SearchScope;

import '../../../golden/support/fakes.dart';

void main() {
  late AppDatabase db;
  late FolderService folders;
  final cards = [
    for (final name in ['Porch Alpha', 'Porch Beta', 'Porch Delta'])
      CharacterCard(
        name: name,
        imagePath: '/library/${name.replaceAll(' ', '_')}.png',
      ),
  ];

  setUp(() async {
    db = AppDatabase.forTesting(sameIsolate: true);
    for (final c in cards) {
      await db.insertCharacterReturningId(
        CharactersCompanion(name: Value(c.name), imagePath: Value(c.imagePath)),
      );
    }
    folders = FolderService(db);
    final cedar = await folders.createFolder('Cedar');
    await folders.addToFolder(cedar.id, '/library/Porch_Delta.png');
    await folders.reload();
  });

  tearDown(() async {
    folders.dispose();
    await db.close();
  });

  Future<void> pumpGrid(
    WidgetTester tester, {
    required Set<String> selected,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeCharacterRepository(cards);
    addTearDown(repo.dispose);
    final groups = FakeGroupChatRepository();
    addTearDown(groups.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<CharacterRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: CharacterCardGrid(
              // "Top level only" + a search: Porch Delta sits in Cedar.
              searchQuery: 'porch',
              searchScope: SearchScope.currentFolder,
              activeFolderId: null,
              sortMode: 'name',
              lastActivityCache: const {},
              messageCountCache: const {},
              gridScale: 200,
              isSelecting: true,
              isOrganizing: false,
              selectedCharacterIds: selected,
              selectedGroupIds: const {},
              searchController: TextEditingController(text: 'porch'),
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

  testWidgets('a pick the search hides is counted as hidden, not lost', (
    tester,
  ) async {
    await pumpGrid(tester, selected: {'Porch_Alpha', 'Porch_Delta'});
    // Header ("2 selected" with a smaller "(1 hidden)") and bottom bar.
    expect(find.text('2 selected (1 hidden)'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(HomeGridToolbar),
        matching: find.text('2 selected (1 hidden)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('nothing hidden, nothing said', (tester) async {
    await pumpGrid(tester, selected: {'Porch_Alpha'});
    expect(find.textContaining('hidden'), findsNothing);
    expect(find.text('1 selected'), findsNWidgets(2));
  });
}
