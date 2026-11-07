// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The composer draft router: where a half-typed message lives while the
// user is away, and who is allowed to read it back.
//
// Red proofs (each mutation run before the case was written):
//  * routing inverted (prefs for row-backed, DB for new) — cases
//    "a saved chat's draft rides the session row" and "a never-sent
//    new chat's draft rides prefs by owner" go red;
//  * empty-save only clearing the DB — "the clear empties BOTH homes"
//    and the materialization-race case go red;
//  * load falling back to prefs for a row-backed session — "a row-backed
//    chat with no draft does NOT borrow the owner mailbox" goes red.

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/composer_draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late ComposerDraftStore store;
  late SharedPreferences prefs;

  const owner = 'composer_draft.nina.png';

  Future<void> insertSession(String id) => db
      .into(db.sessions)
      .insert(
        SessionsCompanion.insert(id: id, characterId: const Value('nina')),
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    store = ComposerDraftStore(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
  });

  test("a saved chat's draft rides the session row, not prefs", () async {
    await insertSession('1000');
    await store.saveDraft(
      sessionId: '1000',
      ownerKey: owner,
      fresh: false,
      text: 'hey —',
    );
    expect(await db.getComposerDraft('1000'), 'hey —');
    expect(prefs.getString(owner), isNull);
    expect(
      await store.loadDraft(sessionId: '1000', ownerKey: owner, fresh: false),
      'hey —',
    );
  });

  test("a never-sent new chat's draft rides prefs by owner", () async {
    // No user message yet: fresh, whatever the row's state.
    await store.saveDraft(
      sessionId: '2000',
      ownerKey: owner,
      fresh: true,
      text: 'still typing…',
    );
    expect(prefs.getString(owner), 'still typing…');
    expect(await db.getComposerDraft('2000'), isNull);
    expect(
      await store.loadDraft(sessionId: '2000', ownerKey: owner, fresh: true),
      'still typing…',
    );
  });

  test('a fresh chat WITH a row still rides the mailbox — the greeting '
      'save must not strand a new chat\u2019s draft', () async {
    // Desktop reality: opening a card materializes the row (the
    // greeting is a message), but the chat is still fresh until the
    // user speaks. Its draft must go where the NEXT new chat looks.
    await insertSession('2500');
    await store.saveDraft(
      sessionId: '2500',
      ownerKey: owner,
      fresh: true,
      text: 'half-written on a materialized chat',
    );
    expect(prefs.getString(owner), 'half-written on a materialized chat');
    expect(await db.getComposerDraft('2500'), isNull);
    expect(
      await store.loadDraft(sessionId: '2500', ownerKey: owner, fresh: true),
      'half-written on a materialized chat',
    );
  });

  test(
    'the clear empties BOTH homes — no ghost for the next new chat',
    () async {
      // The materialization race: the draft rode prefs, the send wrote the
      // row underneath the clear, and the save of '' lands on the NEW row.
      await store.saveDraft(
        sessionId: '3000',
        ownerKey: owner,
        fresh: true,
        text: 'sent!',
      );
      await insertSession('3000');
      await store.saveDraft(
        sessionId: '3000',
        ownerKey: owner,
        fresh: false,
        text: '',
      );
      expect(await db.getComposerDraft('3000'), isNull);
      expect(prefs.getString(owner), isNull);
    },
  );

  test('drafts do not cross sessions', () async {
    await insertSession('4000');
    await insertSession('4001');
    await store.saveDraft(
      sessionId: '4000',
      ownerKey: owner,
      fresh: false,
      text: 'for A',
    );
    expect(
      await store.loadDraft(sessionId: '4001', ownerKey: owner, fresh: false),
      '',
    );
  });

  test(
    'a row-backed chat with no draft does NOT borrow the owner mailbox',
    () async {
      await prefs.setString(owner, 'leftover from a new chat');
      await insertSession('5000');
      expect(
        await store.loadDraft(sessionId: '5000', ownerKey: owner, fresh: false),
        '',
      );
      // The mailbox survives for the new-chat door: a fresh read
      // still finds it.
      expect(
        await store.loadDraft(sessionId: '6000', ownerKey: owner, fresh: true),
        'leftover from a new chat',
      );
    },
  );

  test("deleting the chat deletes its draft with it", () async {
    await insertSession('7000');
    await store.saveDraft(
      sessionId: '7000',
      ownerKey: owner,
      fresh: false,
      text: 'gone',
    );
    await (db.delete(db.sessions)..where((s) => s.id.equals('7000'))).go();
    expect(
      await store.loadDraft(sessionId: '7000', ownerKey: owner, fresh: false),
      '',
    );
  });

  test('the no-chat send clears the mailbox without a session id', () async {
    await prefs.setString(owner, 'pending new-chat line');
    await store.saveDraft(
      sessionId: null,
      ownerKey: owner,
      fresh: true,
      text: '',
    );
    expect(prefs.getString(owner), isNull);
  });

  test("owner keys match the app's identity scheme", () {
    expect(
      composerDraftOwnerForCharacter('nina.png'),
      'composer_draft.nina.png',
    );
    expect(composerDraftOwnerForGroup('abc123'), 'composer_draft.group_abc123');
  });
}
