// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Timeline-integrity invalidation (smoke-test bug 2026-07-21): regenerating,
// swiping, editing, or deleting a message must remove journal cards that
// cite the rewritten region — otherwise the diary remembers events that
// never happened.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';

void main() {
  late AppDatabase db;
  late JournalStore store;
  const sid = 's1';

  setUp(() {
    db = AppDatabase.forTesting();
    store = JournalStore(getDb: () => db);
  });
  tearDown(() async => db.close());

  Future<void> card({
    required String owner,
    required String content,
    List<int>? positions,
    bool pinned = false,
  }) => db.insertJournalCard(
    JournalMemoriesCompanion(
      sessionId: const Value(sid),
      characterId: Value(owner),
      content: Value(content),
      category: const Value('moment'),
      pinned: Value(pinned),
      sourceMessageIds: Value(
        positions == null ? null : jsonEncode(positions),
      ),
    ),
  );

  Future<List<String>> contentsFor(String owner) async => [
    for (final c in await store.cardsFor(sid, owner)) c.content,
  ];

  test('cards citing at/after the rewrite point die; earlier ones survive',
      () async {
    await card(owner: 'a', content: 'early', positions: [2, 4]);
    await card(owner: 'a', content: 'straddles', positions: [4, 10]);
    await card(owner: 'a', content: 'late', positions: [12]);
    final removed = await store.invalidateCardsCitingFrom(sid, 10);
    expect(removed, 2);
    expect(await contentsFor('a'), ['early']);
  });

  test('pins cannot keep a phantom alive', () async {
    await card(owner: 'a', content: 'pinned phantom', positions: [8], pinned: true);
    expect(await store.invalidateCardsCitingFrom(sid, 5), 1);
    expect(await contentsFor('a'), isEmpty);
  });

  test('receipt-less cards (plants/dreams/ambitions) are never touched',
      () async {
    await card(owner: 'a', content: 'manual plant');
    expect(await store.invalidateCardsCitingFrom(sid, 0), 0);
    expect(await contentsFor('a'), ['manual plant']);
  });

  test('sweep covers every diary owner, including departed ones', () async {
    await card(owner: 'a', content: 'a-cites', positions: [7]);
    await card(owner: 'departed-member', content: 'b-cites', positions: [7]);
    await card(owner: 'departed-member', content: 'b-early', positions: [1]);
    expect(await store.invalidateCardsCitingFrom(sid, 6), 2);
    expect(await contentsFor('a'), isEmpty);
    expect(await contentsFor('departed-member'), ['b-early']);
  });

  test('corrupt receipts JSON is skipped, not fatal', () async {
    await db.insertJournalCard(
      const JournalMemoriesCompanion(
        sessionId: Value(sid),
        characterId: Value('a'),
        content: Value('corrupt'),
        category: Value('moment'),
        sourceMessageIds: Value('not-json'),
      ),
    );
    await card(owner: 'a', content: 'citing', positions: [9]);
    expect(await store.invalidateCardsCitingFrom(sid, 0), 1);
    expect(await contentsFor('a'), ['corrupt']);
  });
}
