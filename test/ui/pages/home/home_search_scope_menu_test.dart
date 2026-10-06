// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #346: the search-scope button only existed inside a folder, so at the top
// level — where imported cards land and the button is needed most — a
// search always covered every folder. The button now shows at every level;
// at the top it offers Everywhere and Top level only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/widgets/home_grid_search_bar.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart' show SearchScope;

void main() {
  Future<List<SearchScope>> pumpBar(
    WidgetTester tester, {
    String? folderId,
    SearchScope scope = SearchScope.allCharacters,
  }) async {
    final picked = <SearchScope>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeGridSearchBar(
            searchController: TextEditingController(),
            searchQuery: '',
            searchScope: scope,
            activeFolderId: folderId,
            onSearchScopeChanged: picked.add,
            onSearchQueryChanged: (_) {},
          ),
        ),
      ),
    );
    return picked;
  }

  testWidgets('the top level has a scope menu: Everywhere or Top level only', (
    tester,
  ) async {
    final picked = await pumpBar(tester);
    expect(find.byTooltip('Search scope'), findsOneWidget);

    await tester.tap(find.byTooltip('Search scope'));
    await tester.pumpAndSettle();
    expect(find.text('Everywhere'), findsOneWidget);
    expect(find.text('Top level only'), findsOneWidget);
    // Folder-only wording does not apply at the top level.
    expect(find.text('Folder & Subfolders'), findsNothing);

    await tester.tap(find.text('Top level only'));
    await tester.pumpAndSettle();
    expect(picked, [SearchScope.currentFolder]);
  });

  testWidgets('the top-level button wears the scope; the hint stays put', (
    tester,
  ) async {
    await pumpBar(tester);
    expect(find.text('Search by name or tag...'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await pumpBar(tester, scope: SearchScope.currentFolder);
    expect(find.text('Search by name or tag...'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
  });

  testWidgets('inside a folder the three choices stay as they were', (
    tester,
  ) async {
    final picked = await pumpBar(
      tester,
      folderId: 'f1',
      scope: SearchScope.currentFolder,
    );
    expect(find.text('Search this folder...'), findsOneWidget);
    await tester.tap(find.byTooltip('Search scope'));
    await tester.pumpAndSettle();
    expect(find.text('This Folder Only'), findsOneWidget);
    expect(find.text('Folder & Subfolders'), findsOneWidget);
    expect(find.text('Top level only'), findsNothing);
    await tester.tap(find.text('All Characters'));
    await tester.pumpAndSettle();
    expect(picked, [SearchScope.allCharacters]);
  });
}
