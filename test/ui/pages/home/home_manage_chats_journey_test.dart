// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Right-click a card on the real Home grid → Manage Chats → Start New Chat
// goes through the persona step, then opens the new chat — on a character
// with no saved chat yet. Proven red by passing `onNewChat: () async {}`
// from home_page_history.dart.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/services.dart';

import 'home_page_harness.dart';

void main() {
  testWidgets('Manage Chats → Start New Chat asks for a persona, then opens '
      'the new chat', (tester) async {
    final rig = await HomeRig.build(
      tester,
      seed: (db) => seedCharacter(db, 'Ada', 'Ada.png'),
    );
    await rig.pump(tester);

    await tester.tap(find.text('Ada').first, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage Chats'));
    for (
      var i = 0;
      i < 20 && find.byType(AlertDialog).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final manage = find.byType(AlertDialog);
    expect(
      find.descendant(of: manage, matching: find.text('Manage Chats')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: manage, matching: find.text('Start New Chat')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start a new chat with Ada as…'), findsOneWidget);

    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 300 && rig.chat.isLoadingSession; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.chat.activeCharacter?.name, 'Ada');
    expect(rig.chat.currentSessionId, isNotNull);
  });
}
