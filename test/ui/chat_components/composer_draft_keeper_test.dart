// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The composer draft keeper, end to end: type into the box, close the
// page, reopen the chat — the half-typed line is back. Covers the paths
// the store test cannot see: the controller wiring, the in-page session
// switch (the box must carry the line to the RIGHT chat's key, then
// take the new chat's draft in), and the debounced write.

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  const owner = 'composer_draft.nina.png';

  Future<void> insertSession(String id) => db
      .into(db.sessions)
      .insert(
        SessionsCompanion.insert(id: id, characterId: const Value('nina')),
      );

  setUp(() async {
    // sameIsolate: the default forTesting() runs drift on a background
    // isolate, and its futures never complete inside a fake-async
    // testWidgets zone — the keeper's load would hang the pump forever.
    db = AppDatabase.forTesting(sameIsolate: true);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    // Drain the keeper's last unawaited flush — its saveDraft is a pure
    // microtask chain on the sameIsolate database, and closing under it
    // races the final write ("Can't re-open a database after closing").
    await Future<void>.delayed(Duration.zero);
    await db.close();
  });

  Widget host(TextEditingController controller, String? sessionId) {
    return Provider<AppDatabase>.value(
      value: db,
      child: MaterialApp(
        home: Scaffold(
          body: ComposerDraftKeeper(
            sessionId: sessionId,
            draftOwner: owner,
            controller: controller,
            child: TextField(controller: controller),
          ),
        ),
      ),
    );
  }

  /// Fire the debounce, then drain the futures the save/load chains ride:
  /// even sameIsolate drift hands its result back over several microtask
  /// turns, and one pump is not all of them (the flake this prevents:
  /// the read answering before the write it waited for).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a half-typed line comes back after the page dies', (
    tester,
  ) async {
    await insertSession('1000');
    final controller = TextEditingController();

    // Open, type, and let the debounce write.
    await tester.pumpWidget(host(controller, '1000'));
    await tester.enterText(find.byType(TextField), 'half a thought');
    await settle(tester);
    expect(await db.getComposerDraft('1000'), 'half a thought');

    // Close the chat — the page, controller and keeper all die.
    await tester.pumpWidget(const SizedBox());

    // Reopen with a fresh controller on the same session.
    final reopened = TextEditingController();
    await tester.pumpWidget(host(reopened, '1000'));
    await settle(tester);
    expect(reopened.text, 'half a thought');
    // The dead box was never written back to — restore seeds the LIVE
    // box only.
    expect(controller.text, 'half a thought');
  });

  testWidgets('a send clears the draft so it cannot haunt the reopen', (
    tester,
  ) async {
    await insertSession('1100');
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller, '1100'));
    await tester.enterText(find.byType(TextField), 'sent line');
    await settle(tester);
    expect(await db.getComposerDraft('1100'), 'sent line');

    // sendComposerMessage clears the box; the write follows.
    controller.clear();
    await settle(tester);
    expect(await db.getComposerDraft('1100'), isNull);

    final reopened = TextEditingController();
    await tester.pumpWidget(host(reopened, '1100'));
    await settle(tester);
    expect(reopened.text, isEmpty);
  });

  testWidgets('an in-page switch files the old line and takes the new one', (
    tester,
  ) async {
    await insertSession('2000');
    await insertSession('2001');
    await db.setComposerDraft('2001', 'B was waiting');
    final controller = TextEditingController();
    await tester.pumpWidget(host(controller, '2000'));
    await tester.enterText(find.byType(TextField), 'A is typing');
    await settle(tester);

    // The session switcher loads another chat inside the live page.
    await tester.pumpWidget(host(controller, '2001'));
    await settle(tester);
    expect(controller.text, 'B was waiting');
    expect(await db.getComposerDraft('2000'), 'A is typing');

    // And back — A's line has been kept for A alone.
    await tester.pumpWidget(host(controller, '2000'));
    await settle(tester);
    expect(controller.text, 'A is typing');
  });

  testWidgets('a never-sent new chat rides the owner mailbox', (tester) async {
    final controller = TextEditingController();
    // '9999' has no row — the first message was never sent.
    await tester.pumpWidget(host(controller, '9999'));
    await tester.enterText(find.byType(TextField), 'a first hello');
    await settle(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(owner), 'a first hello');
    expect(await db.getComposerDraft('9999'), isNull);

    // A NEW new chat (different fresh id, same owner) gets it back.
    final reopened = TextEditingController();
    await tester.pumpWidget(host(reopened, '9998'));
    await settle(tester);
    expect(reopened.text, 'a first hello');
  });
}
