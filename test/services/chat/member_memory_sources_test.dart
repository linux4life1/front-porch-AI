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

// PR 4: in a group, a speaker reads this chat's windows under their own key and
// the old pool only. A linked memory source keeps its other-chat windows, but
// its windows from THIS chat (a scene the speaker may have missed) are never
// read, whether its owner is still in the group, was removed, or was renamed.
// The wide fetch that makes this possible happens only when a source is linked.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/group_memory_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockPathProvider('member_memory_sources');

  late GroupMemoryHarness h;
  tearDown(() => h.close());

  Future<void> linkAdaTo(String sourceId) =>
      (h.db.update(h.db.characters)..where((c) => c.id.equals('lib-ada')))
          .write(CharactersCompanion(memorySources: Value('["$sourceId"]')));

  test(
    'a removed member linked as a source: other chats yes, this chat never',
    () async {
      h = await GroupMemoryHarness.open(withCy: true);
      await h.seedLongChat();
      await h.window(GroupMemoryHarness.adaKey, 'ADAONLY window', 3);
      await h.window('Cy_lib', 'CYTHISCHAT window', 6);
      await h.db.insertEmbedding(
        MessageEmbeddingsCompanion(
          sessionId: const Value('some-other-chat'),
          characterId: const Value('Cy_lib'),
          positionStart: const Value(0),
          positionEnd: const Value(2),
          content: const Value('CYOTHERCHAT window'),
          embedding: Value(FakeVectorsBytes.bytes),
          dimensions: const Value(4),
        ),
      );
      await linkAdaTo('Cy_lib');
      await h.openGroup();
      await h.chat.loadSession(GroupMemoryHarness.sessionId);

      final repo = GroupChatRepository(h.storage, h.db);
      expect(
        await h.chat.removeCharacterFromGroup(h.member('Cy'), repo),
        isTrue,
      );
      expect(h.chat.isGroupMode, isTrue, reason: 'two are left, still a group');
      expect(
        (await h.rows('Cy_lib')).where((r) => r.content.contains('THISCHAT')),
        isNotEmpty,
        reason:
            'the leftover window is still there; the read rule must cover it',
      );

      await h.say('Ada', 'Ada, remember what you said?');
      final body = h.backend.lastChatBody;
      expect(body, contains('CYOTHERCHAT'), reason: 'cross-chat recall stays');
      expect(body, contains('ADAONLY'));
      expect(body, isNot(contains('CYTHISCHAT')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('with no linked source, retrieval asks for the normal limit', () async {
    h = await GroupMemoryHarness.open(withCy: true);
    await h.seedLongChat();
    await h.window(GroupMemoryHarness.adaKey, 'ADAONLY window', 3);
    await h.openGroup();
    await h.chat.loadSession(GroupMemoryHarness.sessionId);

    await h.say('Ada', 'Ada, remember what you said?');
    expect(h.memory.asked, isNotEmpty);
    expect(h.memory.asked.last.limit, h.chat.groupRetrievalCount);
    expect(h.memory.asked.last.limit, lessThan(9999));

    // A linked source is what makes the wide fetch worth its cost.
    await linkAdaTo('Cy_lib');
    await h.say('Ada', 'Ada, remember what you said again?');
    expect(h.memory.asked.last.sources, contains('Cy_lib'));
    expect(h.memory.asked.last.limit, 9999);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
