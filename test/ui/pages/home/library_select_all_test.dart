// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #347: Select all / Select none in the selection header, Ctrl/Cmd+A and
// Esc on the grid. Select all takes exactly what the grid shows, so with a
// search only what it found, and with "Top level only" nothing from inside
// a folder. Ctrl+A belongs to the search box while it has focus.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_toolbar.dart';
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

class _Probe {
  final selectAll = <(Set<String>, Set<String>)>[];
  int selectNone = 0;
  int cancel = 0;
}

void main() {
  late AppDatabase db;
  late FolderService folders;
  final cards = [
    for (final name in [
      'Porch Alpha',
      'Porch Beta',
      'Quiet Gamma',
      'Porch Delta',
    ])
      CharacterCard(
        name: name,
        imagePath: '/library/${name.replaceAll(' ', '_')}.png',
      ),
  ];
  final crews = [
    GroupChat(id: 'group_porch', name: 'Porch Crew'),
    GroupChat(id: 'group_quiet', name: 'Quiet Crew'),
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

  Future<_Probe> pumpGrid(
    WidgetTester tester, {
    String query = 'porch',
    SearchScope scope = SearchScope.currentFolder,
    bool selecting = true,
    Set<String> selected = const {},
    Set<String> selectedGroups = const {},
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeCharacterRepository(cards);
    addTearDown(repo.dispose);
    final groups = _Groups(crews);
    addTearDown(groups.dispose);
    final probe = _Probe();
    await tester.pumpWidget(
      ChangeNotifierProvider<CharacterRepository>.value(
        value: repo,
        child: MaterialApp(
          home: Scaffold(
            body: CharacterCardGrid(
              searchQuery: query,
              searchScope: scope,
              activeFolderId: null,
              sortMode: 'name',
              lastActivityCache: const {},
              messageCountCache: const {},
              gridScale: 200,
              isSelecting: selecting,
              isOrganizing: false,
              selectedCharacterIds: selected,
              selectedGroupIds: selectedGroups,
              searchController: TextEditingController(text: query),
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
              onCancelSelection: () => probe.cancel++,
              onDeleteSelected: (_) {},
              onMoveToFolder: (_) {},
              onSortChanged: (_) {},
              onGridScaleChanged: (_) {},
              onSearchScopeChanged: (_) {},
              onSearchQueryChanged: (_) {},
              onResolveCharImage: (c) => File(c.imagePath ?? ''),
              onDeleteGroup: (_) {},
              onAfterNavigateBack: () {},
              onSelectAll: (chars, groups) =>
                  probe.selectAll.add((chars, groups)),
              onSelectNone: () => probe.selectNone++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return probe;
  }

  Finder button(String label) => find.widgetWithText(TextButton, label);

  testWidgets('Select all takes only what the search found, at this level', (
    tester,
  ) async {
    final probe = await pumpGrid(tester);
    await tester.tap(button('Select all'));
    await tester.pump();
    expect(probe.selectAll, hasLength(1));
    final (chars, groups) = probe.selectAll.single;
    // Quiet Gamma does not match; Porch Delta is inside Cedar.
    expect(chars, {'Porch_Alpha', 'Porch_Beta'});
    expect(groups, {'group_porch'});
  });

  testWidgets('Everywhere lets Select all reach into folders', (tester) async {
    final probe = await pumpGrid(tester, scope: SearchScope.allCharacters);
    await tester.tap(button('Select all'));
    await tester.pump();
    expect(probe.selectAll.single.$1, {
      'Porch_Alpha',
      'Porch_Beta',
      'Porch_Delta',
    });
  });

  testWidgets('Select none is greyed out at 0 and clears otherwise', (
    tester,
  ) async {
    await pumpGrid(tester);
    expect(tester.widget<TextButton>(button('Select none')).enabled, isFalse);

    final probe = await pumpGrid(tester, selected: {'Porch_Delta'});
    await tester.tap(button('Select none'));
    await tester.pump();
    expect(probe.selectNone, 1);
  });

  testWidgets('Select all is greyed out once everything shown is picked', (
    tester,
  ) async {
    await pumpGrid(tester, query: 'quiet', selected: {'Quiet_Gamma'});
    // Quiet Crew is still unpicked, so there is more to take.
    expect(tester.widget<TextButton>(button('Select all')).enabled, isTrue);

    await pumpGrid(
      tester,
      query: 'quiet',
      selected: {'Quiet_Gamma'},
      selectedGroups: {'group_quiet'},
    );
    expect(tester.widget<TextButton>(button('Select all')).enabled, isFalse);
  });

  testWidgets('Ctrl+A on the grid selects all; in the search box it does not', (
    tester,
  ) async {
    final probe = await pumpGrid(tester);

    // Typing in the search box: Ctrl+A is the text field's own select-all.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(probe.selectAll, isEmpty);

    // A click on the grid gives it the keyboard.
    await tester.tap(find.text('Porch Alpha'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(probe.selectAll, hasLength(1));
    expect(probe.selectAll.single.$1, {'Porch_Alpha', 'Porch_Beta'});

    // Cmd+A does the same (macOS).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(probe.selectAll, hasLength(2));
  });

  testWidgets('Esc on the grid clears the selection', (tester) async {
    final probe = await pumpGrid(tester, selected: {'Porch_Alpha'});
    await tester.tap(find.text('Porch Beta'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(probe.cancel, 1);
  });

  for (final width in [1000.0, 651.0, 360.0]) {
    testWidgets('the selection header fits at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeCharacterRepository();
      addTearDown(repo.dispose);
      final empty = FakeFolderService();
      addTearDown(empty.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: HomeGridToolbar(
                isSelecting: true,
                isOrganizing: false,
                activeFolderId: null,
                selectedCount: 128,
                hiddenSelectedCount: 37,
                selectionActions: LibrarySelectionActions(
                  selectAll: () {},
                  selectNone: () {},
                ),
                sortMode: 'name',
                gridScale: 240,
                modeToggle: const SizedBox.shrink(),
                repo: repo,
                folderService: empty,
                onCancelSelection: () {},
                onFolderNavigateBack: () {},
                onFolderJump: (_) {},
                onSortChanged: (_) {},
                onGridScaleChanged: (_) {},
                onGridScaleChangeEnd: (_) {},
                onToggleSelectMode: () {},
                onToggleOrganizeMode: () {},
                onFolderDialogAction:
                    (FolderDialogAction _, {folder, parentId}) {},
                onImport: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(button('Select all'), findsOneWidget);
      expect(button('Select none'), findsOneWidget);
    });
  }
}
