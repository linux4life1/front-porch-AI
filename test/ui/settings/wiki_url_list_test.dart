// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life wiki library: Save adds, remove drops, unsafe URLs stay out.
//
// Guard proven red: Save wrote wiki_base_url only (no list).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

import '../../golden/support/fakes_storage.dart';

class _WikiStorage extends FakeStorageService {
  _WikiStorage() {
    webSearchSettings.initializeBase(null, notifyListeners);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Save adds a host; remove deletes it', (tester) async {
    final storage = _WikiStorage();
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(home: Scaffold(body: WikiUrlList())),
      ),
    );

    await tester.enterText(
      find.byType(TextField),
      'https://bleach.fandom.com/wiki/Aizen',
    );
    await tester.tap(find.text('Save wiki'));
    await tester.pump();
    expect(storage.webSearchSettings.savedWikiUrls, [
      'https://bleach.fandom.com',
    ]);
    expect(find.text('bleach.fandom.com'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('wiki-saved-remove-bleach.fandom.com')),
    );
    await tester.pump();
    expect(storage.webSearchSettings.savedWikiUrls, isEmpty);
  });

  testWidgets('unsafe URL is not saved', (tester) async {
    final storage = _WikiStorage();
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(home: Scaffold(body: WikiUrlList())),
      ),
    );
    await tester.enterText(find.byType(TextField), 'javascript:alert(1)');
    await tester.tap(find.text('Save wiki'));
    await tester.pump();
    expect(storage.webSearchSettings.savedWikiUrls, isEmpty);
    expect(find.text('That is not a MediaWiki / Fandom URL.'), findsOneWidget);
  });
}
