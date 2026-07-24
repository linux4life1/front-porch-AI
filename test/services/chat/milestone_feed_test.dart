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

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/milestone_feed.dart';

void main() {
  late AppDatabase db;
  late MilestoneFeed feed;
  const sid = 'session-1';
  const cid = 'char-1';

  setUp(() {
    db = AppDatabase.forTesting();
    feed = MilestoneFeed(getDb: () => db);
  });

  tearDown(() async => db.close());

  Future<void> addCard({
    required String content,
    bool pinned = false,
    String? intensity,
    String? kind,
    int? storyDay,
    List<int>? positions,
  }) => db.insertJournalCard(
    JournalMemoriesCompanion(
      sessionId: const Value(sid),
      characterId: const Value(cid),
      content: Value(content),
      category: const Value('moment'),
      pinned: Value(pinned),
      emotionIntensity: Value(intensity),
      sourceMessageIds: Value(
        positions == null ? null : jsonEncode(positions),
      ),
      metadata: Value(
        kind == null && storyDay == null
            ? null
            : jsonEncode({'storyDay': ?storyDay, 'kind': ?kind}),
      ),
    ),
  );

  test('salience filter: pinned, strong, and dreams pass; mild plain do not',
      () async {
    await addCard(content: 'pinned one', pinned: true, storyDay: 1);
    await addCard(content: 'strong one', intensity: 'strong', storyDay: 1);
    await addCard(content: 'dream one', kind: 'dream', storyDay: 2);
    await addCard(content: 'mild filler', intensity: 'mild');
    final entries = await feed.entriesFor(
      sessionId: sid,
      characterId: cid,
      messages: const [],
    );
    expect(entries.map((e) => e.text), [
      'pinned one',
      'strong one',
      'dream one',
    ]);
    expect(entries.map((e) => e.kind), ['memory', 'memory', 'dream']);
  });

  test('chance-time narrations join from messages with stripped text',
      () async {
    final messages = [
      ChatMessage(text: 'hi', sender: 'User', isUser: true),
      ChatMessage(
        text: '[🎰 CHANCE TIME! A stranger knocks.]',
        sender: 'System',
        isUser: false,
        metadata: {'is_chance_time_narration': true},
      ),
    ];
    final entries = await feed.entriesFor(
      sessionId: sid,
      characterId: cid,
      messages: messages,
    );
    expect(entries.single.kind, 'chance');
    expect(entries.single.text, 'A stranger knocks.');
    expect(entries.single.position, 1);
  });

  test('rings and achieved objectives appear; abandoned/active ones do not',
      () async {
    await db.insertGrowthRing(
      GrowthRingsCompanion(
        id: const Value('r1'),
        sessionId: const Value(sid),
        characterId: const Value(cid),
        content: const Value('learned to trust again'),
        category: const Value('trait'),
      ),
    );
    await db.into(db.objectives).insert(
      ObjectivesCompanion(
        id: const Value('o1'),
        characterId: const Value(cid),
        chatId: const Value(sid),
        objective: const Value('teach him to sail'),
        active: const Value(false),
        tasks: Value(
          jsonEncode([
            {'description': 'a', 'completed': true},
            {'description': 'b', 'completed': true},
          ]),
        ),
      ),
    );
    await db.into(db.objectives).insert(
      ObjectivesCompanion(
        id: const Value('o2'),
        characterId: const Value(cid),
        chatId: const Value(sid),
        objective: const Value('still going'),
        active: const Value(true),
        tasks: const Value('[]'),
      ),
    );
    final entries = await feed.entriesFor(
      sessionId: sid,
      characterId: cid,
      messages: const [],
    );
    expect(entries.map((e) => e.kind).toSet(), {'ring', 'objective'});
    expect(
      entries.map((e) => e.text),
      containsAll([
        'learned to trust again',
        'Objective achieved: teach him to sail',
      ]),
    );
  });

  test('ordering follows story position via receipts', () async {
    await addCard(
      content: 'late moment',
      pinned: true,
      storyDay: 3,
      positions: [40],
    );
    await addCard(
      content: 'early moment',
      pinned: true,
      storyDay: 1,
      positions: [5],
    );
    final messages = [
      for (int i = 0; i < 20; i++)
        ChatMessage(text: 'm$i', sender: 'User', isUser: true),
    ];
    messages[10] = ChatMessage(
      text: '[🎰 CHANCE TIME! Mid-story strike.]',
      sender: 'System',
      isUser: false,
      metadata: {'is_chance_time_narration': true},
    );
    final entries = await feed.entriesFor(
      sessionId: sid,
      characterId: cid,
      messages: messages,
    );
    expect(entries.map((e) => e.text), [
      'early moment',
      'Mid-story strike.',
      'late moment',
    ]);
  });
}
