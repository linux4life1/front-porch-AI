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

// Widget pixel goldens for the library gestures (phases 2–3), captured
// mid-gesture so the transient states are pinned:
//   home/library_box        — a box being dragged over the grid
//   home/library_drag       — the picks dragged onto a folder tile (ghost,
//                             dimmed picks, "Drop to move 3 here")
//   home/library_drag_path  — inside a folder, the path levels as targets
// Light + dark. The whole app is captured so the drag ghost (an overlay) is
// in the picture.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/library_selection.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show CharacterCardGrid, FolderDialogAction, SearchScope;
import 'package:front_porch_ai/utils/utils.dart';

import '../support/fakes.dart';

const _root = Key('library-gestures-root');

final _cards = [
  for (final name in ['Ann', 'Bo', 'Cy', 'Dee', 'Eve', 'Fay'])
    CharacterCard(name: name, imagePath: '/library/$name.png'),
];

class _Folders extends FakeFolderService {
  _Folders(this._all, {this.inside = const {}});
  final List<CharacterFolder> _all;
  final Map<String, List<String>> inside;
  @override
  List<CharacterFolder> get folders => _all;
  @override
  List<CharacterFolder> getSubfolders(String? parentId) =>
      _all.where((f) => f.parentId == parentId).toList();
  @override
  List<String> getCharactersInFolder(String folderId) =>
      inside[folderId] ?? const [];
  @override
  List<String> groupIdsInFolder(String folderId) => const [];
}

class _Groups extends FakeGroupChatRepository {
  @override
  List<GroupChat> get groups => [GroupChat(id: 'group_crew', name: 'Crew')];
  @override
  Future<List<File>> getMemberAvatarFiles(String groupId) async => const [];
}

Widget _app(Brightness brightness, Widget child) => RepaintBoundary(
  key: _root,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: brightness,
      fontFamily: 'Roboto',
      useMaterial3: true,
    ),
    home: Scaffold(body: child),
  ),
);

Widget _grid(LibrarySelection sel, FolderService folders, {String? folderId}) {
  final repo = FakeCharacterRepository(_cards);
  return ChangeNotifierProvider<CharacterRepository>.value(
    value: repo,
    child: ListenableBuilder(
      listenable: sel,
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
        gridScrollController: ScrollController(),
        repo: repo,
        folderService: folders,
        groupRepo: _Groups(),
        modeToggle: const SizedBox.shrink(),
        onTapCharacter: (_) async {},
        onTapGroup: (_) async {},
        onToggleSelect: (c) => sel.toggle(c.stableGroupId, group: false),
        onToggleSelectGroup: (g) => sel.toggle(g.id, group: true),
        onContextMenuAction: (_, _) {},
        onImport: (_) {},
        onAcceptFolderDrop: (_, _) {},
        onFolderDialogAction: (FolderDialogAction _, {folder, parentId}) {},
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
        onDropOnLevel: (_, _) {},
      ),
    ),
  );
}

/// Pumps [build] in both themes, runs [act] to reach the mid-gesture state,
/// checks the golden, then lets go of the pointer.
Future<void> _goldens(
  WidgetTester tester,
  String name,
  Widget Function(LibrarySelection sel) build,
  Future<TestGesture> Function(WidgetTester tester, LibrarySelection sel) act,
) async {
  tester.view.physicalSize = const Size(1300, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  for (final brightness in Brightness.values) {
    final mode = brightness == Brightness.light ? 'light' : 'dark';
    final sel = LibrarySelection();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(brightness, build(sel)));
    await tester.pump();
    final gesture = await act(tester, sel);
    await expectLater(
      find.byKey(_root),
      matchesGoldenFile('_goldens/home/$name.$mode.png'),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    sel.dispose();
  }
}

Offset _at(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text).first);

Future<TestGesture> _mouse(WidgetTester tester, Offset at) => tester
    .startGesture(at, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);

void main() {
  final attic = CharacterFolder(id: 'attic', name: 'Attic');

  testWidgets('a box over the grid', (tester) async {
    await _goldens(
      tester,
      'library_box',
      (sel) => _grid(sel, _Folders([attic])),
      (tester, sel) async {
        final from = _at(tester, 'Bo') - const Offset(30, 60);
        final to = _at(tester, 'Dee') + const Offset(40, 80);
        final mouse = await _mouse(tester, from);
        for (var i = 1; i <= 4; i++) {
          await mouse.moveTo(Offset.lerp(from, to, i / 4)!);
          await tester.pump();
        }
        return mouse;
      },
    );
  });

  testWidgets('the picks dragged onto a folder tile', (tester) async {
    await _goldens(
      tester,
      'library_drag',
      (sel) => _grid(sel, _Folders([attic])),
      (tester, sel) async {
        sel.replace({'Ann', 'Bo'}, {'group_crew'});
        await tester.pump();
        final mouse = await _mouse(tester, _at(tester, 'Bo'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await mouse.moveTo(_at(tester, 'Attic'));
        await tester.pump();
        return mouse;
      },
    );
  });

  testWidgets('inside a folder, the path takes the drop', (tester) async {
    final outer = CharacterFolder(id: 'outer', name: 'Outer');
    final inner = CharacterFolder(
      id: 'inner',
      name: 'Inner',
      parentId: 'outer',
    );
    final folders = _Folders(
      [outer, inner],
      inside: {
        'inner': ['Ann.png', 'Bo.png', 'Cy.png'],
      },
    );
    await _goldens(
      tester,
      'library_drag_path',
      (sel) => _grid(sel, folders, folderId: 'inner'),
      (tester, sel) async {
        sel.replace({'Ann', 'Bo'}, const {});
        await tester.pump();
        final mouse = await _mouse(tester, _at(tester, 'Ann'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        // Over empty grid space, so every level of the path shows as a
        // target (a hovered level sits under the ghost).
        await mouse.moveTo(_at(tester, 'Cy') + const Offset(420, 60));
        await tester.pump();
        return mouse;
      },
    );
  });
}
