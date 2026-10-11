// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tapping the real home grid opens chats the way a user sees it:
//  - the chat screen is up while the chat is still loading (awaiting the
//    load before the push froze the grid) — 1:1, group and Start New Chat;
//  - a character with several saved chats asks which one (the picker is
//    keyed by the portrait basename; the database UUID found nothing);
//  - a load that fails takes the chat screen back down and says so.
// Proven red by awaiting the load before the push, passing `character.dbId`
// to getSessionsForId, and dropping the pop / snack in _pushChatWhile.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

import 'home_page_harness.dart';

Future<void> _session(AppDatabase db, String charId, String id, String name) =>
    db.insertSession(
      SessionsCompanion.insert(
        id: id,
        characterId: Value(charId),
        name: Value(name),
      ),
    );

void main() {
  late HomeRig rig;

  Future<void> open(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Lets the chat's real file and database work finish.
  Future<void> finishLoad(WidgetTester tester) async {
    for (var i = 0; i < 300 && rig.chat.isLoadingSession; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  void expectChatUpWhileLoading(String what) {
    expect(
      find.byType(ChatPage),
      findsOneWidget,
      reason: '$what must push the chat screen before the load finishes',
    );
    expect(
      rig.chat.isLoadingSession,
      isTrue,
      reason: 'the load is still running under the chat screen overlay',
    );
  }

  testWidgets('a card tap opens the chat screen first, then loads the chat', (
    tester,
  ) async {
    rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    await rig.pump(tester);

    await open(tester, 'Ada');
    expectChatUpWhileLoading('a card tap');

    await finishLoad(tester);
    expect(rig.chat.isLoadingSession, isFalse);
    expect(rig.chat.activeCharacter?.name, 'Ada');
    expect(find.byType(ChatPage), findsOneWidget);
  });

  testWidgets('a group tap opens the chat screen first, then loads the cast', (
    tester,
  ) async {
    rig = await HomeRig.build(
      tester,
      seed: (db) async {
        await seedCharacter(db, 'Ada', 'Ada.png');
        await db.insertGroup(
          GroupsCompanion.insert(id: 'crew', name: 'Porch Crew'),
        );
      },
    );
    await rig.pump(tester);

    await open(tester, 'Porch Crew');
    expectChatUpWhileLoading('a group tap');

    await finishLoad(tester);
    expect(rig.chat.activeGroup?.name, 'Porch Crew');
  });

  testWidgets('Start New Chat opens the chat screen first, then the new chat', (
    tester,
  ) async {
    rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    await rig.pump(tester);

    await tester.tap(find.text('Ada').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start New Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Start a new chat with Ada as…'), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectChatUpWhileLoading('Start New Chat');

    await finishLoad(tester);
    expect(rig.chat.activeCharacter?.name, 'Ada');
    expect(rig.chat.currentSessionId, isNotNull);
  });

  testWidgets('a character with two saved chats asks which one to open', (
    tester,
  ) async {
    rig = await HomeRig.build(
      tester,
      seed: (db) async {
        final id = await seedCharacter(db, 'Bo', 'Bo.png');
        await _session(db, id, '1700000000000', 'Porch at dusk');
        await _session(db, id, '1700000500000', 'Rainy morning');
      },
    );
    await rig.pump(tester);

    await open(tester, 'Bo');
    expect(
      find.text('Continue a chat with Bo?'),
      findsOneWidget,
      reason: 'two saved chats must open the picker',
    );
    expect(find.byType(ChatPage), findsNothing);

    await tester.tap(find.text('Porch at dusk'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectChatUpWhileLoading('a picked chat');

    await finishLoad(tester);
    expect(rig.chat.currentSessionId, '1700000000000');
  });

  testWidgets('a chat that fails to load closes the screen and says so', (
    tester,
  ) async {
    rig = await HomeRig.build(
      tester,
      seed: (db) async {
        final id = await seedCharacter(db, 'Cy', 'Cy.png');
        // A damaged row: the stored timestamp is not a date.
        await db.customStatement(
          'INSERT INTO sessions (id, character_id, updated_at) '
          "VALUES ('1700000000000', '$id', 'not a date')",
        );
      },
    );
    await rig.pump(tester);

    await open(tester, 'Cy');
    expectChatUpWhileLoading('a card tap');

    await finishLoad(tester);
    await tester.pumpAndSettle();
    expect(
      find.byType(ChatPage),
      findsNothing,
      reason: 'a failed load must not leave a half-loaded chat screen up',
    );
    expect(find.textContaining('Could not open chat'), findsOneWidget);
    expect(find.text('Cy'), findsWidgets, reason: 'back on the library');
  });
}
