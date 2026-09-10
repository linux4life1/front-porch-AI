// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit Character → Dialogue → Add on a card with no alts. Stack was
// UnmodifiableListMixin.add at _altGreetingSeeds.add(null) because
// alignGreetingSeeds returned const [].

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/pages.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _RepoWithCover extends FakeCharacterRepository {
  @override
  File? coverImageFileFor(CharacterCard card) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Dialogue Add greeting works on a card with no alternate greetings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _RepoWithCover();
      final chat = FakeChatService();
      final storage = FakeStorageService();
      final worlds = FakeWorldRepository();
      addTearDown(repo.dispose);
      addTearDown(chat.dispose);
      addTearDown(storage.dispose);
      addTearDown(worlds.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CharacterRepository>.value(value: repo),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<WorldRepository>.value(value: worlds),
          ],
          child: MaterialApp(
            home: EditCharacterPage(
              character: CharacterCard(
                name: 'Seam Probe',
                firstMessage: 'Every tab, every tap.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dialogue'));
      await tester.pumpAndSettle();

      expect(find.text('No alternate greetings yet'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Add must not hit UnmodifiableListMixin.add — '
            'alignGreetingSeeds(const [], 0) used to return const []',
      );
      expect(find.text('No alternate greetings yet'), findsNothing);
      expect(find.text('Greeting 2'), findsOneWidget);
    },
  );
}
