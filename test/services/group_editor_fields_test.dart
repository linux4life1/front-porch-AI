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

// The group's own copies of the 1:1 card fields (schema v66): each reaches
// the prompt where its 1:1 twin does, and the Group Card carries all of them.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../helpers/group_memory_harness.dart';

GroupChat _full() => GroupChat(
  id: GroupMemoryHarness.groupId,
  name: 'Cast',
  personality: 'GROUPPERSONALITYMARK',
  mesExample: 'GROUPEXAMPLEMARK',
  postHistoryInstructions: 'GROUPPOSTHISTORYMARK',
  tags: const ['slice of life', 'friends'],
  storyStartDate: '2026-05-04',
  storyStartTime: '07:30',
  realismVerificationEnabled: true,
  realismVerificationStrictness: 5,
  realismVerificationMaxReprocesses: 3,
  needsDirectorAuthority: true,
  characterAuthorNotes: const {'mem-ada': MemberAuthorNote('Keep it dry.', 7)},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockPathProvider('group_fields');

  test('a Group Card carries every new field through export and import', () {
    final g = _full();
    final card = GroupCard(
      name: g.name,
      members: const [],
      turnOrder: 'roundRobin',
      personality: g.personality,
      postHistoryInstructions: g.postHistoryInstructions,
      mesExample: g.mesExample,
      tags: g.tags,
      storyStartDate: g.storyStartDate,
      storyStartTime: g.storyStartTime,
      realismVerificationEnabled: g.realismVerificationEnabled,
      realismVerificationStrictness: g.realismVerificationStrictness,
      realismVerificationMaxReprocesses: g.realismVerificationMaxReprocesses,
      needsDirectorAuthority: g.needsDirectorAuthority,
      characterAuthorNotes: g.characterAuthorNotes,
    );
    final back = GroupCard.fromJson(
      jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
    );
    expect(back.personality, g.personality);
    expect(back.postHistoryInstructions, g.postHistoryInstructions);
    expect(back.mesExample, g.mesExample);
    expect(back.tags, g.tags);
    expect((back.storyStartDate, back.storyStartTime), ('2026-05-04', '07:30'));
    expect(back.realismVerificationEnabled, isTrue);
    expect(back.realismVerificationStrictness, 5);
    expect(back.realismVerificationMaxReprocesses, 3);
    expect(back.needsDirectorAuthority, isTrue);
    expect(
      back.characterAuthorNotes['mem-ada'],
      g.characterAuthorNotes['mem-ada'],
    );
  });

  test('a card from an older app, with none of them, reads as none', () {
    final back = GroupCard.fromJson({
      'name': 'Old',
      'members': <Object>[],
      'turn_order': 'roundRobin',
    });
    expect(back.personality, '');
    expect(back.tags, isEmpty);
    expect(back.realismVerificationEnabled, isFalse);
    expect(back.realismVerificationStrictness, 3);
  });

  test("the group's Personality and Post-History reach "
      "each speaker's prompt, its old Example Dialogue does not", () async {
    final h = await GroupMemoryHarness.open();
    addTearDown(h.close);
    await h.chat.setActiveGroup(
      _full(),
      groupRepo: GroupChatRepository(h.storage, h.db),
    );
    await h.say('Ada', 'Ada, what do you think?');
    final body = h.backend.lastChatBody;
    expect(body, contains('GROUPPERSONALITYMARK'));
    expect(body, isNot(contains('GROUPEXAMPLEMARK')));
    expect(body, contains('GROUPPOSTHISTORYMARK'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
