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

// Two-tier memory (living-time-features.md §8) — the wedding-vows scenario:
// in a long chat, "remember our wedding vows?" makes the character recall
// the VERBATIM vows (via the card's receipts) plus how it felt (the card).

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/journal_injection.dart';
import 'package:front_porch_ai/services/memory_service.dart';

void main() {
  late AppDatabase db;
  late JournalStore store;
  const sid = 's1';
  const cid = 'mara';

  // Deterministic keyword embedder: wedding-ish text → one axis, the rest →
  // another, so cosine similarity is 1.0 or 0.0 exactly.
  Future<List<double>?> fakeEmbed(String text) async {
    final t = text.toLowerCase();
    return (t.contains('vow') || t.contains('wedding'))
        ? [1.0, 0.0, 0.0]
        : [0.0, 1.0, 0.0];
  }

  // A long chat whose vows live at positions 10–11, far behind the window.
  final messages = [
    for (var i = 0; i < 60; i++)
      ChatMessage(text: 'filler line $i', sender: 'Sam', isUser: true),
  ];
  messages[10] = ChatMessage(
    text: 'I vow to choose you every morning, in storm and in calm.',
    sender: 'Sam',
    isUser: true,
  );
  messages[11] = ChatMessage(
    text: 'And I vow to be your harbor, whatever the sea brings us.',
    sender: 'Mara',
    isUser: false,
  );

  JournalInjection injection() => JournalInjection(
    store: store,
    getSessionId: () => sid,
    getCurrentEmotion: () => '',
    getCurrentStoryDay: () => 12,
    getStoryStartDate: () => DateTime(2026, 1, 1),
    getMessageAt: (p) => p >= 0 && p < messages.length ? messages[p] : null,
  );

  Future<void> plantWeddingCard({List<int> positions = const [10, 11]}) async {
    await db.insertJournalCard(
      JournalMemoriesCompanion(
        sessionId: const Value(sid),
        characterId: const Value(cid),
        content: const Value(
          'We said our wedding vows at the lighthouse. I have never felt '
          'so sure of anything.',
        ),
        category: const Value('about_us'),
        emotionLabel: const Value('joyful'),
        emotionIntensity: const Value('strong'),
        sourceMessageIds: Value(jsonEncode(positions)),
      ),
    );
    await store.embedMissing(sid, cid);
  }

  setUp(() {
    db = AppDatabase.forTesting();
    store = JournalStore(getDb: () => db, embedText: fakeEmbed);
  });
  tearDown(() async => db.close());

  test('the wedding-vows scenario: verbatim recall + the feeling', () async {
    await plantWeddingCard();
    final result = await injection().buildJournalBlock(
      characterId: cid,
      characterName: 'Mara',
      userName: 'Sam',
      queryText: 'Sam: you remember when we had our wedding vows here?',
      lastWords: 'Sam: you remember when we had our wedding vows here?',
      messageCount: messages.length,
    );
    // The feeling (the card) is present…
    expect(result.text, contains('never felt so sure'));
    // …and so are the EXACT words, attributed.
    expect(result.text, contains('exact words'));
    expect(result.text, contains('choose you every morning'));
    expect(result.text, contains('be your harbor'));
    expect(result.text, contains('«Sam:'));
    expect(result.text, contains('«Mara:'));
    expect(result.expandedPositions, {10, 11});
  });

  test('an unrelated query injects the card but never the verbatim', () async {
    await plantWeddingCard();
    final result = await injection().buildJournalBlock(
      characterId: cid,
      characterName: 'Mara',
      userName: 'Sam',
      queryText: 'Sam: what should we cook tonight?',
      messageCount: messages.length,
    );
    expect(result.text, contains('never felt so sure'));
    expect(result.text, isNot(contains('choose you every morning')));
    expect(result.expandedPositions, isEmpty);
  });

  test('age gate: receipts still near the transcript do not expand', () async {
    await plantWeddingCard(positions: const [55]);
    final result = await injection().buildJournalBlock(
      characterId: cid,
      characterName: 'Mara',
      userName: 'Sam',
      queryText: 'Sam: remember our wedding vows?',
      lastWords: 'Sam: remember our wedding vows?',
      messageCount: messages.length,
    );
    expect(result.expandedPositions, isEmpty);
  });

  test('no-embedder floor: block renders, expansion silently absent', () async {
    store = JournalStore(getDb: () => db); // no embedText
    await db.insertJournalCard(
      JournalMemoriesCompanion(
        sessionId: const Value(sid),
        characterId: const Value(cid),
        content: const Value('a hot memory'),
        category: const Value('moment'),
        sourceMessageIds: Value(jsonEncode(const [10])),
      ),
    );
    final result = await injection().buildJournalBlock(
      characterId: cid,
      characterName: 'Mara',
      userName: 'Sam',
      queryText: 'Sam: remember?',
      lastWords: 'Sam: remember?',
      messageCount: messages.length,
    );
    expect(result.text, contains('a hot memory'));
    expect(result.expandedPositions, isEmpty);
  });

  test('RAG dedupe drops spans the journal already expanded', () {
    const mems = [
      RetrievedMemory(
        content: 'the vows passage',
        sessionId: sid,
        positionStart: 9,
        positionEnd: 12,
        score: 0.9,
      ),
      RetrievedMemory(
        content: 'an unrelated passage',
        sessionId: sid,
        positionStart: 30,
        positionEnd: 33,
        score: 0.8,
      ),
      RetrievedMemory(
        content: 'cross-session source (different position space)',
        sessionId: 'other-session',
        positionStart: 10,
        positionEnd: 11,
        score: 0.7,
      ),
    ];
    final kept = RetrievedMemory.excludingPositions(mems, {
      10,
      11,
    }, currentSessionId: sid);
    expect(kept.map((m) => m.content), [
      'an unrelated passage',
      'cross-session source (different position space)',
    ]);
    expect(
      RetrievedMemory.excludingPositions(mems, {}, currentSessionId: sid),
      hasLength(3),
    );
  });
}
