// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wiki URL box is visible on Porch Life (and the chat-tools field widget).
// ensureVisible when the Porch Life list is stacked.
//
// Guard proven red: missing WikiUrlField / missing copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/porch_life_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _WikiStorage extends FakeStorageService {
  _WikiStorage() {
    _realism.initializeBase(null, notifyListeners);
    webSearchSettings.initializeBase(null, notifyListeners);
  }

  final RealismSettings _realism = RealismSettings();

  @override
  RealismSettings get realismSettings => _realism;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Porch Life shows the wiki URL box (ensureVisible)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = _WikiStorage();
    final chat = FakeChatService();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: const MaterialApp(home: Scaffold(body: PorchLifeTab())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final box = find.byKey(const Key('wiki-url-field'));
    await tester.scrollUntilVisible(
      box,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(box);
    expect(box, findsOneWidget);
    expect(
      find.text('Looks up this wiki only (MediaWiki / Fandom). Not Google.'),
      findsWidgets,
    );
  });

  testWidgets('chat-tools WikiUrlField is visible', (tester) async {
    final storage = _WikiStorage();
    addTearDown(storage.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WikiUrlField(storage: storage, fieldKey: 'wiki-url-tools'),
        ),
      ),
    );
    expect(find.byKey(const Key('wiki-url-tools')), findsOneWidget);
    expect(
      find.text('Looks up this wiki only (MediaWiki / Fandom). Not Google.'),
      findsOneWidget,
    );
  });
}
