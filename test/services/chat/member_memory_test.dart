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

// PR 4 of docs/design/one-chat-ux.md: group memory is per member. A character
// recalls only what they were there for, never a scene they were Away for.
// A real group chat writes its windows through the live reply path; reads go
// through a real turn. Embeddings are constant fake vectors, so every window
// scores alike: these tests prove WHICH windows are filed and read, and say
// nothing about how a model ranks text.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/group_memory_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockPathProvider('member_memory');

  late GroupMemoryHarness h;

  group('keys and masks', () {
    test('a member is keyed by library identity, not tier or roster id', () {
      final lib = CharacterCard(name: 'Ada', imagePath: '/lib/Ada_lib.png');
      final member = CharacterCard(name: 'Ada', imagePath: '/g/mem-ada.png')
        ..originStableId = 'Ada_lib';
      expect(memoryKeyFor(member, [lib]), 'Ada_lib');
      // Promotion from a lite guest changes the tier, never the identity.
      final promoted = CharacterCard(
        name: 'Ada',
        imagePath: '/g/mem-ada.png',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
      )..originStableId = 'Ada_lib';
      expect(memoryKeyFor(promoted, [lib]), 'Ada_lib');
      // No origin and no library match: the member's own store id.
      final stranger = CharacterCard(
        name: 'Zed',
        imagePath: '/g/zed.png',
        dbId: 'mem-zed',
      );
      expect(memoryKeyFor(stranger, const []), 'mem-zed');
    });

    test('masks follow the stamps; unstamped lines inherit, then roster', () {
      ChatMessage line(String text, [List<String>? present]) => ChatMessage(
        text: text,
        sender: 'x',
        isUser: false,
        metadata: present == null ? null : {kMemoryPresentMeta: present},
      );
      final masks = presentLineMasks(
        [
          line('legacy'), // before any stamp: whole roster
          line('a', ['ada', 'mem-bea']),
          line('note'), // unstamped: whoever the line before saw
          line('b', ['ada']),
          line('c', ['ada', 'mem-bea']),
        ],
        ['ada', 'mem-bea'],
      );
      expect(masks['ada'], [true, true, true, true, true]);
      expect(masks['mem-bea'], [true, true, true, false, true]);
    });
  });

  test(
    'who was present is not exported: another library\'s ids mean nothing',
    () {
      final m = ChatMessage(
        text: 'hi',
        sender: 'Ada',
        isUser: false,
        metadata: {
          kMemoryPresentMeta: ['Ada_lib'],
          'keep': 1,
        },
      );
      final out = messagesExtraEntry(0, m);
      expect(out['metadata'], {'keep': 1});
      expect((out['swipe_metadata'] as List).single, {'keep': 1});
      expect(
        m.metadata,
        contains(kMemoryPresentMeta),
        reason: 'live untouched',
      );
    },
  );

  group('a real group chat', () {
    setUp(() async {
      h = await GroupMemoryHarness.open();
      await h.openGroup();
    });
    tearDown(() => h.close());

    test('a window from a member\'s Away stretch is filed and read only for '
        'those who were there', () async {
      await h.say('Ada', 'ALPHA one');
      await h.say('Ada', 'ALPHA two');
      expect(await h.chat.setGroupMemberAway(h.idOf('Bea'), away: true), true);
      for (final n in ['one', 'two', 'three', 'four']) {
        await h.say('Ada', 'BRAVO $n');
      }
      expect(await h.chat.setGroupMemberAway(h.idOf('Bea'), away: false), true);
      await h.say('Ada', 'CHARLIE one');
      await h.say('Ada', 'CHARLIE two');

      final beaKey = memoryKeyFor(h.member('Bea'), const []);
      final ada = await h.rows(GroupMemoryHarness.adaKey);
      final bea = await h.rows(beaKey);
      expect(ada, isNotEmpty);
      expect(bea, isNotEmpty);
      bool has(List<MessageEmbedding> rs, String m) =>
          rs.any((r) => r.content.contains(m));
      expect(has(ada, 'BRAVO'), isTrue, reason: 'Ada was there');
      expect(has(bea, 'BRAVO'), isFalse, reason: 'Bea was Away');
      expect(has(bea, 'ALPHA'), isTrue, reason: 'before she left');
      expect(has(bea, 'CHARLIE'), isTrue, reason: 'after she came back');
      expect(
        await h.rows('group_${GroupMemoryHarness.groupId}'),
        isEmpty,
        reason: 'new windows are never filed under the old shared id',
      );

      // Reopening the chat keeps who was there: the stamps ride the messages.
      await h.chat.loadSession(h.chat.currentSessionId!);
      final bravo = h.chat.messages.firstWhere(
        (m) => m.isUser && m.text.contains('BRAVO one'),
      );
      final seen = bravo.activeMetadata?[kMemoryPresentMeta] as List?;
      expect(seen, contains(GroupMemoryHarness.adaKey));
      expect(seen, isNot(contains(beaKey)));

      // And the read side, on those same rows.
      Future<List<RetrievedMemory>> recall(String key) => h.memory.retrieve(
        queryText: 'the porch',
        sourceCharacterIds: [key],
        currentSessionId: h.chat.currentSessionId!,
        inContextStart: 1000,
        limit: 99,
        sessionScopedCharacterIds: {key},
      );
      expect(
        (await recall(beaKey)).any((m) => m.content.contains('BRAVO')),
        isFalse,
      );
      expect(
        (await recall(
          GroupMemoryHarness.adaKey,
        )).any((m) => m.content.contains('BRAVO')),
        isTrue,
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a window is filed once, and a swipe or regen never files it '
        'under the wrong member', () async {
      for (var i = 0; i < 4; i++) {
        await h.say('Ada', 'DELTA $i');
      }
      final before = {
        for (final k in [
          GroupMemoryHarness.adaKey,
          memoryKeyFor(h.member('Bea'), const []),
        ])
          k: (await h.rows(k)).map((r) => (r.positionStart, r.positionEnd)),
      };
      for (final e in before.entries) {
        expect(e.value.toSet(), hasLength(e.value.length), reason: e.key);
      }
      await h.chat.regenerateLastMessage();
      await h.settle();
      // Continue extends a reply that already carries its stamp, and the Next
      // button's reply is stamped with its own speaker.
      final last = h.chat.messages.last;
      final stamp = List.of(last.activeMetadata![kMemoryPresentMeta] as List);
      await h.chat.continueGeneration();
      await h.settle();
      expect(h.chat.messages.last.activeMetadata![kMemoryPresentMeta], stamp);
      h.chat.setNextCharacter(h.member('Bea'));
      await h.chat.triggerNextCharacter();
      await h.settle();
      expect(h.chat.messages.last.sender, 'Bea');
      expect(
        h.chat.messages.last.activeMetadata![kMemoryPresentMeta],
        contains(memoryKeyFor(h.member('Bea'), const [])),
      );
      for (final e in before.entries) {
        final now = (await h.rows(
          e.key,
        )).map((r) => (r.positionStart, r.positionEnd)).toList();
        expect(now.toSet(), hasLength(now.length), reason: 'no double filing');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('reading', () {
    setUp(() async {
      h = await GroupMemoryHarness.open();
      await h.seedLongChat();
      // A chat from before per-member memory has every window under the one
      // shared id. Only OLDPOOL matches the fake query; the rest is filler a
      // real search would score low, so the top hits are the marked windows.
      final pool = 'group_${GroupMemoryHarness.groupId}';
      for (var at = 0; at + 2 < 70; at += 3) {
        await h.window(pool, 'filler $at', at, matches: false);
      }
      await h.window(GroupMemoryHarness.adaKey, 'ADAONLY window', 3);
      await h.window('mem-bea', 'BEAONLY window', 6);
      await h.window(pool, 'OLDPOOL window', 9);
      await h.openGroup();
      await h.chat.loadSession(GroupMemoryHarness.sessionId);
      expect(h.chat.messages, hasLength(70), reason: 'the seed must load');
    });
    tearDown(() => h.close());

    test('each member reads their own windows plus the old shared pool, '
        'never another member\'s', () async {
      await h.say('Ada', 'Ada, remember what you said?');
      expect(h.memory.asked, isNotEmpty, reason: 'retrieval never ran');
      final ada = h.backend.lastChatBody;
      expect(ada, contains('ADAONLY'));
      expect(ada, contains('OLDPOOL'), reason: 'the fallback reaches Ada');
      expect(ada, isNot(contains('BEAONLY')));
      expect(h.memory.asked.last.sources, isNot(contains('mem-bea')));

      await h.say('Bea', 'Bea, remember what you said?');
      final bea = h.backend.lastChatBody;
      expect(bea, contains('BEAONLY'));
      expect(bea, contains('OLDPOOL'), reason: 'the fallback reaches Bea');
      expect(bea, isNot(contains('ADAONLY')));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('rewrites', () {
    setUp(() async {
      h = await GroupMemoryHarness.open();
      await h.seedLongChat();
      await h.window(GroupMemoryHarness.adaKey, 'ADA early', 0);
      await h.window('mem-bea', 'BEA early', 0);
      await h.window(GroupMemoryHarness.adaKey, 'ADA late', 60);
      await h.window('mem-bea', 'BEA late', 60);
      await h.openGroup();
      await h.chat.loadSession(GroupMemoryHarness.sessionId);
    });
    tearDown(() => h.close());

    test(
      'a delete purges every member\'s windows citing it, and only those',
      () async {
        h.chat.deleteMessage(61);
        for (var i = 0; i < 30; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        Future<List<String>> corpus(String key) async => [
          for (final r in await h.rows(key)) r.content,
        ];
        expect(await corpus(GroupMemoryHarness.adaKey), ['ADA early']);
        expect(await corpus('mem-bea'), ['BEA early']);
      },
    );
  });
}
