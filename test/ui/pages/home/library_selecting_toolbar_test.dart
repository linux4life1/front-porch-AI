// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The approved library sketch keeps the sort, the card size and the
// library actions on the right while picking cards, beside the selection
// header (close, "N selected (M hidden)", Select all / Select none). They
// used to vanish while picking. As the window narrows they fold away
// first — slider, sort label, inline actions — so the header never
// overflows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_toolbar.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart' show FolderDialogAction;

import '../../../golden/support/fakes.dart';

const _refresh =
    'Refresh character list (pick up external changes, e.g. Character Card Forge)';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = FakeCharacterRepository();
  addTearDown(repo.dispose);
  final folders = FakeFolderService();
  addTearDown(folders.dispose);
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
  for (final width in [1400.0, 1000.0, 800.0, 651.0, 520.0, 440.0, 360.0]) {
    testWidgets('picking at $width px: no overflow, the header stays whole', (
      tester,
    ) async {
      await _pump(tester, width);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextButton, 'Select all'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Select none'), findsOneWidget);
      expect(find.text('128 selected (37 hidden)'), findsOneWidget);
    });
  }

  testWidgets('a wide window keeps sort, card size and every action', (
    tester,
  ) async {
    await _pump(tester, 1400);
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byTooltip(_refresh), findsOneWidget);
    expect(find.byTooltip('Organize into folders'), findsOneWidget);
    expect(find.byTooltip('New Folder'), findsOneWidget);
  });

  testWidgets('a narrower one folds the actions into the overflow menu', (
    tester,
  ) async {
    await _pump(tester, 651);
    expect(find.byTooltip('More library actions'), findsOneWidget);
    expect(find.byTooltip(_refresh), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('a squeezed one shows only the header', (tester) async {
    await _pump(tester, 360);
    expect(find.byTooltip('More library actions'), findsNothing);
    expect(find.byTooltip('Cancel selection'), findsOneWidget);
  });
}
