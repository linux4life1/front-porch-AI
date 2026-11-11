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

// PR 4: the paths that move or re-key a group's per-member memory: an
// imported group chat, a lite member promoted mid-chat, and a group that
// collapses to a 1:1. Real ChatService, real MemoryService over constant fake
// vectors; what is asserted is which rows exist under which key.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../helpers/group_memory_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockPathProvider('member_memory_cast');

  late GroupMemoryHarness h;
  tearDown(() => h.close());

  test(
    'an imported group chat with no stamps is filed once for every member',
    () async {
      h = await GroupMemoryHarness.open();
      await h.openGroup();
      final lines = [
        for (var i = 0; i < 12; i++)
          {
            'name': i.isEven ? 'User' : (i % 4 == 1 ? 'Ada' : 'Bea'),
            'is_user': i.isEven,
            'mes': 'IMPORTED line $i about the porch',
          },
      ];
      await h.chat.importChatPackage(
        Uint8List.fromList(
          utf8.encode(jsonEncode({'chat_metadata': {}, 'messages': lines})),
        ),
      );
      // The backfill is fire-and-forget; wait until it stops adding rows.
      var last = -1;
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final n = (await h.db.select(h.db.messageEmbeddings).get()).length;
        if (n > 0 && n == last) break;
        last = n;
      }
      final beaKey = memoryKeyFor(h.member('Bea'), const []);
      for (final key in [GroupMemoryHarness.adaKey, beaKey]) {
        final rows = await h.rows(key);
        final ranges = rows
            .map((r) => (r.positionStart, r.positionEnd))
            .toList();
        expect(ranges.toSet(), hasLength(ranges.length), reason: '$key once');
        expect(ranges, hasLength(4), reason: '$key gets every window');
        expect(rows.first.content, contains('IMPORTED'));
      }
      expect(await h.rows('group_${GroupMemoryHarness.groupId}'), isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'promoting a lite member keeps one key, and they recall what they saw',
    () async {
      h = await GroupMemoryHarness.open(beaLite: true);
      await h.openGroup();
      expect(h.member('Bea').isLite, isTrue);
      final before = memoryKeyFor(h.member('Bea'), h.library.characters);
      for (final n in ['one', 'two', 'three']) {
        await h.say('Ada', 'PRELITE $n');
      }
      await h.chat.promoteGuestToFull(h.member('Bea'));
      expect(h.member('Bea').isLite, isFalse);
      final after = memoryKeyFor(h.member('Bea'), h.library.characters);
      expect(
        after,
        before,
        reason: 'promotion never changes who owns a memory',
      );
      for (final n in ['one', 'two', 'three']) {
        await h.say('Ada', 'POSTFULL $n');
      }
      final rows = await h.rows(after);
      bool has(String m) => rows.any((r) => r.content.contains(m));
      expect(has('PRELITE'), isTrue, reason: 'filed while lite, same key');
      expect(has('POSTFULL'), isTrue, reason: 'filed after promotion');
      final recalled = await h.memory.retrieve(
        queryText: 'the porch',
        sourceCharacterIds: [after],
        currentSessionId: h.chat.currentSessionId!,
        inContextStart: 1000,
        limit: 99,
        sessionScopedCharacterIds: {after},
      );
      expect(recalled.any((m) => m.content.contains('PRELITE')), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'collapsing to a 1:1 keeps the survivor\'s windows and the old pool',
    () async {
      h = await GroupMemoryHarness.open();
      await h.seedLongChat();
      final pool = 'group_${GroupMemoryHarness.groupId}';
      for (var at = 0; at + 2 < 70; at += 3) {
        await h.window(pool, 'filler $at', at, matches: false);
      }
      await h.window(GroupMemoryHarness.adaKey, 'ADAOWN window', 3);
      await h.window('mem-bea', 'BEAOWN window', 6);
      await h.window(pool, 'OLDPOOL window', 9);
      await h.openGroup();
      await h.chat.loadSession(GroupMemoryHarness.sessionId);

      final repo = GroupChatRepository(h.storage, h.db);
      expect(
        await h.chat.removeCharacterFromGroup(h.member('Bea'), repo),
        isTrue,
      );
      expect(h.chat.isGroupMode, isFalse, reason: 'it collapsed to a 1:1');
      expect(h.chat.activeCharacter?.name, 'Ada');

      expect(
        await h.rows(pool),
        isEmpty,
        reason: 'the pool moved to the survivor',
      );
      await h.chat.sendMessage('Ada, remember what you said?');
      await h.settle();
      final body = h.backend.lastChatBody;
      expect(body, contains('ADAOWN'));
      expect(
        body,
        contains('OLDPOOL'),
        reason: 'the pool is the survivor\'s now',
      );
      expect(body, isNot(contains('BEAOWN')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('a 1:1 forked into a group files the host\'s windows under the host '
      'member, not the old shared pool', () async {
    h = await GroupMemoryHarness.open();
    final nia = CharacterCard(
      name: 'Nia',
      description: 'Exists only inside the member-memory test.',
      firstMessage: 'The porch light hums.',
    )..dbId = 'char-nia';
    await h.chat.setActiveCharacter(nia);
    final solo = h.chat.currentSessionId!;
    await h.db.insertEmbedding(
      MessageEmbeddingsCompanion(
        sessionId: Value(solo),
        characterId: Value(nia.stableGroupId),
        positionStart: const Value(0),
        positionEnd: const Value(2),
        content: const Value('SOLO window'),
        embedding: Value(FakeVectorsBytes.bytes),
        dimensions: const Value(4),
      ),
    );
    final group = await h.chat.forkToGroupChat([
      CharacterCard(name: 'Rue', firstMessage: 'Hi.')..dbId = 'char-rue',
    ], GroupChatRepository(h.storage, h.db));
    expect(group, isNotNull);
    final grouped = h.chat.currentSessionId!;
    expect(grouped, isNot(solo));

    final host = h.member('Nia');
    final key = memoryKeyFor(host, h.library.characters);
    Future<List<String>> inChat(String owner) async => [
      for (final r in await h.rows(owner))
        if (r.sessionId == grouped) r.content,
    ];
    expect(await inChat(key), ['SOLO window']);
    expect(await inChat('group_${group!.id}'), isEmpty);
    expect(
      (await h.rows(nia.stableGroupId)).where((r) => r.sessionId == solo),
      hasLength(1),
      reason: 'a copy, not a move',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
