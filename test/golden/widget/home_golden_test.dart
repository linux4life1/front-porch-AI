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

@Tags(['golden'])
@TestOn('linux')
library;

// Widget pixel goldens for the home-screen character grid — the primary
// visible surface of home_page.dart. The full ~3400-line HomePage widget reads
// 10 providers and is too heavy to pump as a monolith, so we cover the reusable
// CharacterCardGrid component directly (it receives all data as constructor
// parameters and only reads StorageService + CharacterRepository via
// Provider.of in its async folder-preview helper, which never fires during a
// static golden).
//
// Two cases:
//   home_grid_empty  — no characters: shows the "empty library" prompt
//   home_grid_cards  — 3 seeded characters: shows the grid with name labels,
//                      tag chips, action buttons, and the grid header
//
// Both light + dark.  FakeCharacterRepository / FakeFolderService /
// FakeGroupChatRepository supply the three repo dependencies the widget holds.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show
        CharacterCardGrid,
        FolderDialogAction,
        SearchScope;

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

StorageService _storage() {
  SharedPreferences.setMockInitialValues({});
  return StorageService();
}

/// Build a [CharacterCardGrid] with all no-op callbacks — callers only need to
/// supply repo, folderService, groupRepo, and the character list.
Widget _grid({
  required FakeCharacterRepository repo,
  required FakeFolderService folderService,
  required FakeGroupChatRepository groupRepo,
  required StorageService storage,
}) {
  final searchController = TextEditingController();
  final scrollController = ScrollController();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<StorageService>.value(value: storage),
      // CharacterCardGrid's async _folderPreviewImages reads CharacterRepository
      // from the provider tree; supply the same fake.
      ChangeNotifierProvider<CharacterRepository>.value(value: repo),
    ],
    child: CharacterCardGrid(
      searchQuery: '',
      searchScope: SearchScope.allCharacters,
      activeFolderId: null,
      sortMode: 'name',
      lastActivityCache: const {},
      messageCountCache: const {},
      gridScale: 240,
      isSelecting: false,
      isOrganizing: false,
      selectedCharacterIds: const {},
      searchController: searchController,
      gridScrollController: scrollController,
      repo: repo,
      folderService: folderService,
      groupRepo: groupRepo,
      modeToggle: const SizedBox.shrink(),
      onTapCharacter: (_) async {},
      onTapGroup: (_) async {},
      onToggleSelect: (_) {},
      onContextMenuAction: (_, _) {},
      onImport: (_) {},
      onAcceptFolderDrop: (_, _) {},
      onFolderDialogAction: (FolderDialogAction _, {folder, parentId}) {},
      onFolderTap: (_) {},
      onFolderNavigateBack: () {},
      onCancelSelection: () {},
      onDeleteSelected: (_) {},
      onMoveToFolder: (_) {},
      onSortChanged: (_) {},
      onGridScaleChanged: (_) {},
      onSearchScopeChanged: (_) {},
      onSearchQueryChanged: (_) {},
      // No characters have imagePath set → this callback is never invoked.
      onResolveCharImage: (c) => File(c.imagePath ?? ''),
      onDeleteGroup: (_) {},
      onAfterNavigateBack: () {},
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('CharacterCardGrid — empty library', (tester) async {
    final repo = FakeCharacterRepository();
    addTearDown(repo.dispose);
    final folders = FakeFolderService();
    addTearDown(folders.dispose);
    final groups = FakeGroupChatRepository();
    addTearDown(groups.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: _grid(
        repo: repo,
        folderService: folders,
        groupRepo: groups,
        storage: storage,
      ),
      group: 'home',
      name: 'grid_empty',
      surface: const Size(1000, 700),
    );
  });

  testWidgets('CharacterCardGrid — 3 characters', (tester) async {
    final characters = [
      CharacterCard(
        name: 'Aria Vale',
        description: 'A lighthouse keeper on a wind-scoured cape.',
        tags: ['lighthouse', 'mystery'],
      ),
      CharacterCard(
        name: 'Dex Marlowe',
        description: 'A retired detective with sharp eyes and old debts.',
        tags: ['detective', 'noir'],
      ),
      CharacterCard(
        name: 'Lyra Sun',
        description: 'A cartographer who maps the unmappable.',
        tags: ['explorer'],
      ),
    ];
    final repo = FakeCharacterRepository(characters);
    addTearDown(repo.dispose);
    final folders = FakeFolderService();
    addTearDown(folders.dispose);
    final groups = FakeGroupChatRepository();
    addTearDown(groups.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: _grid(
        repo: repo,
        folderService: folders,
        groupRepo: groups,
        storage: storage,
      ),
      group: 'home',
      name: 'grid_cards',
      surface: const Size(1000, 700),
    );
  });
}
