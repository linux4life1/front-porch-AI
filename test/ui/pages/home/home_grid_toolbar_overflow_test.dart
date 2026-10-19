// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The home toolbar is a single Row of toggle + sort + slider + five actions.
// There is no fixed window size; a ~650px content strip (sidebar still open)
// overflowed that Row by 73px. This pumps the real toolbar at the reported
// width, a wide window, and a very narrow one, and fails on any RenderFlex
// overflow. Actions stay reachable (inline or via the overflow menu).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_toolbar.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/home_mode_toggle.dart';
import 'package:front_porch_ai/ui/pages/home/widgets/toolbar/toolbar.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show FolderDialogAction;

import '../../../golden/support/fakes.dart';

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required double width,
  required CharacterRepository repo,
  required FolderService folders,
  String? activeFolderId,
  bool isSelecting = false,
}) {
  tester.view.physicalSize = Size(width, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: HomeGridToolbar(
            isSelecting: isSelecting,
            isOrganizing: false,
            activeFolderId: activeFolderId,
            selectedCount: isSelecting ? 2 : 0,
            sortMode: 'name',
            gridScale: 240,
            modeToggle: HomeModeToggle(
              showStories: false,
              onShowChats: () {},
              onShowStories: () {},
            ),
            repo: repo,
            folderService: folders,
            onCancelSelection: () {},
            onFolderNavigateBack: () {},
            onFolderJump: (_) {},
            onSortChanged: (_) {},
            onGridScaleChanged: (_) {},
            onGridScaleChangeEnd: (_) {},
            onToggleSelectMode: () {},
            onToggleOrganizeMode: () {},
            onFolderDialogAction: (FolderDialogAction _, {folder, parentId}) {},
            onImport: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  late FakeCharacterRepository repo;
  late FakeFolderService folders;

  setUp(() {
    repo = FakeCharacterRepository();
    folders = FakeFolderService();
  });

  tearDown(() {
    repo.dispose();
    folders.dispose();
  });

  // 651 content width → 603 after the toolbar's 24px padding. That is the
  // field report. 1000 is the home golden surface. 360 is a squeezed window.
  for (final width in [1000.0, 651.0, 360.0]) {
    testWidgets('no overflow at content width $width', (tester) async {
      await _pumpToolbar(tester, width: width, repo: repo, folders: folders);
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeGridToolbar), findsOneWidget);
    });
  }

  testWidgets('wide window keeps the slider and inline refresh', (
    tester,
  ) async {
    await _pumpToolbar(tester, width: 1000, repo: repo, folders: folders);
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsOneWidget);
    expect(
      find.byTooltip(
        'Refresh character list (pick up external changes, e.g. Character Card Forge)',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('More library actions'), findsNothing);
  });

  testWidgets('reported 651px width stays overflow-free and keeps refresh', (
    tester,
  ) async {
    await _pumpToolbar(tester, width: 651, repo: repo, folders: folders);
    expect(tester.takeException(), isNull);
    expect(
      find.byTooltip(
        'Refresh character list (pick up external changes, e.g. Character Card Forge)',
      ),
      findsOneWidget,
    );
  });

  testWidgets('narrow window folds actions into a reachable overflow menu', (
    tester,
  ) async {
    await _pumpToolbar(tester, width: 360, repo: repo, folders: folders);
    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('More library actions'), findsOneWidget);

    await tester.tap(find.byTooltip('More library actions'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh list'), findsOneWidget);
    expect(find.text('Import Cards'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder breadcrumb does not overflow when squeezed', (
    tester,
  ) async {
    final nested = _Folders([
      CharacterFolder(id: 'a', name: 'Summer porch parties'),
      CharacterFolder(id: 'b', name: 'Guests who overstayed', parentId: 'a'),
    ]);
    addTearDown(nested.dispose);
    await _pumpToolbar(
      tester,
      width: 360,
      repo: repo,
      folders: nested,
      activeFolderId: 'b',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('My Characters'), findsOneWidget);
  });

  testWidgets('squeezed breadcrumb ellipsizes the parent, never clips its '
      'head under the back arrow', (tester) async {
    final nested = _Folders([
      CharacterFolder(id: 'a', name: 'Bletchfield of the long valley road'),
    ]);
    addTearDown(nested.dispose);
    await _pumpToolbar(
      tester,
      width: 360,
      repo: repo,
      folders: nested,
      activeFolderId: 'a',
    );
    expect(tester.takeException(), isNull);
    final back = tester.getRect(find.byTooltip('Up one level'));
    final root = tester.getRect(find.text('My Characters'));
    final current = tester.getRect(
      find.text('Bletchfield of the long valley road'),
    );
    expect(root.left, greaterThanOrEqualTo(back.right));
    expect(current.left, greaterThan(root.right));
  });

  for (final width in [900.0, 700.0, 600.0, 360.0]) {
    testWidgets('two levels deep at $width, the parent crumbs stay readable', (
      tester,
    ) async {
      final nested = _Folders([
        CharacterFolder(id: 'a', name: 'Bletchfield of the long valley road'),
        CharacterFolder(
          id: 'b',
          name: 'Hollow porch steps under the elm',
          parentId: 'a',
        ),
      ]);
      addTearDown(nested.dispose);
      await _pumpToolbar(
        tester,
        width: width,
        repo: repo,
        folders: nested,
        activeFolderId: 'b',
      );
      expect(tester.takeException(), isNull);
      for (final label in [
        'My Characters',
        'Bletchfield of the long valley road',
      ]) {
        expect(
          tester.getSize(find.text(label)).width,
          greaterThanOrEqualTo(20),
          reason: '"$label" collapsed at $width px',
        );
      }
    });
  }

  testWidgets('a deep path folds the middle into "…", which jumps to the '
      'deepest hidden level', (tester) async {
    String? jumped = 'unset';
    final folders = [
      CharacterFolder(id: 'a', name: 'Porch'),
      CharacterFolder(id: 'b', name: 'Steps', parentId: 'a'),
      CharacterFolder(id: 'c', name: 'Elm', parentId: 'b'),
      CharacterFolder(id: 'd', name: 'Swing', parentId: 'c'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: HomeToolbarBreadcrumb(
              activeFolderId: 'd',
              folders: folders,
              onFolderJump: (id) => jumped = id,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Porch'), findsNothing);
    expect(find.text('Steps'), findsNothing);
    expect(find.text('Elm'), findsOneWidget);
    expect(find.text('Swing'), findsOneWidget);
    await tester.tap(find.text('…'));
    expect(jumped, 'b');
  });
}

class _Folders extends FakeFolderService {
  _Folders(this._folders);
  final List<CharacterFolder> _folders;
  @override
  List<CharacterFolder> get folders => _folders;
}
