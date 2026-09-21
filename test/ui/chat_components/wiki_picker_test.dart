// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chat sidebar wiki picker sets this chat's URL (or none).
//
// Guard proven red: tap did not call setWikiBaseUrl.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/wiki_panel.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _PickChat extends FakeChatService {
  String url = '';

  @override
  String get wikiBaseUrl => url;

  @override
  Future<void> setWikiBaseUrl(String next) async {
    url = next;
  }
}

class _WikiStorage extends FakeStorageService {
  _WikiStorage() {
    webSearchSettings.initializeBase(null, notifyListeners);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hidden when nothing is saved and this chat has no URL', (
    tester,
  ) async {
    final storage = _WikiStorage();
    final chat = _PickChat();
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
        child: MaterialApp(
          home: Scaffold(
            body: WikiPanel(chatService: chat, initiallyExpanded: true),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('wiki-picker')), findsNothing);
  });

  testWidgets('tap sets this chat wiki; none clears it', (tester) async {
    final storage = _WikiStorage();
    final chat = _PickChat();
    addTearDown(() {
      storage.dispose();
      chat.dispose();
    });
    await storage.webSearchSettings.addSavedWikiUrl(
      'https://bleach.fandom.com/',
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: WikiPanel(chatService: chat, initiallyExpanded: true),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('wiki-picker')), findsOneWidget);
    expect(
      find.text('Looks up this wiki only (MediaWiki / Fandom). Not Google.'),
      findsOneWidget,
    );

    await tester.tap(find.text('bleach.fandom.com'));
    await tester.pump();
    expect(chat.wikiBaseUrl, 'https://bleach.fandom.com');

    await tester.tap(find.text('None (off for this chat)'));
    await tester.pump();
    expect(chat.wikiBaseUrl, isEmpty);
  });
}
